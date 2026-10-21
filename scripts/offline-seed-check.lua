-- Preflight for scripts/offline-seed.py: lists what the config would
-- still download on its next start (missing plugins, Mason packages,
-- treesitter parsers), so a seed isn't built from an incomplete install.
--
--   nvim --headless "+luafile scripts/offline-seed-check.lua"
--
-- Writes {"version":1,"missing":[...]} (one "missing <kind> <name>" string
-- per gap) to $OFFLINE_SEED_CHECK_OUT, or stdout, and exits 0. On any error
-- it writes {"version":1,"error":"..."} and exits 1: a check that couldn't
-- look must never read as "complete".

local function check()
  local out = {}
  local function missing(kind, name)
    out[#out + 1] = ("missing %s %s"):format(kind, name)
  end

  local Config = require("lazy.core.config")
  local Plugin = require("lazy.core.plugin")

  for name, p in pairs(Config.plugins) do
    if not p._.installed then missing("plugin", name) end
  end

  local function opts_of(name)
    local p = Config.plugins[name]
    return p and Plugin.values(p, "opts", false) or {}
  end

  local wanted = {}
  for _, pkg in ipairs(opts_of("mason-tool-installer.nvim").ensure_installed or {}) do
    wanted[type(pkg) == "table" and pkg[1] or pkg] = true
  end
  local servers = opts_of("mason-lspconfig.nvim").ensure_installed or {}
  if #servers > 0 then
    require("lazy").load({ plugins = { "mason-lspconfig.nvim" } })
    local map = require("mason-lspconfig").get_mappings().lspconfig_to_package
    for _, server in ipairs(servers) do
      wanted[map[server] or server] = true
    end
  end
  if next(wanted) then
    local registry = require("mason-registry")
    for pkg in pairs(wanted) do
      if not registry.is_installed(pkg) then missing("mason", pkg) end
    end
  end

  local parsers = opts_of("nvim-treesitter").parsers or {}
  if #parsers > 0 then
    local installed = {}
    for _, lang in ipairs(require("nvim-treesitter.config").get_installed("parsers")) do
      installed[lang] = true
    end
    for _, lang in ipairs(parsers) do
      if not installed[lang] then missing("parser", lang) end
    end
  end

  table.sort(out)
  return out
end

local ok, res = pcall(check)
local report = ok and { version = 1, missing = res } or { version = 1, error = tostring(res) }
local text = vim.json.encode(report)
local file = vim.env.OFFLINE_SEED_CHECK_OUT
local wrote = true
if file and file ~= "" then
  wrote = pcall(vim.fn.writefile, { text }, file)
else
  io.stdout:write(text .. "\n")
end
vim.cmd(ok and wrote and "qa!" or "cquit 1")
