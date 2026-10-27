describe("optional tool prerequisites", function()
  local previous, executable, has, exepath, system, tools, available, cc, cwd, fixture

  before_each(function()
    previous = package.loaded["config.tooling"]
    require("config.settings").reset()
    cwd, fixture = vim.fn.getcwd(-1, -1), nil
    cc, vim.env.CC = vim.env.CC, nil
    executable, has, exepath, system = vim.fn.executable, vim.fn.has, vim.fn.exepath, vim.system
    available = {}
    vim.fn.executable = function(bin)
      return available[bin] and 1 or 0
    end
    vim.fn.has = function(feature)
      return feature == "win32" and 0 or has(feature)
    end
    vim.system = function(args, opts)
      if args[1] == "python" or args[1] == "python3" then
        return {
          wait = function()
            return { code = 0 }
          end,
        }
      end
      return system(args, opts)
    end
    package.loaded["config.tooling"] = nil
    tools = require("config.tooling")
  end)

  after_each(function()
    require("config.settings").reset()
    vim.cmd.cd(cwd)
    if fixture then vim.fn.delete(fixture, "rf") end
    package.loaded["config.tooling"] = previous
    vim.env.CC = cc
    vim.fn.executable, vim.fn.has, vim.fn.exepath, vim.system = executable, has, exepath, system
  end)

  it("does not start parser builds when only the CLI is installed", function()
    available = { ["tree-sitter"] = true, curl = true, tar = true }
    assert.is_false(tools.parsers_ready())
    assert.equals("C compiler", tools.skipped()["Treesitter automatic parser installation"])
    available.cc = true
    assert.is_true(tools.parsers_ready())
    assert.is_nil(next(tools.skipped()))
  end)

  it("keeps prebuilt Lua tools independent of Lua, LuaRocks, Rust and C", function()
    available = { curl = true, tar = true, unzip = true }
    assert.is_true(tools.install_supported("lua-language-server"))
    assert.is_true(tools.install_supported("stylua"))
  end)

  it("does not install npm packages without npm but permits their installed runtime", function()
    available = { curl = true, node = true }
    assert.is_false(tools.install_supported("pyright"))
    assert.same({}, tools.runtime_missing("pyright"))
    available.npm = true
    assert.is_true(tools.install_supported("pyright"))
  end)

  it("skips unsupported installs and copied servers without mutating the declared list", function()
    local input = {
      ensure_installed = { "lua_ls", "pyright", "rust_analyzer" },
      automatic_enable = { exclude = { "stylua" } },
    }
    local opts = tools.configure_servers(input)
    assert.same({}, opts.ensure_installed)
    assert.is_true(vim.tbl_contains(opts.automatic_enable.exclude, "pyright"))
    assert.is_true(vim.tbl_contains(opts.automatic_enable.exclude, "rust_analyzer"))
    assert.is_true(vim.tbl_contains(opts.automatic_enable.exclude, "stylua"))
    assert.is_false(vim.tbl_contains(opts.automatic_enable.exclude, "lua_ls"))
    assert.equals(3, #input.ensure_installed)
    assert.same({ "stylua" }, input.automatic_enable.exclude)
  end)

  it("preserves automatic installation and reporting on a complete machine", function()
    available = {
      curl = true,
      node = true,
      npm = true,
      cargo = true,
      rustc = true,
      python3 = true,
      tar = true,
      unzip = true,
      gzip = true,
    }
    local opts = tools.configure_servers({
      ensure_installed = { "lua_ls", "pyright", "rust_analyzer" },
      automatic_enable = { exclude = { "stylua" } },
    })
    assert.same({ "lua_ls", "pyright", "rust_analyzer" }, opts.ensure_installed)
    assert.same({ "stylua" }, opts.automatic_enable.exclude)
    assert.is_nil(next(tools.skipped()))
  end)

  it("rejects Windows Store Python aliases for PyPI tools", function()
    available = { curl = true, python3 = true }
    vim.fn.exepath = function()
      return [[C:\Users\user\AppData\Local\Microsoft\WindowsApps\python3.exe]]
    end
    assert.is_false(tools.install_supported("debugpy"))
    available.python = true
    vim.fn.exepath = function(bin)
      return bin == "python" and "C:/Python/python.exe" or exepath(bin)
    end
    assert.is_true(tools.install_supported("debugpy"))
  end)

  it("checks native archive tools and the Node runtime of the GitHub Bash adapter", function()
    available.curl = true
    assert.is_false(tools.install_supported("stylua"))
    available.unzip = true
    assert.is_true(tools.install_supported("stylua"))
    assert.is_false(tools.install_supported("bash-debug-adapter"))
    available.node = true
    assert.is_true(tools.install_supported("bash-debug-adapter"))
  end)

  it("wires installer conditions per package and leaves manual commands available", function()
    local old = package.loaded["mason-tool-installer"]
    local observed
    package.loaded["mason-tool-installer"] = {
      setup = function(opts)
        observed = opts
      end,
    }
    local spec = dofile(vim.fn.getcwd() .. "/lua/plugins/formatting.lua")[2]
    local ok, err = pcall(function()
      spec.config(nil, spec.opts)
      assert.is_false(observed.run_on_start)
      assert.is_true(spec.opts.run_on_start)
      local conditions = {}
      for _, entry in ipairs(observed.ensure_installed) do
        conditions[entry[1]] = entry.condition
      end
      available = { curl = true, unzip = true }
      assert.is_true(conditions.stylua())
      assert.is_false(conditions.prettierd())
      assert.is_false(conditions.debugpy())
      available.node, available.npm = true, true
      assert.is_true(conditions.prettierd())
    end)
    package.loaded["mason-tool-installer"] = old
    assert.is_true(ok, tostring(err))
  end)

  it("skips a partial Python installation without venv and caches the bounded probe", function()
    available = { curl = true, python3 = true }
    local calls = 0
    vim.system = function()
      calls = calls + 1
      return {
        wait = function(_, timeout)
          assert.equals(1500, timeout)
          return { code = 1, stderr = "No module named ensurepip" }
        end,
      }
    end
    assert.is_false(tools.install_supported("clang-format"))
    assert.is_false(tools.install_supported("debugpy"))
    assert.equals(1, calls)
  end)

  it("respects automatic-enable opt-outs and allowlists", function()
    local disabled = tools.configure_servers({ automatic_enable = false })
    assert.is_false(disabled.automatic_enable)
    local allowed = tools.configure_servers({ automatic_enable = { "lua_ls", "pyright" } })
    assert.same({ "lua_ls" }, allowed.automatic_enable)
    assert.is_table(tools.configure_servers({ automatic_enable = true }).automatic_enable.exclude)
  end)

  it("checks prerequisites of version-pinned language servers", function()
    available = { curl = true, tar = true, unzip = true }
    local opts = tools.configure_servers({
      ensure_installed = { "pyright@1.1.414", "lua_ls@3.19.2" },
    })
    assert.same({ "lua_ls@3.19.2" }, opts.ensure_installed)
  end)

  it("resolves custom aliases from current loaded metadata before checking installers", function()
    local registry, bridge, supported =
      package.loaded["mason-registry"], package.loaded["mason-lspconfig"], tools.install_supported
    local name, observed = "dockerfile-language-server", {}
    package.loaded["mason-lspconfig"] = nil
    package.loaded["mason-registry"] = {
      get_all_package_specs = function()
        return { { name = name, neovim = { lspconfig = "dockerls" } } }
      end,
    }
    tools.install_supported = function(package)
      observed[#observed + 1] = package
      return true
    end
    local ok, err = pcall(function()
      local opts = tools.configure_servers({ ensure_installed = { "dockerls@0.14.1" } })
      assert.same({ "dockerls@0.14.1" }, opts.ensure_installed)
      name = "custom-docker-server"
      tools.configure_servers({ ensure_installed = { "dockerls@0.14.1" } })
      assert.same({ "dockerfile-language-server", "custom-docker-server" }, observed)
    end)
    package.loaded["mason-registry"], package.loaded["mason-lspconfig"], tools.install_supported =
      registry, bridge, supported
    assert.is_true(ok, tostring(err))
  end)

  it("preserves Mason tool versions and caller conditions", function()
    local old = package.loaded["mason-tool-installer"]
    local observed, enabled
    package.loaded["mason-tool-installer"] = {
      setup = function(opts)
        observed = opts
      end,
    }
    local spec = dofile(vim.fn.getcwd() .. "/lua/plugins/formatting.lua")[2]
    local condition = function()
      return enabled == true
    end
    spec.opts.ensure_installed = {
      { "prettierd", version = "0.29.0", auto_update = true, condition = condition },
      "stylua",
    }
    available = { curl = true, unzip = true }
    local ok, err = pcall(function()
      spec.config(nil, spec.opts)
      local entry = observed.ensure_installed[1]
      assert.equals("prettierd", entry[1])
      assert.equals("0.29.0", entry.version)
      assert.is_true(entry.auto_update)
      enabled = true
      assert.is_false(entry.condition()) -- Node/npm are still unavailable.
      available.node, available.npm = true, true
      enabled = false
      assert.is_false(entry.condition()) -- Preserve the caller's opt-out.
      enabled = true
      assert.is_true(entry.condition())
      assert.equals(condition, spec.opts.ensure_installed[1].condition)
    end)
    package.loaded["mason-tool-installer"] = old
    assert.is_true(ok, tostring(err))
  end)

  it("keeps Telescope's Lua sorter when no native build chain exists", function()
    assert.is_false(tools.native_sorter_build())
    available.make = true
    assert.is_false(tools.native_sorter_build())
    available.cc = true
    assert.equals("make", tools.native_sorter_build())
  end)

  it("requires gcc for Telescope's Windows Makefile and supports CMake with MSVC", function()
    vim.fn.has = function(feature)
      return feature == "win32" and 1 or has(feature)
    end
    available = { make = true, cl = true }
    assert.is_false(tools.native_sorter_build())
    available.cmake = true
    assert.is_string(tools.native_sorter_build())
    available.gcc = true
    assert.equals("make", tools.native_sorter_build())
  end)

  it("quietly selects Lua completion when the downloader is absent", function()
    assert.equals("lua", tools.blink_implementation())
    available = { curl = true, sha256sum = true, shasum = true, sha256 = true }
    assert.equals("prefer_rust_with_warning", tools.blink_implementation())
  end)

  it("recognizes an absolute compiler and uses literal CMake argv for paths with spaces", function()
    local compiler = "/tools/my compiler/clang"
    available = { [compiler] = true, cmake = true, make = true }
    require("config.settings").configure({ tools = { executables = { compiler = compiler } } })
    assert.is_true(tools.compiler())
    local calls = {}
    vim.system = function(args, opts)
      calls[#calls + 1] = { args = args, cwd = opts.cwd }
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end
    local build = tools.native_sorter_build()
    assert.is_function(build)
    build({ dir = "/plugin with spaces" })
    assert.equals("-DCMAKE_C_COMPILER=" .. compiler, calls[1].args[5])
    assert.equals("/plugin with spaces", calls[1].cwd)
    assert.equals(2, #calls)
    assert.equals(compiler, vim.env.CC)
    available.cmake = nil
    assert.is_false(tools.native_sorter_build())
  end)

  it("recognizes inherited absolute CC without assuming Windows Make uses it", function()
    vim.env.CC = "/toolchain/clang"
    available = { [vim.env.CC] = true, make = true }
    assert.is_true(tools.compiler())
    assert.equals("make", tools.native_sorter_build())
    vim.fn.has = function(feature)
      return feature == "win32" and 1 or has(feature)
    end
    assert.is_false(tools.native_sorter_build())
  end)

  it("restores the inherited compiler after leaving a project override", function()
    vim.env.CC = "/inherited/cc"
    available = { ["/inherited/cc"] = true, ["/project/clang"] = true }
    require("config.settings").configure({
      tools = { executables = { compiler = "/project/clang" } },
    })
    assert.is_true(tools.compiler())
    assert.equals("/project/clang", vim.env.CC)
    require("config.settings").reset()
    assert.is_true(tools.compiler())
    assert.equals("/inherited/cc", vim.env.CC)
  end)

  local function project_dirs()
    fixture = vim.fn.tempname()
    local a, b = fixture .. "/a", fixture .. "/b"
    vim.fn.mkdir(a, "p")
    vim.fn.mkdir(b, "p")
    return a, b
  end

  it("reconciles project CC synchronously on global directory changes", function()
    local a, b = project_dirs()
    vim.env.CC = "/inherited/cc"
    available = { ["/inherited/cc"] = true, ["/project/clang"] = true }
    require("config.settings").for_project(a, {
      tools = { executables = { compiler = "/project/clang" } },
    })
    vim.cmd.cd(a)
    assert.equals("/project/clang", vim.env.CC)
    vim.cmd.cd(b)
    -- A terminal or task can start here, before any readiness probe runs.
    assert.equals("/inherited/cc", vim.env.CC)
  end)

  it("preserves external CC edits across local and global directory changes", function()
    local a, b = project_dirs()
    vim.env.CC = "/inherited/cc"
    available = { ["/project/clang"] = true }
    require("config.settings").for_project(a, {
      tools = { executables = { compiler = "/project/clang" } },
    })
    vim.cmd.cd(a)
    assert.equals("/project/clang", vim.env.CC)
    vim.env.CC = "/external/cc"
    vim.cmd.lcd(b)
    assert.equals(a, vim.fn.getcwd(-1, -1))
    assert.equals("/external/cc", vim.env.CC)
    vim.cmd.cd(b)
    assert.equals("/external/cc", vim.env.CC)
  end)

  it("clears a machine compiler when a project replaces its executable table", function()
    local a, b = project_dirs()
    local settings = require("config.settings")
    vim.env.CC = "/inherited/cc"
    available = { ["/inherited/cc"] = true, ["/machine/clang"] = true }
    settings.configure({ tools = { executables = { compiler = "/machine/clang" } } })
    tools.configure_build_environment()
    assert.equals("/machine/clang", vim.env.CC)
    settings.for_project(a, { tools = { executables = {} } })
    vim.cmd.cd(a)
    assert.same({}, settings.get("tools.executables"))
    assert.is_nil(settings.get("tools.executables.compiler"))
    assert.equals("/inherited/cc", vim.env.CC)
    vim.cmd.cd(b)
    assert.equals("/machine/clang", vim.env.CC)
  end)

  it("does not mistake a custom Python probe for Mason's PATH interpreter", function()
    require("config.settings").configure({
      tools = { executables = { python = "/runtime/python-custom" } },
    })
    available = { curl = true, ["/runtime/python-custom"] = true }
    assert.is_false(tools.install_supported("debugpy"))
    available.python3 = true
    assert.is_true(tools.install_supported("debugpy"))
  end)

  it("honors an explicit false installer condition and normalizes tool pins", function()
    local old = package.loaded["mason-tool-installer"]
    local observed
    package.loaded["mason-tool-installer"] = {
      setup = function(opts)
        observed = opts
      end,
    }
    local spec = dofile(vim.fn.getcwd() .. "/lua/plugins/formatting.lua")[2]
    spec.opts.ensure_installed = { { "debugpy", condition = false }, "stylua@2.3.1" }
    available = { curl = true, unzip = true, python3 = true }
    local ok, err = pcall(function()
      spec.config(nil, spec.opts)
      assert.is_false(observed.ensure_installed[1].condition())
      assert.equals("stylua", observed.ensure_installed[2][1])
      assert.equals("2.3.1", observed.ensure_installed[2].version)
      assert.is_true(observed.ensure_installed[2].condition())
    end)
    package.loaded["mason-tool-installer"] = old
    assert.is_true(ok, tostring(err))
  end)

  it("recognizes MSVC without cl on PATH and bounds its discovery", function()
    vim.fn.has = function(feature)
      return feature == "win32" and 1 or has(feature)
    end
    vim.fn.executable = function(bin)
      return bin:match("vswhere.exe$") and 1 or 0
    end
    local calls = 0
    vim.system = function()
      calls = calls + 1
      return {
        wait = function(_, timeout)
          assert.equals(1500, timeout)
          return { code = 0, stdout = "C:\\Build Tools\r\n" }
        end,
      }
    end
    assert.is_true(tools.compiler())
    assert.is_true(tools.compiler())
    assert.equals(1, calls)
  end)
end)
