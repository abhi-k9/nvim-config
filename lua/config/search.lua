-- Shared policy for config-owned search commands. Backends retain their own
-- advanced options; these helpers only resolve roots and literal directory names.
local M = {}

local function settings()
  return require("config.settings")
end

function M.root(kind)
  return settings().resolve(
    settings().get("search." .. kind .. "_root", settings().get("search.root", "cwd"))
  )
end

function M.visibility(backend, kind)
  local function policy(name, default)
    return settings().get(
      "search." .. backend .. "." .. name,
      settings().get("search." .. name, default)
    )
  end
  local excluded = policy("exclude_dirs")
  if excluded == nil then
    excluded = backend == "telescope" and { ".git", "node_modules" }
      or backend == "explorer" and { ".DS_Store", "thumbs.db", "node_modules" }
      or { ".git", ".jj" }
  end
  assert(type(excluded) == "table", "search.exclude_dirs must be a list of literal directory names")
  local names = {}
  for _, name in ipairs(excluded) do
    if type(name) == "string" and name ~= "" and not name:find("[/\\\r\n]") then
      names[#names + 1] = name
    end
  end
  return {
    hidden = policy("hidden", kind == "find" or backend == "explorer"),
    respect_gitignore = policy("respect_gitignore", backend ~= "explorer"),
    follow_links = policy("follow_links", false),
    exclude_dirs = names,
  }
end

function M.component_patterns(names)
  local out = {}
  for _, name in ipairs(names) do
    local escaped = name:gsub("([^%w])", "%%%1")
    out[#out + 1] = "^" .. escaped .. "[/\\]"
    out[#out + 1] = "[/\\]" .. escaped .. "[/\\]"
  end
  return out
end

function M.find_command(policy)
  if vim.fn.executable("rg") == 1 then
    local command = { "rg", "--files", "--color=never" }
    if policy.hidden then command[#command + 1] = "--hidden" end
    if not policy.respect_gitignore then command[#command + 1] = "--no-ignore" end
    if policy.follow_links then command[#command + 1] = "--follow" end
    -- Exact directory-component filtering also runs on parsed entries. At
    -- source use escaped glob metacharacters for names such as [vendor].
    for _, name in ipairs(policy.exclude_dirs) do
      local literal = name:gsub("([*?%[%]{}\\])", "\\%1")
      command[#command + 1] = "--glob=!**/" .. literal .. "/**"
    end
    return command
  end
  for _, executable in ipairs({ "fd", "fdfind" }) do
    if vim.fn.executable(executable) == 1 then
      local command = { executable, "--type", "f", "--color", "never" }
      if policy.hidden then command[#command + 1] = "--hidden" end
      if not policy.respect_gitignore then command[#command + 1] = "--no-ignore" end
      if policy.follow_links then command[#command + 1] = "--follow" end
      for _, name in ipairs(policy.exclude_dirs) do
        command[#command + 1] = "--exclude"
        command[#command + 1] = "**/" .. name:gsub("([*?%[%]{}\\])", "\\%1") .. "/**"
      end
      return command
    end
  end
end

function M.telescope_options(kind)
  local policy = M.visibility("telescope", kind)
  return {
    cwd = M.root(kind),
    hidden = policy.hidden,
    no_ignore = not policy.respect_gitignore,
    follow = policy.follow_links,
    file_ignore_patterns = M.component_patterns(policy.exclude_dirs),
    find_command = kind == "find" and M.find_command(policy) or nil,
    additional_args = kind == "grep" and function()
      local args = {}
      if policy.hidden then args[#args + 1] = "--hidden" end
      if not policy.respect_gitignore then args[#args + 1] = "--no-ignore" end
      if policy.follow_links then args[#args + 1] = "--follow" end
      for _, name in ipairs(policy.exclude_dirs) do
        args[#args + 1] = "--glob=!**/" .. name:gsub("([*?%[%]{}\\])", "\\%1") .. "/**"
      end
      return args
    end or nil,
  }
end

function M.fzf_options(kind)
  local policy = M.visibility("fzf", kind)
  local opts = {
    cwd = M.root(kind),
    hidden = policy.hidden,
    no_ignore = not policy.respect_gitignore,
    follow = policy.follow_links,
    file_ignore_patterns = M.component_patterns(policy.exclude_dirs),
  }
  if kind == "find" then
    local command = M.find_command(policy)
    if command then
      local escape = require("fzf-lua.libuv").shellescape
      opts.cmd = table.concat(vim.tbl_map(escape, command), " ")
    end
  else
    local escape = require("fzf-lua.libuv").shellescape
    local args =
      { "--column --line-number --no-heading --color=always --smart-case --max-columns=4096" }
    if policy.hidden then args[#args + 1] = "--hidden" end
    if not policy.respect_gitignore then args[#args + 1] = "--no-ignore" end
    if policy.follow_links then args[#args + 1] = "--follow" end
    for _, name in ipairs(policy.exclude_dirs) do
      args[#args + 1] = escape("--glob=!**/" .. name:gsub("([*?%[%]{}\\])", "\\%1") .. "/**")
    end
    -- Preserve the backend's required end marker: dash-leading queries remain patterns.
    args[#args + 1] = "-e"
    opts.rg_opts = table.concat(args, " ")
  end
  return opts
end

-- grug-far resolves deferred commands against whichever window is current;
-- even absolute prefills are made relative again by its pinned path parser.
-- Refuse a non-current root rather than imply durable cwd confinement.
function M.replace_options(prefills)
  local root = M.root("replace")
  local cwd = vim.fs.normalize(vim.fn.getcwd(), { expand_env = false })
  local selected = vim.fs.normalize(root, { expand_env = false })
  if vim.fn.has("win32") == 1 then
    cwd, selected = cwd:lower(), selected:lower()
  end
  if cwd ~= selected then
    vim.notify(
      "Search/replace cannot preserve a different root with this grug-far version. "
        .. "Change the working directory explicitly before opening it.",
      vim.log.levels.WARN
    )
    return nil
  end
  return { prefills = vim.deepcopy(prefills or {}) }
end

return M
