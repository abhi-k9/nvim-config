-- Declared tool intent. Prerequisite filtering must never erase requirements
-- used by health/offline checks: unavailable and deliberately disabled differ.
local M = {}

M.server_packages = {
  bashls = "bash-language-server",
  lua_ls = "lua-language-server",
  clangd = "clangd",
  pyright = "pyright",
  ruff = "ruff",
  ts_ls = "typescript-language-server",
  rust_analyzer = "rust-analyzer",
  jsonls = "json-lsp",
  yamlls = "yaml-language-server",
  html = "html-lsp",
  cssls = "css-lsp",
  marksman = "marksman",
  taplo = "taplo",
}

-- Read local metadata only when its owner is already loaded. Resolving intent
-- must not activate the deferred LSP bridge or refresh/install a registry.
function M.mapping()
  local mapping = vim.deepcopy(M.server_packages)
  local registry = package.loaded["mason-registry"]
  if type(registry) == "table" and type(registry.get_all_package_specs) == "function" then
    local ok, specs = pcall(registry.get_all_package_specs)
    if ok and type(specs) == "table" then
      for _, spec in ipairs(specs) do
        local server = type(spec) == "table"
          and type(spec.neovim) == "table"
          and spec.neovim.lspconfig
        if
          type(server) == "string"
          and server ~= ""
          and type(spec.name) == "string"
          and spec.name ~= ""
        then
          mapping[server] = spec.name
        end
      end
    end
  end
  local bridge = package.loaded["mason-lspconfig"]
  if type(bridge) == "table" and type(bridge.get_mappings) == "function" then
    local ok, mappings = pcall(bridge.get_mappings)
    local aliases = ok and type(mappings) == "table" and mappings.lspconfig_to_package
    if type(aliases) == "table" then
      for server, name in pairs(aliases) do
        if type(server) == "string" and server ~= "" and type(name) == "string" and name ~= "" then
          mapping[server] = name
        end
      end
    end
  end
  return mapping
end

function M.option(name, default)
  local value = require("config.settings").get("tools." .. name, default)
  assert(type(value) == "table" and vim.islist(value), "tools." .. name .. " must be a list")
  return vim.deepcopy(value)
end

function M.identity(value)
  assert(type(value) == "string" and value ~= "", "tool name must be a nonempty string")
  local name, version = value:match("^([^@]+)@(.+)$")
  assert(not value:find("@", 1, true) or name, "version pins must use name@version")
  return name or value, version
end

function M.enabled(entry)
  local condition
  if type(entry) == "table" then condition = entry.condition end
  if condition == nil then return true end
  if type(condition) == "boolean" then return condition end
  assert(type(condition) == "function", "tool condition must be a function or boolean")
  return condition() == true
end

function M.package(entry)
  local name, version = M.identity(type(entry) == "table" and entry[1] or entry)
  if type(entry) == "table" and entry.version ~= nil then
    assert(
      version == nil or version == entry.version,
      "conflicting inline and explicit tool versions for " .. name
    )
    version = entry.version
  end
  assert(
    version == nil or type(version) == "string" and version ~= "",
    "tool version must be a nonempty string"
  )
  return name, version
end

-- Both lists are resolved plugin options BEFORE runtime prerequisite gating.
function M.packages(servers, packages, mapping)
  mapping = mapping or M.mapping()
  local wanted = {}
  local function add(name, version, enabled, source)
    assert(
      version == nil or type(version) == "string" and version ~= "",
      "tool version must be a nonempty string"
    )
    local item = wanted[name]
    if item and item.enabled and enabled and item.version ~= version then
      error("conflicting version requirements for Mason package " .. name)
    end
    if not item or enabled then
      wanted[name] = { name = name, version = version, enabled = enabled, source = source }
    end
  end
  for _, server in ipairs(servers or {}) do
    local name, version = M.identity(server)
    local override = require("config.settings").get("lsp.servers." .. name)
    add(mapping[name] or name, version, override ~= false, "server:" .. name)
  end
  for _, entry in ipairs(packages or {}) do
    local name, version = M.package(entry)
    add(name, version, M.enabled(entry), "package")
  end
  return wanted
end

function M.resolved()
  local ok, config = pcall(require, "lazy.core.config")
  if not ok then return { servers = {}, packages = {}, parsers = {} } end
  local plugin = require("lazy.core.plugin")
  local function opts(name)
    local p = (config.plugins or {})[name]
    return p and plugin.values(p, "opts", false) or {}
  end
  return {
    servers = opts("mason-lspconfig.nvim").ensure_installed or {},
    packages = opts("mason-tool-installer.nvim").ensure_installed or {},
    parsers = opts("nvim-treesitter").parsers or {},
  }
end

-- Validate BOTH owners' resolved options before either may schedule installs.
-- The current callback's options win, including native Lazy opts functions.
function M.validate_installation(kind, opts)
  assert(kind == "servers" or kind == "packages", "invalid tool requirement kind")
  local declared = M.resolved()
  declared[kind] = opts.ensure_installed or {}
  return M.packages(declared.servers, declared.packages)
end

function M.parser_provisioning(parsers)
  return vim.g.treesitter_auto_install ~= false and #parsers > 0
end

function M.missing_packages(wanted, registry)
  local missing = {}
  for name, item in pairs(wanted) do
    if item.enabled then
      if not registry.is_installed(name) then
        missing[#missing + 1] = "missing mason " .. name
      elseif item.version then
        -- A present binary is not a complete pinned seed if startup would
        -- immediately need to download the requested version instead.
        local package = registry.get_package(name)
        local actual = package:get_installed_version()
        if actual ~= item.version then
          missing[#missing + 1] = ("missing mason %s@%s (installed: %s)"):format(
            name,
            item.version,
            actual or "version unknown"
          )
        end
      end
    end
  end
  table.sort(missing)
  return missing
end

function M.server_selected(name)
  if require("config.settings").get("lsp.servers." .. name) == false then return false end
  local entries = require("config.settings").get("tools.servers")
  if entries == nil then
    local ok, config = pcall(require, "lazy.core.config")
    local p = ok and config.plugins["mason-lspconfig.nvim"]
    entries = p and require("lazy.core.plugin").values(p, "opts", false).ensure_installed
      or { "pyright", "ruff" }
  end
  for _, entry in ipairs(entries) do
    if M.identity(entry) == name then return true end
  end
  return false
end

function M.python_policy()
  local pyright, ruff = M.server_selected("pyright"), M.server_selected("ruff")
  local opts = require("config.settings").get("lsp.python", {})
  assert(type(opts) == "table", "lsp.python must be a table")
  local policy = {
    ruff_hover = opts.ruff_hover == nil and not pyright or opts.ruff_hover == true,
    organize_imports = opts.organize_imports
      or (ruff and "ruff" or pyright and "pyright" or "none"),
    type_checking = opts.type_checking or "basic",
  }
  assert(
    vim.tbl_contains({ "ruff", "pyright", "none" }, policy.organize_imports),
    "invalid lsp.python.organize_imports"
  )
  assert(
    vim.tbl_contains({ "basic", "strict", "off" }, policy.type_checking),
    "invalid lsp.python.type_checking"
  )
  return policy
end

return M
