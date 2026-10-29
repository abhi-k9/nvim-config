-- lua/config/health.lua
-- =============================================================================
-- `:checkhealth config`
--
-- Neovim discovers this automatically: a module at lua/<name>/health.lua that
-- exposes check() is run by `:checkhealth <name>`, so this file lives at
-- lua/config/health.lua and answers to `:checkhealth config`.
--
-- WHY THIS EXISTS. This config leans on a lot of EXTERNAL programs — clangd,
-- clang-format, clang-tidy, ripgrep, fzf, node, the debug adapters, a C
-- compiler for tree-sitter parsers, and so on. When one is missing or the
-- wrong version, the failure is usually silent and far from its cause ("why is
-- completion empty in this C++ file?" is really "clangd isn't on PATH"). This
-- healthcheck surfaces those in one place.
--
-- SCOPE. It checks system/runtime prerequisites, state-directory access,
-- selected C/C++ tools and recorded optional-install skips. It does NOT
-- re-verify the language servers / formatters / debug adapters that Mason
-- installs into its own prefix — that is `:checkhealth mason`'s job, and
-- duplicating package inventory here would drift. Where a tool can come
-- from either PATH or Mason (clangd, stylua, …) presence on PATH is treated
-- as sufficient and Mason is pointed to otherwise.
-- =============================================================================

local M = {}

local h = vim.health

-- executable() is the honest "is it on PATH" test.
local function have(bin)
  return vim.fn.executable(bin) == 1
end

-- First non-empty line of `<bin> <arg>`, trimmed — or nil if the call fails.
-- Best-effort and defensive: a miss just means "present, version unknown",
-- so callers that parse it must treat nil as "can't tell", not as a failure.
local function version(bin, arg)
  if not have(bin) then return nil end
  local ok, out = pcall(vim.fn.systemlist, { bin, arg or "--version" })
  if not ok or vim.v.shell_error ~= 0 or type(out) ~= "table" then return nil end
  for _, line in ipairs(out) do
    if type(line) == "string" and line:match("%S") then return (line:gsub("%s+$", "")) end
  end
  return nil
end

-- Report a single required/recommended tool. `level` is "error" (required) or
-- "warn" (recommended); present tools always report ok with their version.
local function check(bin, label, level, why)
  if have(bin) then
    h.ok(("%s — %s"):format(label, version(bin) or "found (version unknown)"))
    return true
  end
  local msg = ("%s not found on PATH"):format(label)
  if level == "error" then
    h.error(msg, why)
  else
    h.warn(msg, why)
  end
  return false
end

-- Report the first of several interchangeable binaries that is present.
local function check_any(bins, label, level, why)
  for _, b in ipairs(bins) do
    if have(b) then
      h.ok(("%s — %s (%s)"):format(label, version(b) or "found", b))
      return true
    end
  end
  local msg = ("%s not found (looked for: %s)"):format(label, table.concat(bins, ", "))
  if level == "error" then
    h.error(msg, why)
  else
    h.warn(msg, why)
  end
  return false
end

-- Windows: tree-sitter-cli locates the MSVC Build Tools through vswhere, so
-- cl.exe doesn't have to be on PATH (no Developer Prompt needed). Returns
-- the installation path, or nil when there is no MSVC C++ toolset.
local function msvc_install_path()
  return require("config.tooling").msvc_install_path()
end

-- Python 3 for Mason's PyPI packages. On Windows, python3/python under
-- ...\WindowsApps\ may be the Microsoft Store alias stub: on PATH, but every
-- call fails, so a PATH test alone passes falsely.
local function check_python(why, explicit)
  local stub
  for _, b in ipairs(explicit and { explicit } or { "python3", "python" }) do
    local v = version(b)
    if v and v:match("Python 3") then
      h.ok(("Python 3 — %s (%s)"):format(v, b))
      return
    end
    local path = vim.fn.exepath(b)
    if path:find("[/\\]WindowsApps[/\\]") then stub = path end
  end
  if stub then
    h.warn("Python 3: only the Microsoft Store stub was found (" .. stub .. ")", why)
  else
    h.warn("Python 3 not found (looked for: python3, python)", why)
  end
end

-- Report whether a runtime state directory is usable: writable if it exists,
-- or creatable (nearest existing ancestor writable) if it doesn't yet. Neovim
-- makes the swap/undo dirs lazily, so "not there yet" is normal — "can't be
-- made" is the real problem. `path` may carry a trailing // (as 'directory'
-- does) and may be a comma list; callers pass a single entry.
local function check_state_dir(label, path, why)
  if not path or path == "" then
    h.warn(label .. " is not set", why)
    return
  end
  -- Normalize the trailing // filename-encoding marker without losing
  -- filesystem roots. Expand environment variables without interpreting
  -- filename wildcards or Vim's %/# placeholders.
  path = vim.fs.normalize(path)
  if vim.fn.isdirectory(path) == 1 then
    if vim.fn.filewritable(path) == 2 then
      h.ok(("%s — writable (%s)"):format(label, path))
    else
      h.error(("%s exists but is NOT writable (%s)"):format(label, path), why)
    end
    return
  end
  -- Walk upward only through missing paths. A regular file or dangling
  -- symlink in the way prevents mkdir even if its own parent is writable.
  local anc = path
  while anc ~= "" and vim.fn.isdirectory(anc) == 0 do
    if vim.uv.fs_lstat(anc) then
      h.error(("%s cannot be created — path is not a directory (%s)"):format(label, anc), why)
      return
    end
    local up = vim.fn.fnamemodify(anc, ":h")
    if up == anc then break end
    anc = up
  end
  if vim.fn.isdirectory(anc) == 1 and vim.fn.filewritable(anc) == 2 then
    h.ok(("%s — not created yet; will be made under a writable parent (%s)"):format(label, anc))
  else
    h.error(("%s cannot be created — no writable parent (%s)"):format(label, path), why)
  end
end

function M.check()
  -- Load Mason first: its setup prepends Mason's bin dir to PATH, so the
  -- PATH probes below also see the clangd / clang-format / stylua it
  -- installed (and on Windows the tar shim is in place).
  local mason_ok = pcall(require, "mason")
  local intent = require("config.tool_intent")
  local declared = intent.resolved()
  local intent_ok, requested = pcall(intent.packages, declared.servers, declared.packages)
  local intent_error
  if not intent_ok then
    intent_error = tostring(requested)
    requested = {}
  end
  local function selected(name)
    return requested[name] and requested[name].enabled
  end
  local parser_builds = intent.parser_provisioning(declared.parsers)
  for name, item in pairs(requested) do
    if item.enabled then require("config.tooling").install_supported(name) end
  end

  -- ── Neovim itself ─────────────────────────────────────────────────────────
  h.start("Neovim")
  local v = vim.version()
  local vstr = ("%d.%d.%d"):format(v.major, v.minor, v.patch)
  -- The floor comes from init.lua (vim.g.config_min_nvim); the literal is
  -- only a fallback for a health run outside the normal init
  -- (e.g. `nvim -u NONE +checkhealth`).
  local min = vim.g.config_min_nvim or "0.12.0"
  if vim.fn.has("nvim-" .. min) == 1 then
    h.ok(("Neovim %s (meets the %s minimum)"):format(vstr, min))
  else
    h.error(("Neovim %s is below the required %s"):format(vstr, min), {
      "Upgrade Neovim — init.lua refuses to load older versions.",
    })
  end
  -- 'exrc' runs .nvim.lua / .nvimrc / .exrc from the cwd and its parent
  -- directories — only after you approve each file with :trust
  -- (vim.secure). Surface the setting so it stays a conscious choice.
  if vim.o.exrc then
    h.info(
      "'exrc' is ON: .nvim.lua/.exrc files in the cwd and its parent directories "
        .. "run once you :trust them (revoke with :trust ++remove). A trusted file "
        .. "in a parent applies to every project below it. Disable in "
        .. "local.lua with options.exrc=false."
    )
  end

  -- ── Core system prerequisites Mason cannot provide ────────────────────────
  h.start("Core prerequisites (must be on PATH — Mason cannot supply these)")
  check("git", "git", "error", { "Required by lazy.nvim to clone/update plugins and by Mason." })
  if parser_builds then
    local msvc = msvc_install_path()
    local explicit_cc = require("config.settings").get("tools.executables.compiler", vim.env.CC)
    if explicit_cc then
      check(
        explicit_cc,
        "Configured C compiler",
        "error",
        { "Used through CC by tree-sitter, CMake and the Unix sorter Makefile." }
      )
    elseif msvc then
      h.ok("C compiler — MSVC Build Tools (" .. msvc .. ")")
    else
      check_any({ "cc", "clang", "gcc", "cl" }, "C compiler", "error", {
        "nvim-treesitter compiles parsers from source; without a compiler the",
        "parser build fails. Any of cc / clang / gcc will do; on Windows the",
        "MSVC Build Tools are found automatically (cl need not be on PATH).",
      })
    end
    -- nvim-treesitter's `main` branch builds EVERY parser with
    -- `tree-sitter build` — there are no prebuilt downloads. Without the CLI,
    -- unguarded installation of each entry in treesitter.lua's PARSERS fails with
    -- "ENOENT … 'tree-sitter'" and only Neovim's bundled parsers (c, lua,
    -- markdown, query, vim, vimdoc) highlight unless another parser is installed.
    -- Our readiness gate skips those automatic builds. The minimum matches
    -- nvim-treesitter's own health check.
    local ts_why = {
      "Required by nvim-treesitter (main) to build parsers; a C compiler alone",
      "is not enough. Install tree-sitter 0.26.1+ (see README: Installing the",
      "tree-sitter CLI): package manager (scoop/brew/pacman when new enough),",
      "`cargo install --locked tree-sitter-cli`, or a release binary from",
      "https://github.com/tree-sitter/tree-sitter/releases — not npm.",
    }
    if check("tree-sitter", "tree-sitter CLI", "error", ts_why) then
      local tv = vim.version.parse(version("tree-sitter") or "", { strict = false })
      if tv and not vim.version.ge(tv, { 0, 26, 1 }) then
        h.error(("tree-sitter CLI %s is older than 0.26.1"):format(tostring(tv)), ts_why)
      elseif vim.fn.exepath("tree-sitter"):find("node_modules", 1, true) then
        h.info(
          "tree-sitter CLI comes from npm; nvim-treesitter's README asks for a "
            .. "package-manager, cargo or release build instead."
        )
      end
    end
    check_any({ "curl", "wget" }, "curl or wget", "warn", {
      "Used by Mason and nvim-treesitter to download sources.",
    })
    check("tar", "tar", "warn", {
      "nvim-treesitter (main) unpacks downloaded parser sources with tar.",
    })
  else
    h.info("Automatic parser builds are disabled or no parser languages are selected.")
  end
  if next(requested) and not parser_builds then
    check_any(
      { "curl", "wget" },
      "curl or wget",
      "warn",
      { "Needed for requested Mason package downloads." }
    )
  end
  -- Windows: Mason needs a tar that accepts `--no-same-owner` and C:\ paths.
  -- util.windows_tar_shim() puts System32's bsdtar first on PATH when Mason
  -- loads; report which tar Neovim's child processes actually get.
  if vim.fn.has("win32") == 1 then
    local tar = vim.fn.exepath("tar")
    local sys = ((vim.env.SystemRoot or "C:\\Windows") .. "\\System32\\tar.exe")
    local shim = vim.fn.stdpath("data") .. "/tar-shim"
    local norm = function(p)
      return vim.fs.normalize(p):lower()
    end
    if tar ~= "" and (norm(tar) == norm(sys) or vim.startswith(norm(tar), norm(shim))) then
      h.ok("tar for Mason: Windows bsdtar (" .. tar .. ")")
    else
      h.warn("tar for Mason: " .. (tar ~= "" and tar or "none") .. " (not Windows' bsdtar)", {
        'Mason installs that ship tarballs may fail with "unrecognized option',
        "`--no-same-owner'\". The shim switches to System32\\tar.exe when Mason",
        "loads (run :Mason, then re-check); or put C:\\Windows\\System32 before",
        "the other tool's directory in PATH.",
      })
    end
  end

  -- ── Runtime state directories (persistence must be writable) ──────────────
  h.start("Runtime state directories")
  local option_paths = require("config.util").option_paths
  check_state_dir("Swap directory ('directory')", option_paths(vim.o.directory)[1], {
    "Holds .swp files; the swap guard and :SwapDelete operate on this dir.",
    "If it isn't writable, Neovim opens files without a swap file (E303),",
    "so there is nothing to recover after a crash.",
  })
  if vim.o.undofile then
    check_state_dir("Undo directory ('undodir')", option_paths(vim.o.undodir)[1], {
      "undofile is on, so persistent undo history is written here.",
    })
  else
    h.info("Persistent undo is off ('noundofile') — undodir not checked.")
  end

  -- ── Search & pickers ──────────────────────────────────────────────────────
  h.start("Search & pickers")
  check("rg", "ripgrep (rg)", "warn", {
    "Backs live-grep and file-finding in telescope and fzf-lua.",
    "Without it those pickers fall back to slow built-ins or empty results.",
  })
  check("fzf", "fzf", "warn", {
    "The fzf-lua backend (<leader>F…) needs the real fzf binary.",
    "The telescope backend (<leader>f…) does not, so this is only a warning.",
  })
  -- Distro fzf packages lag badly (Ubuntu 24.04 ships 0.44). fzf-lua
  -- drives fzf with the `transform` action (fzf 0.45+); with an older
  -- binary pickers such as :FzfLua tabs fail with "unknown action:
  -- transform" and never open (observed with 0.44.1).
  do
    local fzf_v = version("fzf")
    local maj, minor = (fzf_v or ""):match("^(%d+)%.(%d+)")
    if maj and tonumber(maj) == 0 and tonumber(minor) < 45 then
      h.warn(("fzf %s is older than 0.45; some fzf-lua pickers will not open"):format(fzf_v), {
        "Install a current release from https://github.com/junegunn/fzf/releases",
        "(or mise / brew / scoop) instead of the distro package.",
      })
    end
  end
  -- Debian/Ubuntu install fd as `fdfind`; telescope and fzf-lua look for both.
  check_any({ "fd", "fdfind" }, "fd", "warn", {
    "Optional but recommended: faster file traversal for find_files.",
    "Both pickers work without it (they fall back to rg / built-ins).",
  })

  -- ── C/C++ toolchain (this config's primary focus) ─────────────────────────
  h.start("C/C++ toolchain")
  if
    selected("clangd")
    or selected("clang-format")
    or selected("cpptools")
    or selected("codelldb")
  then
    if selected("clangd") then
      check(
        "clangd",
        "clangd",
        "warn",
        { "Selected C/C++ language server; Mason or a system LLVM can supply it." }
      )
    end
    if selected("clang-format") then
      check("clang-format", "clang-format", "warn", { "Selected C/C++ formatter." })
    end
    check(
      "clang-tidy",
      "clang-tidy",
      "warn",
      { "Optional standalone Clang-Tidy; clangd includes its own tidy support." }
    )
  else
    h.info("C/C++ tools are not selected for automatic installation.")
  end

  h.start("Language runtimes")
  local node = false
  for name, item in pairs(requested) do
    if item.enabled and require("config.tooling").uses_node(name) then node = true end
  end
  if node then
    check(
      "node",
      "Node.js",
      "warn",
      { "Required by selected JavaScript-based servers, formatters or adapters." }
    )
  else
    h.info("No Node-based tools are selected.")
  end
  if selected("clang-format") or selected("debugpy") then
    check_python({ "Selected Mason PyPI tools need Python 3 with venv/ensurepip." })
    local explicit = require("config.settings").get("tools.executables.python")
    if explicit then
      check_python({ "Configured interpreter for the optional runtime probe." }, explicit)
      h.info(
        "The configured Python path is a runtime probe. Mason's PyPI installer independently resolves python/python3 on PATH."
      )
    end
  else
    h.info("No Python-based Mason packages are selected.")
  end
  if selected("rust-analyzer") then
    check(
      "cargo",
      "cargo (Rust)",
      "warn",
      { "rust-analyzer runs cargo metadata; install the Rust toolchain via rustup." }
    )
  else
    h.info("Rust language-server tooling is not selected.")
  end

  h.start("Dev & test tooling (optional)")
  if
    require("config.settings").get(
      "tools.development",
      selected("lua-language-server") or selected("stylua")
    )
  then
    check("luacheck", "luacheck", "warn", { "make lint and the pre-commit hook use it." })
    check("stylua", "stylua", "warn", { "Lua formatting and make check use it." })
  else
    h.info("Lua config-development checks are not selected.")
  end

  -- ── Mason-managed tooling (delegated) ─────────────────────────────────────
  h.start("Mason-managed servers / formatters / debug adapters")
  if intent_error then h.error("Cannot resolve selected tool requirements: " .. intent_error) end
  for name, item in pairs(requested) do
    if not item.enabled then h.info("Intentionally disabled Mason package: " .. name) end
  end
  if mason_ok then
    h.ok("mason.nvim is available")
    h.info(
      "Mason installs the language servers (ensure_installed in "
        .. "lua/plugins/lsp.lua) and the formatters and debug adapters "
        .. "(ensure_installed in lua/plugins/formatting.lua). Verify them with "
        .. ":Mason and :checkhealth mason rather than here — this check only "
        .. "covers the system-level deps above."
    )
  else
    h.warn("mason.nvim not loaded", { "Run once after startup so lazy.nvim can install it." })
  end

  h.start("Optional tooling skipped on this machine")
  local skipped = require("config.tooling").skipped()
  if next(skipped) == nil then
    h.ok("No optional tooling was skipped by prerequisite checks.")
  else
    local names = vim.tbl_keys(skipped)
    table.sort(names)
    for _, name in ipairs(names) do
      h.warn(name .. ": missing " .. skipped[name])
    end
    h.info(
      "Install the prerequisites and restart. Explicit :MasonInstall / :TSInstall commands remain available."
    )
  end
end

return M
