-- lua/scoper/pickers.lua
--
-- Search-within-scope commands. Three operations, three backends auto-
-- detected at call time so the user can drop either dependency without
-- crashing the plugin.
--
--   :ScoperFind     – fuzzy-find files within active scope
--   :ScoperGrep     – live grep within active scope
--   :ScoperReplace  – ordinary grug-far only for unrestricted scope queries
--
-- Backend preference (in order):
--   1. fzf-lua    – accepts `cwd` + multiple search paths
--   2. telescope  – accepts `search_dirs` and a filtering `entry_maker`
--   3. plain vim  – findfile() / :vimgrep with explicit project paths
--
-- Ripgrep receives anchored exclude globs. Telescope filters its parsed
-- entries through the same captured matcher as the compilation database;
-- it does not approximate Neovim globs with Lua patterns.
--
-- Scoping off, or an empty include list, means everything is in scope
-- (as in is_in_scope): find/grep use the whole loaded project, without
-- the scope's excludes. Unrestricted replace retains grug-far's usual cwd.

local State = require("scoper.state")
local Path = require("scoper.path")
local Util = require("scoper.util")
local Scope = require("scoper.scope")

local M = {}

-- ---------------------------------------------------------------------------
-- Helper: get scope context as a single struct, or nil with a notify when
-- the active scope has includes but none has an existing file/search root
-- (so the user gets a clear error, not silent "search everything"
-- behavior). `dirs` is nil when the whole cwd is in scope.
-- ---------------------------------------------------------------------------
local function get_context()
  -- Refresh external saves before reading membership or rejecting stale roots.
  local context = State.context()
  local scope = State.active_scope()
  if not scope then
    vim.notify("Scoper: no active scope", vim.log.levels.WARN)
    return nil
  end
  local cwd = State.root()
  local query = Scope.query(scope, cwd, State.is_enabled())
  if query.restricted and #query.roots == 0 then
    vim.notify(
      ("Scoper: scope %q has no existing search roots. Use :ScoperAdd first."):format(
        State.active_name()
      ),
      vim.log.levels.WARN
    )
    return nil
  end
  return {
    name = query.restricted and State.active_name() or "all",
    cwd = cwd,
    dirs = query.roots,
    excludes = query.excludes,
    restricted = query.restricted,
    in_scope = query.matches,
    context = context,
  }
end
M._context = get_context

-- ---------------------------------------------------------------------------
-- The tools match an exclude against the paths they list: relative to the
-- cwd for a search dir inside it, but the full path for a dir outside it,
-- where is_in_scope matches relative to that include dir. So each exclude
-- is paired with what it is relative to: { glob = g } for the cwd, and
-- { glob = g, root = dir } for each search dir outside the cwd. An
-- absolute exclude is made relative to the cwd or the outside dir it lies
-- in. One in neither, or with a wildcard above them (C:/**/vendor), is
-- dropped on Windows; on Unix it anchors at each root, as any "/x" does.
-- The second result says whether any dir is outside the cwd.
-- ---------------------------------------------------------------------------
function M._anchor_excludes(excludes, dirs, cwd)
  local roots = { cwd }
  for _, d in ipairs(dirs or {}) do
    if not Path.is_under(d, cwd) then table.insert(roots, d) end
  end
  local out = {}
  for _, ex in ipairs(excludes) do
    local abs, placed = Path.is_absolute(ex), false
    -- the directory the pattern names before its first wildcard
    local lit = ex:match("^[^*?[{]*")
    if lit ~= ex then lit = lit:match("^(.*)/") or "" end
    for i, root in ipairs(roots) do
      if abs and Path.is_under(lit, root) then
        local rel = Path.relative(ex, root)
        rel = rel == "." and "**" or rel
        table.insert(out, { glob = "/" .. rel, root = i > 1 and root or nil })
        placed = true
      end
    end
    if not placed and not (abs and Path.is_windows) then
      for i, root in ipairs(roots) do
        table.insert(out, { glob = ex, root = i > 1 and root or nil })
      end
    end
  end
  return out, #roots > 1
end

-- Telescope entry_maker is a public filtering hook: returning nil discards
-- an entry. Wrap the normal/configured maker after it has parsed the filename,
-- so every supported glob uses State's matcher without a lossy translation.
-- Keep a matcher snapshot for the picker lifetime, even if the active scope
-- or global project changes while a picker is open.
function M._telescope_entry_maker(ctx, factory, opts, hide_git)
  local make = opts.entry_maker
  local in_scope = ctx.in_scope or State.matcher(ctx.cwd)
  local outside_git = hide_git
    and State.build_matcher({
      include = ctx.dirs or { ctx.cwd },
      exclude = { ".git" },
    }, ctx.cwd)
  return function(line)
    if not make then make = factory(opts) end
    local entry = make(line)
    if not entry then return nil end
    local path = entry.path or entry.filename or (hide_git and entry.value)
    if type(path) ~= "string" or path == "" then return nil end
    if not in_scope(path) or outside_git and not outside_git(path) then return nil end
    return entry
  end
end

-- The backend expands environment variables and special leading characters
-- even in supplied paths. Refuse a search whose actual target would change;
-- filtering wrong-directory results alone would only conceal missing results.
local function telescope_literal_paths(ctx)
  local expand = require("telescope.utils").path_expand
  local paths = { ctx.cwd }
  for _, dir in ipairs(ctx.dirs or {}) do
    paths[#paths + 1] = Path.relative(dir, ctx.cwd)
  end
  for _, path in ipairs(paths) do
    local ok, expanded = pcall(expand, path)
    if
      not ok
      or Path.key(Path.absolute(expanded, ctx.cwd)) ~= Path.key(Path.absolute(path, ctx.cwd))
    then
      vim.notify(
        ("Scoper: Telescope cannot preserve the literal directory %q; search refused."):format(path),
        vim.log.levels.WARN
      )
      return false
    end
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Backend detection lives in scoper.util (has / prefer_fzf). Re-checked
-- per call so a backend installed mid-session is picked up.
-- ---------------------------------------------------------------------------
local has = Util.has

-- The search dirs relative to the project root when inside it, the way fzf-lua
-- passes `search_paths`: the tools match excludes against the paths they
-- list, which then don't contain the folders above the cwd.
local function cwd_relative(dirs, cwd)
  if not dirs then return nil end
  return vim.tbl_map(function(d)
    return Path.relative(d, cwd)
  end, dirs)
end

-- ---------------------------------------------------------------------------
-- Telescope: non-closing <M-p> mapping that shows the highlighted entry's
-- absolute path in the prompt title without dismissing the picker.
-- This mapping is implemented only for Telescope. Registered through
-- telescope's `map`: keys set behind its back are overwritten by its
-- defaults, and <C-p> is its "previous entry".
--
-- We update the prompt's title rather than firing vim.notify so the path
-- doesn't fight the picker for screen real estate.
-- ---------------------------------------------------------------------------
local function attach_show_path_mapping(prompt_bufnr, map)
  local action_state = require("telescope.actions.state")

  local function show_path()
    local entry = action_state.get_selected_entry()
    if not entry then return end
    local p = entry.path or entry.filename or entry.value
    if not p then return end
    -- Make it absolute against telescope's cwd for unambiguous display.
    local is_abs = p:match("^/") or p:match("^[A-Za-z]:[/\\]")
    if not is_abs then
      local cwd = (action_state.get_current_picker(prompt_bufnr) or {}).cwd or vim.uv.cwd()
      p = vim.fs.joinpath(cwd, p)
    end
    p = vim.fs.normalize(p)
    -- Telescope doesn't re-render the prompt title by itself: it shows
    -- this path until the next <M-p> or until the picker closes.
    local picker = action_state.get_current_picker(prompt_bufnr)
    if picker and picker.prompt_border and picker.prompt_border.change_title then
      picker.prompt_border:change_title(p)
    else
      -- Older telescope, or different border type — fall back to notify.
      vim.notify(p, vim.log.levels.INFO, { title = "Scoper" })
    end
  end

  map({ "i", "n" }, "<M-p>", show_path, { desc = "Scoper: show full path" })
  -- Returning true keeps telescope's own default mappings active.
  return true
end

-- ---------------------------------------------------------------------------
-- One ripgrep exclude flag, shell-quoted. fzf-lua's rg_opts / fd_opts are
-- spliced into a SHELL command line, so the glob must be escaped:
-- unquoted, a glob containing a space splits into two arguments and `*` /
-- `**` are exposed to the shell's pathname expansion. The pickers pass
-- fzf-lua's own escaper (it knows the cmd.exe rules fzf-lua runs with on
-- Windows); vim.fn.shellescape follows 'shell' and 'shellslash' instead.
-- Not used for grug-far, whose `flags` field is parsed by grug-far itself
-- rather than by a shell. Extracted (underscore = internal) so
-- pickers_spec can assert the quoting.
-- ---------------------------------------------------------------------------
function M._rg_exclude(glob, escape)
  return (escape or vim.fn.shellescape)("--glob=!" .. glob)
end

-- ripgrep globs for `excludes` when searching `dirs` (M._anchor_excludes).
-- Below a dir outside the cwd ripgrep matches the full path, so the glob
-- goes below that dir, with the dir's glob syntax escaped and a leading
-- "/" doubled (ripgrep strips one as the anchor). With such a dir in the
-- search, a cwd glob matching at any depth is split into forms whose
-- first component must be a name — not "" or a drive, as in a full path —
-- so it can't match the folders above that dir.
function M._rg_globs(excludes, dirs, cwd)
  local anchored, outside = M._anchor_excludes(excludes, dirs, cwd or vim.uv.cwd())
  local out = {}
  for _, a in ipairs(anchored) do
    local body, deep = a.glob, not a.glob:gsub("/+$", ""):find("/", 1, true)
    while body:sub(1, 3) == "**/" do
      body, deep = body:sub(4), true
    end
    if a.root then
      local dir = a.root:gsub("[%[{}*?]", "[%0]")
      local glob = dir .. (deep and "/**/" or "/") .. body:gsub("^/+", "")
      table.insert(out, (glob:gsub("^/", "//")))
    elseif outside and deep then
      table.insert(out, "/" .. body)
      for _, head in ipairs(Path.is_windows and { "?", "?*[!:]" } or { "?*" }) do
        table.insert(out, head .. "/**/" .. body)
      end
    else
      table.insert(out, a.glob)
    end
  end
  return out
end

-- ripgrep matches globs case-sensitively unless told otherwise; on Windows
-- the clangd filter and is_in_scope ignore case, so ripgrep must too.
local function rg_case_flag()
  return Path.is_windows and " --glob-case-insensitive" or ""
end

-- :ScoperFind lists files reached through directory links below the
-- scope's dirs, even when the link points outside them; set
-- `vim.g.scoper_follow_links = false` to stay inside the dirs themselves.
-- Read at call time, applied to both the fzf-lua and telescope backends.
local function follow_links()
  return vim.g.scoper_follow_links ~= false
end

-- A query may include individual files/globs, whose literal search roots
-- are intentionally broader than the exact include predicate. Filter raw
-- backend rows before decorating them, using the captured scope. Closures
-- stay in this editor: fzf-lua's subprocess serializer cannot retain them.
function M._fzf_transform(ctx, grep)
  return function(line, opts)
    local path = line
    if grep then path = require("fzf-lua.path").entry_to_file(line, { cwd = ctx.cwd }).path end
    if type(path) ~= "string" or not ctx.in_scope(path) then return nil end
    return require("fzf-lua.make_entry").file(line, opts)
  end
end

local function exact_fzf(opts, ctx, grep)
  if ctx.restricted then
    opts.multiprocess = false
    opts.fn_transform = M._fzf_transform(ctx, grep)
  end
  return opts
end

-- ---------------------------------------------------------------------------
-- :ScoperFind
-- ---------------------------------------------------------------------------

-- Build the 'path' value the plain-vim :find fallback uses: each scope dir
-- with a recursive "/**" suffix, comma-joined. Spaces and commas inside a
-- dir are backslash-escaped, as 'path' requires (:h 'path'); an unescaped
-- comma would split one dir into two bogus entries. Dirs are normalized to
-- forward slashes, so a backslash here is always an escape, never a
-- Windows separator.
--
-- The "/**" MUST be appended to EVERY dir: `table.concat(dirs, ",") ..
-- "/**"` would attach it to only the LAST dir, and `:find` would treat the
-- others as non-recursive. Extracted (underscore = internal) so
-- pickers_spec can assert the per-dir behaviour.
function M._find_path(dirs)
  local parts = {}
  for _, d in ipairs(dirs) do
    parts[#parts + 1] = (d:gsub("[ ,]", "\\%0")) .. "/**"
  end
  return table.concat(parts, ",")
end

-- fzf-lua files() options for `ctx`. ripgrep lists the files when it is
-- installed (fzf-lua would pick fd first; fd can't match excludes
-- case-insensitively), with the search dirs appended to the command the
-- way fzf-lua appends `search_paths`: relative to the project root and quoted.
-- `.git` is excluded explicitly because hidden files are listed.
function M._fzf_files_opts(ctx, escape)
  local cwd = ctx.cwd or State.root()
  local opts = { prompt = ("Find [%s]> "):format(ctx.name), cwd = cwd }
  local excludes = vim.list_extend({ ".git" }, ctx.excludes)
  local follow = follow_links() and " --follow" or ""
  if vim.fn.executable("rg") == 1 then
    local parts = { "rg --files --color=never --hidden" .. follow .. rg_case_flag() }
    for _, ex in ipairs(M._rg_globs(excludes, ctx.dirs, cwd)) do
      table.insert(parts, M._rg_exclude(ex, escape))
    end
    -- Quoting protects shell syntax; -- protects directory names that rg
    -- would otherwise parse as options (for example an include named -U).
    if ctx.dirs and #ctx.dirs > 0 then table.insert(parts, "--") end
    for _, d in ipairs(ctx.dirs or {}) do
      table.insert(parts, escape(Path.relative(d, cwd)))
    end
    opts.cmd = table.concat(parts, " ")
    return exact_fzf(opts, ctx, false)
  end
  -- Setting fd_opts REPLACES fzf-lua's default fd options wholesale (it
  -- doesn't merge), so the essentials are rebuilt around our excludes,
  -- which fd gets as written.
  local parts = { "--color=never --type f --type l --hidden" .. follow }
  for _, ex in ipairs(excludes) do
    table.insert(parts, "--exclude " .. escape(ex))
  end
  opts.fd_opts = table.concat(parts, " ")
  opts.search_paths = ctx.dirs
  return exact_fzf(opts, ctx, false)
end

function M.find()
  local ctx = get_context()
  if not ctx then return end
  -- fd accepts only directory roots. With individual-file includes and no
  -- ripgrep, retain the exact native lookup instead of handing fd bad roots.
  local files_without_rg = vim.fn.executable("rg") ~= 1
    and vim.iter(ctx.dirs or {}):any(function(root)
      local stat = vim.uv.fs_stat(root)
      return stat and stat.type == "file"
    end)

  -- fzf-lua first (snappier on big trees). We search ALL of the scope's
  -- directories, not just the first.
  --
  -- Resolve every picker from the loaded project root. A window-local or
  -- tab-local cwd must not change the meaning of project-relative excludes.
  --
  -- To force the telescope backend instead, set
  -- `vim.g.scoper_picker = "telescope"`.
  if not files_without_rg and Util.prefer_fzf() then
    require("fzf-lua").files(M._fzf_files_opts(ctx, require("fzf-lua.libuv").shellescape))
    return
  end

  if not files_without_rg and has("telescope.builtin") then
    if not telescope_literal_paths(ctx) then return end
    local config = require("telescope.config")
    local opts = {
      prompt_title = ("Find [%s]"):format(ctx.name),
      cwd = ctx.cwd,
      search_dirs = cwd_relative(ctx.dirs, ctx.cwd),
      hidden = true,
      follow = follow_links(),
      attach_mappings = attach_show_path_mapping,
    }
    local entry_opts = vim.tbl_extend("force", config.values, config.pickers.find_files or {}, opts)
    opts.entry_maker =
      M._telescope_entry_maker(ctx, require("telescope.make_entry").gen_from_file, entry_opts, true)
    require("telescope.builtin").find_files(opts)
    return
  end

  -- Plain-vim fallback: findfile() over the scope dirs (each made
  -- recursive, see M._find_path), then the first match that is in scope.
  -- The search path is passed to findfile() rather than set in 'path', so
  -- a prompt left open or cancelled can't leave the option changed.
  vim.ui.input({ prompt = ("Find [%s] file: "):format(ctx.name) }, function(name)
    if not name or name == "" then return end
    local file, found = M._find_in_scope(ctx, name)
    if not file then
      vim.notify(
        found > 0 and ("Scoper: %q only matches excluded files in scope %q"):format(name, ctx.name)
          or ("Scoper: no file %q in scope %q"):format(name, ctx.name),
        vim.log.levels.WARN
      )
      return
    end
    local ok, err = pcall(vim.cmd.edit, vim.fn.fnameescape(file))
    if not ok then vim.notify(tostring(err), vim.log.levels.ERROR) end
  end)
end

-- The plain-vim :ScoperFind lookup: the absolute path of the first file
-- called `name` below the scope's dirs that the scope's excludes don't
-- hide (or nil), and how many files of that name there were in all.
function M._find_in_scope(ctx, name)
  local dirs, found, seen = {}, {}, {}
  for _, root in ipairs(ctx.dirs or { ctx.cwd or State.root() }) do
    local stat = vim.uv.fs_stat(root)
    if stat and stat.type == "file" then
      if
        name == vim.fs.basename(root) or Path.key(Path.absolute(name, ctx.cwd)) == Path.key(root)
      then
        found[#found + 1], seen[Path.key(root)] = root, true
      end
    else
      dirs[#dirs + 1] = root
    end
  end
  if #dirs > 0 then
    for _, file in ipairs(vim.fn.findfile(name, M._find_path(dirs), -1)) do
      local key = Path.key(Path.absolute(file, ctx.cwd))
      if not seen[key] then
        found[#found + 1], seen[key] = file, true
      end
    end
  end
  local in_scope = ctx.in_scope or State.matcher(ctx.cwd)
  for _, f in ipairs(found) do
    local full = vim.fn.fnamemodify(f, ":p")
    if in_scope(full) then return full, #found end
  end
  return nil, #found
end

-- ---------------------------------------------------------------------------
-- :ScoperGrep
-- ---------------------------------------------------------------------------

-- fzf-lua live_grep() options for `ctx`. fzf-lua appends the query after
-- rg_opts, so they must end in `-e` like its defaults do: a query starting
-- with "-" (`-Wall`) is then still a pattern, not a flag. Use the loaded
-- project root for cwd, just as M.find does.
function M._fzf_grep_opts(ctx, query, escape)
  local cwd = ctx.cwd or State.root()
  local parts = {
    "--column --line-number --no-heading --color=always --smart-case --max-columns=4096"
      .. rg_case_flag(),
  }
  for _, ex in ipairs(M._rg_globs(ctx.excludes, ctx.dirs, cwd)) do
    table.insert(parts, M._rg_exclude(ex, escape))
  end
  table.insert(parts, "-e")
  return exact_fzf({
    prompt = ("Grep [%s]> "):format(ctx.name),
    cwd = cwd,
    search_paths = ctx.dirs,
    query = query or "",
    rg_opts = table.concat(parts, " "),
  }, ctx, true)
end

-- `pattern` for :vimgrep /…/: every "/" not already escaped gets a
-- backslash, since "/" is the delimiter. An escaped one (an odd number of
-- backslashes before it, as in "abc\/def") is left alone; escaping it again
-- would end the pattern there.
function M._vimgrep_pattern(pattern)
  return (
    pattern:gsub("(\\*)/", function(bs)
      return #bs % 2 == 0 and bs .. "\\/" or bs .. "/"
    end)
  )
end

function M.grep(initial_query)
  local ctx = get_context()
  if not ctx then return end

  if Util.prefer_fzf() then
    require("fzf-lua").live_grep(
      M._fzf_grep_opts(ctx, initial_query, require("fzf-lua.libuv").shellescape)
    )
    return
  end

  if has("telescope.builtin") then
    if not telescope_literal_paths(ctx) then return end
    local config = require("telescope.config")
    local configured = config.pickers.live_grep or {}
    local additional = configured.additional_args or config.values.additional_args
    require("telescope.builtin").live_grep({
      prompt_title = ("Grep [%s]"):format(ctx.name),
      cwd = ctx.cwd,
      search_dirs = cwd_relative(ctx.dirs, ctx.cwd),
      default_text = initial_query or "",
      attach_mappings = attach_show_path_mapping,
      -- Telescope passes its resolved options here before starting a job.
      -- Construct the default maker lazily, after it has also determined
      -- whether custom rg arguments omit coordinates or invert matches.
      additional_args = function(opts)
        local args = additional
        if type(args) == "function" then args = args(opts) end
        args = args or {}
        opts.entry_maker =
          M._telescope_entry_maker(ctx, require("telescope.make_entry").gen_from_vimgrep, opts)
        return args
      end,
    })
    return
  end

  -- Plain-vim fallback: :vimgrep across the dirs. Slow on big trees.
  local pattern = initial_query
  if not pattern or pattern == "" then
    pattern = vim.fn.input("Grep pattern: ")
    if pattern == "" then return end
  end
  local files = {}
  for _, d in ipairs(ctx.dirs or {}) do
    local stat = vim.uv.fs_stat(d)
    table.insert(files, vim.fn.fnameescape(d) .. (stat and stat.type == "file" and "" or "/**/*"))
  end
  if not ctx.dirs then files = { vim.fn.fnameescape(ctx.cwd) .. "/**/*" } end
  -- nvim_cmd with bar = false: a "|" or '"' in the pattern is part of it,
  -- not a command separator or comment. vimgrep THROWS E480 when nothing
  -- matches; report that as a message instead of an error trace.
  local ok, err = pcall(vim.api.nvim_cmd, {
    cmd = "vimgrep",
    args = { ("/%s/gj"):format(M._vimgrep_pattern(pattern)), unpack(files) },
    magic = { file = true, bar = false },
  }, {})
  if not ok then
    if tostring(err):find("E480", 1, true) then
      vim.notify(("Scoper: no matches in scope %q"):format(ctx.name))
    else
      vim.notify(tostring(err), vim.log.levels.ERROR)
    end
    return
  end
  -- vimgrep can't take excludes; apply the scope's excludes to the result
  -- so this backend agrees with the fzf-lua / telescope ones.
  if ctx.restricted or #ctx.excludes > 0 then
    local in_scope = ctx.in_scope or State.matcher()
    local kept = vim.tbl_filter(function(item)
      return item.bufnr == 0 or in_scope(vim.api.nvim_buf_get_name(item.bufnr))
    end, vim.fn.getqflist())
    vim.fn.setqflist({}, "r", { items = kept })
    if #kept == 0 then
      vim.notify(("Scoper: no matches in scope %q (all excluded)"):format(ctx.name))
      return
    end
  end
  vim.cmd("copen")
end

-- ---------------------------------------------------------------------------
-- :ScoperReplace delegates only unrestricted searches to grug-far. Its
-- pinned backend resolves paths and spawns deferred jobs against whichever
-- window is current at that later time; it has no durable per-instance cwd
-- API. A result-window :lcd therefore cannot enforce an active scope.
-- ---------------------------------------------------------------------------
function M.replace(prefills)
  local ctx = get_context()
  if not ctx then return end

  if (ctx.dirs and #ctx.dirs > 0) or #ctx.excludes > 0 then
    vim.notify(
      "Scoper: scoped replace is unavailable: grug-far cannot preserve the project directory "
        .. "for deferred searches and writes after window changes. Use :ScoperGrep to inspect "
        .. "the scope, or use :GrugFar explicitly for unscoped replacement.",
      vim.log.levels.WARN
    )
    return
  end

  if not has("grug-far") then
    vim.notify("Scoper: grug-far.nvim is not installed", vim.log.levels.ERROR)
    return
  end

  require("grug-far").open({ prefills = prefills or {} })
end

-- ---------------------------------------------------------------------------
-- :ScoperTogglePicker
-- ---------------------------------------------------------------------------
-- Flips `vim.g.scoper_picker` between "fzf" (default — uses fzf-lua) and
-- "telescope". The value is only read at the moment a picker is invoked,
-- so flipping it takes effect on the very next :ScoperFind / :ScoperGrep
-- with no restart needed.
--
-- We treat any unset / nil value as "fzf" so the default behaviour is
-- preserved. Setting it to "telescope" gives you the <M-p>-shows-path
-- feature documented above; nothing else changes.
function M.toggle_picker()
  local current = vim.g.scoper_picker or "fzf"
  local next_picker = (current == "telescope") and "fzf" or "telescope"
  vim.g.scoper_picker = next_picker
  vim.notify(("Scoper picker → %s"):format(next_picker), vim.log.levels.INFO)
end

return M
