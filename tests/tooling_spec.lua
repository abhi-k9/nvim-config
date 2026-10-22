describe("optional tool prerequisites", function()
  local previous, executable, has, exepath, system, tools, available

  before_each(function()
    previous = package.loaded["config.tooling"]
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
    package.loaded["config.tooling"] = previous
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
