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
-- SCOPE. It checks the SYSTEM prerequisites Mason cannot provide, plus the
-- C/C++ toolchain this config is built around. It deliberately does NOT
-- re-verify the language servers / formatters / debug adapters that Mason
-- installs into its own prefix — that is `:checkhealth mason`'s job, and
-- duplicating it here would double-report and drift. Where a tool can come
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
  if vim.fn.has("win32") == 0 then return nil end
  local vswhere = (vim.env["ProgramFiles(x86)"] or "C:\\Program Files (x86)")
    .. "\\Microsoft Visual Studio\\Installer\\vswhere.exe"
  if not have(vswhere) then return nil end
  local ok, out = pcall(vim.fn.systemlist, {
    vswhere,
    "-latest",
    "-products",
    "*",
    "-requires",
    "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
    "-property",
    "installationPath",
  })
  if not ok or vim.v.shell_error ~= 0 or type(out) ~= "table" then return nil end
  local path = (out[1] or ""):gsub("%s+$", "")
  return path ~= "" and path or nil
end

-- Python 3 for Mason's PyPI packages. On Windows, python3/python under
-- ...\WindowsApps\ may be the Microsoft Store alias stub: on PATH, but every
-- call fails, so a PATH test alone passes falsely.
local function check_python(why)
  local stub
  for _, b in ipairs({ "python3", "python" }) do
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
  path = (path or ""):gsub("[/\\]+$", "")
  if path == "" then
    h.warn(label .. " is not set", why)
    return
  end
  if vim.fn.isdirectory(path) == 1 then
    if vim.fn.filewritable(path) == 2 then
      h.ok(("%s — writable (%s)"):format(label, path))
    else
      h.error(("%s exists but is NOT writable (%s)"):format(label, path), why)
    end
    return
  end
  -- Doesn't exist yet: walk up to the nearest existing ancestor and test it.
  local anc = vim.fn.fnamemodify(path, ":h")
  while anc ~= "" and vim.fn.isdirectory(anc) == 0 do
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
        .. "lua/config/options.lua."
    )
  end

  -- ── Core system prerequisites Mason cannot provide ────────────────────────
  h.start("Core prerequisites (must be on PATH — Mason cannot supply these)")
  check("git", "git", "error", { "Required by lazy.nvim to clone/update plugins and by Mason." })
  local msvc = msvc_install_path()
  if msvc then
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
  -- every entry in treesitter.lua's PARSERS fails with
  -- "ENOENT … 'tree-sitter'" and only Neovim's bundled parsers (c, lua,
  -- markdown, query, vim, vimdoc) highlight. The minimum matches
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
  check_state_dir("Swap directory ('directory')", vim.o.directory:match("^[^,]*"), {
    "Holds .swp files; the swap guard and :SwapDelete operate on this dir.",
    "If it isn't writable, Neovim opens files without a swap file (E303),",
    "so there is nothing to recover after a crash.",
  })
  if vim.o.undofile then
    check_state_dir("Undo directory ('undodir')", vim.o.undodir:match("^[^,]*"), {
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
  check("clangd", "clangd", "warn", {
    "The C/C++ language server. Mason installs it (lua/plugins/lsp.lua);",
    "a system LLVM on PATH works too.",
  })
  check("clang-format", "clang-format", "warn", {
    "Drives <leader>cf and format-on-save for C/C++ (conform's clang_format).",
  })
  check("clang-tidy", "clang-tidy", "warn", {
    "Powers the .clang-tidy diagnostics (standalone, and via clangd).",
  })
  h.info(
    "The bundled docs/templates/cpp/.clang-tidy is written for a recent "
      .. "clang-tidy. An older clangd/clang-tidy may warn about unknown check "
      .. "options — trim them to match your installed version."
  )

  -- ── Language runtimes for the configured servers ──────────────────────────
  h.start("Language runtimes")
  check("node", "Node.js", "warn", {
    "Mason installs the npm-based packages from the ensure_installed lists in",
    "lua/plugins/lsp.lua and lua/plugins/formatting.lua (pyright, bashls, ts_ls,",
    "jsonls, yamlls, prettierd, …); all of them run on Node.js.",
  })
  check_python({
    "Mason installs clang-format and debugpy from PyPI, which needs Python 3",
    "(`python` on Windows). debugpy is the Python debug adapter.",
  })
  check("cargo", "cargo (Rust)", "warn", {
    "rust_analyzer locates the project with `cargo metadata`; without cargo",
    'it logs "cargo not found" and never attaches. Install via rustup.',
    "(Ignore if you don't write Rust.)",
  })

  -- ── Optional: dev / test tooling ──────────────────────────────────────────
  h.start("Dev & test tooling (optional)")
  check("luacheck", "luacheck", "warn", { "`make lint` / the pre-commit hook and CI use it." })
  check("stylua", "stylua", "warn", {
    "Lua formatter (conform). `make check` and CI also run `stylua --check`;",
    "CI pins its stylua version, so a different local version can disagree.",
  })

  -- ── Mason-managed tooling (delegated) ─────────────────────────────────────
  h.start("Mason-managed servers / formatters / debug adapters")
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
end

return M
