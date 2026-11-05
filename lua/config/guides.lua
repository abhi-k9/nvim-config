-- Read the maintained guides directly; never execute text from a guide.
local M = {}
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
local topics = {
  { "quickstart", "Everyday workflows", "quick-start.md" },
  {
    "navigation",
    "Files, buffers and search",
    "quick-start.md",
    "## Find files, text and symbols",
  },
  {
    "buffers",
    "Closing buffers and managing layouts",
    "quick-start.md",
    "## Keep a useful layout and resume work",
  },
  {
    "workspace",
    "Directories, scopes and sessions",
    "search-session-configuration.md",
    "## Changing directories",
  },
  { "debugging", "Launch configurations and debugging", "debug-terminal-configuration.md" },
  { "help", "Help inside each feature", "context-help.md" },
  { "tools", "Missing tools and limited systems", "limited-environments.md" },
  { "install", "Install, update and roll back", "workflows/install-update-uninstall.md" },
  { "migration", "Visual Studio migration", "visual-studio-migration.md" },
  { "customization", "Local settings and project policy", "customization.md" },
}

function M.complete(prefix)
  local result = {}
  for _, topic in ipairs(topics) do
    if topic[1]:sub(1, #prefix) == prefix then result[#result + 1] = topic[1] end
  end
  return result
end

local function open(topic)
  local path = vim.fs.joinpath(root, "docs", topic[3])
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    vim.notify(
      "Guide unavailable: "
        .. path
        .. ". Restore the repository's docs folder; :help remains available.",
      vim.log.levels.WARN
    )
    return
  end
  local line = 1
  if topic[4] then
    for index, text in ipairs(lines) do
      if text:sub(1, #topic[4]) == topic[4] then
        line = index
        break
      end
    end
  end
  return require("config.readonly").open(lines, {
    title = topic[2],
    filetype = "markdown",
    line = line,
    footer = " q / Esc: close | b: topics | /: search ",
    actions = {
      b = {
        desc = "Choose another guide",
        run = function()
          M.show()
        end,
      },
    },
  })
end

function M.show(name)
  if name and name ~= "" then
    for _, topic in ipairs(topics) do
      if topic[1] == name then return open(topic) end
    end
    vim.notify(
      "Unknown guide: "
        .. name
        .. ". Use :ConfigHelp with Tab completion, or :ConfigHelp for the menu.",
      vim.log.levels.WARN
    )
    return
  end
  local ok, err = pcall(vim.ui.select, topics, {
    prompt = "Configuration guides",
    format_item = function(topic)
      return topic[2]
    end,
  }, function(topic)
    if topic then open(topic) end
  end)
  if not ok then
    vim.notify(
      "Guide selector unavailable: "
        .. tostring(err)
        .. ". Use :ConfigHelp with Tab completion to choose a topic directly.",
      vim.log.levels.WARN
    )
    return open(topics[1])
  end
end

return M
