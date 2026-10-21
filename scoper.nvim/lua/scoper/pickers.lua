-- lua/scoper/pickers.lua
--
-- Search-within-scope commands. Three operations, three backends auto-
-- detected at call time so the user can drop either dependency without
-- crashing the plugin.
--
--   :ScoperFind     – fuzzy-find files within active scope
--   :ScoperGrep     – live grep within active scope
--   :ScoperReplace  – open grug-far rooted at the scope's dirs
--
-- Backend preference (in order):
--   1. fzf-lua    – fastest, accepts `cwd` + multiple search paths
--   2. telescope  – pure-lua, accepts `search_dirs` and `file_ignore_patterns`
--   3. plain vim  – falls back to :vimgrep / :find with cwd hacks
--
-- For the deny-list: telescope wants Lua patterns, fzf-lua and grug-far
-- run ripgrep. We pass excludes to ripgrep as globs (also for finding
-- files, so all three commands read globs the same way) and convert
-- simple globs to Lua patterns for telescope, both anchored the way
-- is_in_scope reads them (M._anchor_excludes).
--
-- Scoping off, or an empty include list, means everything is in scope
-- (as in is_in_scope): the commands then search the whole cwd, without
-- the scope's excludes.

local State = require("scoper.state")
local Path = require("scoper.path")
local Util = require("scoper.util")

local M = {}

-- ---------------------------------------------------------------------------
-- Helper: get scope context as a single struct, or nil with a notify when
-- the active scope has includes but none of them is an existing directory
-- (so the user gets a clear error, not silent "search everything"
-- behavior). `dirs` is nil when the whole cwd is in scope.
-- ---------------------------------------------------------------------------
local function get_context()
  local scope = State.active_scope()
  if not scope then
    vim.notify("Scoper: no active scope", vim.log.levels.WARN)
    return nil
  end
  if not State.is_enabled() or #scope.include == 0 then return { name = "all", excludes = {} } end
  local dirs = State.active_dirs()
  if #dirs == 0 then
    vim.notify(
      ("Scoper: scope %q has no existing directories. Use :ScoperAdd first."):format(
        State.active_name()
      ),
      vim.log.levels.WARN
    )
    return nil
  end
  return {
    name = State.active_name(),
    dirs = dirs,
    excludes = scope.exclude,
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

-- ---------------------------------------------------------------------------
-- Convert simple glob exclude → Lua patterns for telescope's
-- file_ignore_patterns. We handle the common cases (*, **, ?, [...]);
-- patterns using syntax this small translator CANNOT express — `{a,b}`
-- alternation or `[!...]` negation — return nil, and we notify (once
-- per pattern per session) so the divergence is visible: on the
-- fzf-lua backend those globs pass straight through to ripgrep and
-- work; a silently-mistranslated Lua pattern on the telescope backend
-- would just match nothing.
--
-- Telescope matches the patterns against the paths it lists: relative to
-- the cwd for search dirs inside it (they are passed that way; "./" in
-- front when the cwd itself is searched), absolute for the others, and
-- with "\" on Windows. As in ripgrep, a pattern without a slash (or with a
-- leading "**/") matches whole components at any depth (`build` must not
-- hide `builder/`, `**/x/**` not `my_x/`), and any other pattern is
-- anchored at the cwd. Given a `root` (a search dir outside the cwd) the
-- pattern applies below that dir instead; without one it never matches an
-- absolute path. Separators match "/" and "\", and letters match
-- either case on Windows, where is_in_scope ignores case too. Lua patterns
-- have no alternation, so a LIST of patterns comes back (any match ignores
-- the entry).
-- ---------------------------------------------------------------------------
local warned_globs = {}
local SEP, NOTSEP = "[/\\]", "[^/\\]"

-- Lua pattern matching the path `s` literally.
local function literal(s, fold)
  local pat = s:gsub("[^%w/]", "%%%0"):gsub("/", SEP)
  if not fold then return pat end
  return (pat:gsub("%a", function(c)
    return "[" .. c:lower() .. c:upper() .. "]"
  end))
end

function M._glob_to_lua_pats(glob, root)
  if glob:find("{", 1, true) or glob:find("[!", 1, true) then
    if not warned_globs[glob] then
      warned_globs[glob] = true
      vim.notify(
        (
          "Scoper: exclude %q uses glob syntax ({a,b} / [!…]) the telescope "
          .. "backend can't translate — it is ignored there. The fzf-lua "
          .. "backend handles it; :ScoperTogglePicker to switch."
        ):format(glob),
        vim.log.levels.WARN
      )
    end
    return nil
  end

  -- "/**" at the end means "below this directory".
  local body, below = glob:gsub("/+$", ""), false
  local anywhere = not body:find("/", 1, true)
  while body:sub(1, 3) == "**/" do
    body, anywhere = body:sub(4), true
  end
  body = body:gsub("^/+", "")
  while body:sub(-3) == "/**" do
    body, below = body:sub(1, -4), true
  end

  local fold = Path.is_windows
  local heads
  if root then
    local head = "^" .. literal(root, fold) .. SEP
    heads = anywhere and { head, head .. ".-" .. SEP } or { head }
  else
    -- deeper only in a relative path: not after "/", "c:" or "//srv"
    heads = anywhere and { "^", "^[^/\\]" .. (fold and "[^:]-" or ".-") .. SEP }
      or { "^", "^%." .. SEP }
  end
  if body == "" or body == "**" then return heads end

  local variants = { "" }
  local function add(s)
    for i, v in ipairs(variants) do
      variants[i] = v .. s
    end
  end
  local i = 1
  while i <= #body do
    local c = body:sub(i, i)
    if body:sub(i, i + 2) == "**/" then
      -- zero or more whole directories: one variant each
      local more = {}
      for _, v in ipairs(variants) do
        table.insert(more, v)
        table.insert(more, v .. ".-" .. SEP)
      end
      variants = more
      i = i + 3
    elseif body:sub(i, i + 1) == "**" then
      add(".*")
      i = i + 2
    else
      local close = c == "[" and body:find("]", i + 2, true)
      if close then
        -- character class, copied with its punctuation escaped
        local class = body:sub(i + 1, close - 1):gsub("[^%w%-]", "%%%0")
        if fold then class = class:lower() .. class:upper() end
        add("[" .. class .. "]")
        i = close + 1
      else
        if c == "*" then
          add(NOTSEP .. "*")
        elseif c == "?" then
          add(NOTSEP)
        elseif c == "/" then
          add(SEP)
        elseif fold and c:match("%a") then
          add("[" .. c:lower() .. c:upper() .. "]")
        elseif c:match("%w") then
          add(c)
        else
          add("%" .. c)
        end
        i = i + 1
      end
    end
  end

  local pats = {}
  for _, v in ipairs(variants) do
    for _, head in ipairs(heads) do
      if below then
        table.insert(pats, head .. v .. SEP)
      else
        table.insert(pats, head .. v .. "$")
        table.insert(pats, head .. v .. SEP)
      end
    end
  end
  return pats
end

-- Telescope file_ignore_patterns for `excludes` when searching `dirs`.
local function telescope_ignores(excludes, dirs)
  local out = {}
  for _, a in ipairs(M._anchor_excludes(excludes, dirs, vim.uv.cwd())) do
    -- nil for untranslatable globs (warned); otherwise a list of patterns
    vim.list_extend(out, M._glob_to_lua_pats(a.glob, a.root) or {})
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Backend detection lives in scoper.util (has / prefer_fzf). Re-checked
-- per call so a backend installed mid-session is picked up.
-- ---------------------------------------------------------------------------
local has = Util.has

-- The search dirs relative to Neovim's cwd when inside it, the way fzf-lua
-- passes `search_paths`: the tools match excludes against the paths they
-- list, which then don't contain the folders above the cwd.
local function cwd_relative(dirs)
  if not dirs then return nil end
  local cwd = vim.uv.cwd()
  return vim.tbl_map(function(d)
    return Path.relative(d, cwd)
  end, dirs)
end

-- ---------------------------------------------------------------------------
-- Telescope: non-closing <M-p> mapping that shows the highlighted entry's
-- absolute path in the prompt title without dismissing the picker.
-- (fzf-lua's Lua actions all exit; telescope's mapping API doesn't, which
-- is why this only exists on the telescope backend.) Registered through
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
-- way fzf-lua appends `search_paths`: relative to Neovim's cwd and quoted.
-- `.git` is excluded explicitly because hidden files are listed.
function M._fzf_files_opts(ctx, escape)
  local opts = { prompt = ("Find [%s]> "):format(ctx.name) }
  local excludes = vim.list_extend({ ".git" }, ctx.excludes)
  local follow = follow_links() and " --follow" or ""
  if vim.fn.executable("rg") == 1 then
    local parts = { "rg --files --color=never --hidden" .. follow .. rg_case_flag() }
    for _, ex in ipairs(M._rg_globs(excludes, ctx.dirs)) do
      table.insert(parts, M._rg_exclude(ex, escape))
    end
    for _, d in ipairs(ctx.dirs or {}) do
      table.insert(parts, escape(Path.relative(d, vim.uv.cwd())))
    end
    opts.cmd = table.concat(parts, " ")
    return opts
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
  return opts
end

function M.find()
  local ctx = get_context()
  if not ctx then return end

  -- fzf-lua first (snappier on big trees). We search ALL of the scope's
  -- directories, not just the first.
  --
  -- The directories are search roots resolved against the real Neovim cwd;
  -- deliberately NO `cwd` option: fzf-lua runs the command from
  -- `opts.cwd`, so cwd = ctx.dirs[1] would make fd/rg look for
  -- `src/src` and `src/lib` inside `<root>/src`. Without it, dirs both
  -- inside and outside the project tree work (in-tree ones become
  -- relative, the others stay absolute).
  --
  -- To force the telescope backend instead, set
  -- `vim.g.scoper_picker = "telescope"`.
  if Util.prefer_fzf() then
    require("fzf-lua").files(M._fzf_files_opts(ctx, require("fzf-lua.libuv").shellescape))
    return
  end

  if has("telescope.builtin") then
    require("telescope.builtin").find_files({
      prompt_title = ("Find [%s]"):format(ctx.name),
      search_dirs = cwd_relative(ctx.dirs),
      file_ignore_patterns = telescope_ignores(vim.list_extend({ ".git" }, ctx.excludes), ctx.dirs),
      hidden = true,
      follow = follow_links(),
      attach_mappings = attach_show_path_mapping,
    })
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
  local found = vim.fn.findfile(name, M._find_path(ctx.dirs or { vim.uv.cwd() }), -1)
  local in_scope = #ctx.excludes > 0 and State.matcher() or nil
  for _, f in ipairs(found) do
    local full = vim.fn.fnamemodify(f, ":p")
    if not in_scope or in_scope(full) then return full, #found end
  end
  return nil, #found
end

-- ---------------------------------------------------------------------------
-- :ScoperGrep
-- ---------------------------------------------------------------------------

-- fzf-lua live_grep() options for `ctx`. fzf-lua appends the query after
-- rg_opts, so they must end in `-e` like its defaults do: a query starting
-- with "-" (`-Wall`) is then still a pattern, not a flag. search_paths
-- only, NO cwd — see M.find.
function M._fzf_grep_opts(ctx, query, escape)
  local parts = {
    "--column --line-number --no-heading --color=always --smart-case --max-columns=4096"
      .. rg_case_flag(),
  }
  for _, ex in ipairs(M._rg_globs(ctx.excludes, ctx.dirs)) do
    table.insert(parts, M._rg_exclude(ex, escape))
  end
  table.insert(parts, "-e")
  return {
    prompt = ("Grep [%s]> "):format(ctx.name),
    search_paths = ctx.dirs,
    query = query or "",
    rg_opts = table.concat(parts, " "),
  }
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
    require("telescope.builtin").live_grep({
      prompt_title = ("Grep [%s]"):format(ctx.name),
      search_dirs = cwd_relative(ctx.dirs),
      file_ignore_patterns = telescope_ignores(ctx.excludes, ctx.dirs),
      default_text = initial_query or "",
      attach_mappings = attach_show_path_mapping,
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
    table.insert(files, vim.fn.fnameescape(d) .. "/**/*")
  end
  if not ctx.dirs then files = { "**/*" } end
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
  if #ctx.excludes > 0 then
    local in_scope = State.matcher()
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
-- One entry for grug-far's `paths` field. grug-far splits that string on
-- spaces ITSELF (utils.splitPaths) and only recognises a backslash-escaped
-- space ("my\\ dir"); quotes — shell-style or double — are kept as literal
-- path bytes, so a quoted dir with a space matched nothing. Only spaces
-- are escaped, which leaves Windows "\\" separators untouched.
-- ---------------------------------------------------------------------------
function M._grug_path(p)
  return (p:gsub(" ", "\\ "))
end

-- grug-far prefills (paths, flags) for `ctx`, or nil and the reason. An
-- empty `paths` searches grug-far's cwd, which `cwd` (default: Neovim's)
-- stands for.
function M._grug_prefills(ctx, cwd)
  -- grug-far splits its flags field at whitespace and has no quoting, so
  -- an exclude with whitespace can't reach ripgrep as written. Rewriting
  -- it would change which files a project-wide replace touches; refuse.
  for _, ex in ipairs(ctx.excludes) do
    if ex:find("%s") then
      return nil,
        ("exclude %q contains whitespace, which grug-far can't pass to ripgrep. Rewrite it without (e.g. ? for one character) to use :ScoperReplace."):format(
          ex
        )
    end
  end
  local quoted = {}
  for _, d in ipairs(ctx.dirs or {}) do
    table.insert(quoted, M._grug_path(d))
  end
  -- ripgrep --glob exclude flags go into the "flags" prefill so the user
  -- can see and edit them inside the grug-far buffer. A dir with
  -- whitespace still shows up inside the globs anchored below it; there
  -- it is written as "?", which only matters for a sibling dir that
  -- differs from it in just that character.
  local flag_parts = {}
  if Path.is_windows then table.insert(flag_parts, "--glob-case-insensitive") end
  for _, ex in ipairs(M._rg_globs(ctx.excludes, ctx.dirs, cwd)) do
    table.insert(flag_parts, "--glob=!" .. (ex:gsub("%s", "?")))
  end
  return {
    paths = table.concat(quoted, " "),
    flags = table.concat(flag_parts, " "),
  }
end

-- ---------------------------------------------------------------------------
-- :ScoperReplace — grug-far rooted at scope. grug-far has the right model
-- for this already: pass `paths` and it uses ripgrep with those as search
-- roots, and `--glob=!...` for excludes.
-- ---------------------------------------------------------------------------
function M.replace(prefills)
  local ctx = get_context()
  if not ctx then return end

  if not has("grug-far") then
    vim.notify("Scoper: grug-far.nvim is not installed", vim.log.levels.ERROR)
    return
  end

  local scoped, err = M._grug_prefills(ctx)
  if not scoped then
    vim.notify("Scoper: " .. err, vim.log.levels.ERROR)
    return
  end
  require("grug-far").open({
    prefills = vim.tbl_extend("force", scoped, prefills or {}),
  })
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
