-- Optional tooling policy. Missing prerequisites skip automatic work quietly;
-- health checks retain the reasons. Explicit installer commands still work.
local M = {}
local skipped, msvc, python_cache = {}, nil, {}

local function have(bin)
  return vim.fn.executable(bin) == 1
end

local function any(bins)
  for _, bin in ipairs(bins) do
    if have(bin) then return true end
  end
  return false
end

function M.record(name, missing)
  skipped[name] = #missing > 0 and table.concat(missing, ", ") or nil
  return #missing == 0
end

function M.skipped()
  return vim.deepcopy(skipped)
end

-- tree-sitter discovers MSVC without a Developer Prompt. Cache only this
-- expensive probe; installing Build Tools takes a restart to be discovered.
function M.msvc_install_path()
  if vim.fn.has("win32") == 0 then return nil end
  if msvc ~= nil then return msvc or nil end
  msvc = false
  local vswhere = (vim.env["ProgramFiles(x86)"] or "C:\\Program Files (x86)")
    .. "\\Microsoft Visual Studio\\Installer\\vswhere.exe"
  if not have(vswhere) then return nil end
  local ok, result = pcall(function()
    return vim
      .system({
        vswhere,
        "-latest",
        "-products",
        "*",
        "-requires",
        "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
        "-property",
        "installationPath",
      }, { text = true })
      :wait(1500)
  end)
  if ok and result.code == 0 then
    local path = (result.stdout or ""):match("([^\r\n]+)")
    if path and path:match("%S") then msvc = path:gsub("%s+$", "") end
  end
  return msvc or nil
end

function M.compiler()
  return any({ "cc", "clang", "gcc", "cl" }) or M.msvc_install_path() ~= nil
end

function M.parsers_ready()
  local missing = {}
  for _, bin in ipairs({ "tree-sitter", "curl", "tar" }) do
    if not have(bin) then missing[#missing + 1] = bin end
  end
  if not M.compiler() then missing[#missing + 1] = "C compiler" end
  return M.record("Treesitter automatic parser installation", missing)
end

function M.native_sorter_build()
  if
    have("make")
    and (vim.fn.has("win32") == 1 and have("gcc") or vim.fn.has("win32") == 0 and have("cc"))
  then
    M.record("Telescope native sorter build", {})
    return "make"
  end
  if have("cmake") and M.compiler() then
    M.record("Telescope native sorter build", {})
    return "cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release --target install"
  end
  M.record("Telescope native sorter build", { "make + its C compiler, or cmake + a C toolchain" })
  return false
end

function M.blink_implementation()
  local missing = {}
  local os = vim.uv.os_uname().sysname
  local checksum = vim.fn.has("win32") == 1 and "certutil"
    or os == "Darwin" and "shasum"
    or os == "OpenBSD" and "sha256"
    or "sha256sum"
  for _, bin in ipairs({ "curl", checksum }) do
    if not have(bin) then missing[#missing + 1] = bin end
  end
  return M.record("Blink native fuzzy matcher (using Lua fallback)", missing)
      and "prefer_rust_with_warning"
    or "lua"
end

local npm = {
  ["bash-language-server"] = true,
  pyright = true,
  ["typescript-language-server"] = true,
  ["json-lsp"] = true,
  ["yaml-language-server"] = true,
  ["html-lsp"] = true,
  ["css-lsp"] = true,
  prettierd = true,
}
local servers = {
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

local function python()
  for _, bin in ipairs({ "python3", "python" }) do
    -- Windows Store execution aliases look executable but are not Python.
    local path = vim.fn.exepath(bin)
    if have(bin) and not path:find("[/\\]WindowsApps[/\\]") then
      local key = path .. "\n" .. (vim.env.PATH or "")
      if python_cache[key] == nil then
        local ok, result = pcall(function()
          return vim
            .system(
              { bin, "-c", "import sys, venv, ensurepip; assert sys.version_info.major == 3" },
              { text = true }
            )
            :wait(1500)
        end)
        python_cache[key] = ok and result.code == 0
      end
      if python_cache[key] then return true end
    end
  end
  return false
end

function M.runtime_missing(package)
  local missing = {}
  if (npm[package] or package == "bash-debug-adapter") and not have("node") then
    missing[#missing + 1] = "node"
  end
  if package == "rust-analyzer" then
    for _, bin in ipairs({ "cargo", "rustc" }) do
      if not have(bin) then missing[#missing + 1] = bin end
    end
  end
  return missing
end

function M.mason_download_ready()
  local windows = vim.fn.has("win32") == 1
  return any({ "curl", "wget" }) or windows and any({ "pwsh", "powershell" })
end

function M.install_supported(package)
  local missing = M.runtime_missing(package)
  local windows = vim.fn.has("win32") == 1
  if not M.mason_download_ready() then
    missing[#missing + 1] = "curl/wget (or PowerShell on Windows)"
  end
  if npm[package] and not have("npm") then missing[#missing + 1] = "npm" end
  if (package == "clang-format" or package == "debugpy") and not python() then
    missing[#missing + 1] = "Python 3 with venv/ensurepip"
  end
  -- The configured Mason packages use these prebuilt archive formats.
  -- npm and pip extract their own payloads; standalone shfmt/marksman need no extractor.
  local archives = {
    ["lua-language-server"] = windows and "zip" or "tar",
    clangd = "zip",
    stylua = "zip",
    codelldb = "zip",
    cpptools = "zip",
    ["bash-debug-adapter"] = "zip",
    ruff = "tar",
    shellcheck = "tar",
    ["rust-analyzer"] = windows and "zip" or "gzip",
    taplo = windows and "zip" or "gzip",
  }
  local archive = archives[package]
  if
    archive == "zip"
    and not (windows and any({ "pwsh", "powershell" }) or not windows and have("unzip"))
  then
    missing[#missing + 1] = windows and "PowerShell (ZIP extraction)" or "unzip"
  elseif archive == "tar" and not any({ "tar", "gtar" }) then
    missing[#missing + 1] = "tar"
  elseif archive == "gzip" and not have("gzip") then
    missing[#missing + 1] = "gzip"
  end
  return M.record("Mason install: " .. package, missing)
end

function M.configure_servers(opts)
  opts = vim.deepcopy(opts)
  local installs = {}
  for _, server in ipairs(opts.ensure_installed or {}) do
    if M.install_supported(servers[server] or server) then installs[#installs + 1] = server end
  end
  opts.ensure_installed = installs
  -- This gates installed servers too: a copied Mason wrapper may still exist
  -- after its Node/Rust runtime disappears. Preserve user exclusions.
  if opts.automatic_enable == false then return opts end
  local automatic = opts.automatic_enable
  local allowed = type(automatic) == "table" and vim.islist(automatic) and automatic or nil
  if not allowed then
    if type(automatic) ~= "table" then automatic = {} end
    automatic.exclude = automatic.exclude or {}
    opts.automatic_enable = automatic
  end
  for server, package in pairs(servers) do
    local missing = M.runtime_missing(package)
    if not M.record("LSP runtime: " .. server, missing) then
      if allowed then
        for i = #allowed, 1, -1 do
          if allowed[i] == server then table.remove(allowed, i) end
        end
      elseif not vim.tbl_contains(automatic.exclude, server) then
        automatic.exclude[#automatic.exclude + 1] = server
      end
    end
  end
  return opts
end

return M
