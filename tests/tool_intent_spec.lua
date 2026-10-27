local settings = require("config.settings")
local intent = require("config.tool_intent")

describe("declared tool intent", function()
  before_each(function()
    settings.reset()
  end)
  after_each(function()
    settings.reset()
  end)

  it(
    "normalizes server pins and distinguishes explicit disablement from unavailable requirements",
    function()
      settings.configure({ lsp = { servers = { clangd = false } } })
      local wanted = intent.packages({ "lua_ls@3.13.5", "clangd" }, {
        { "debugpy", condition = false },
        "stylua",
        {
          "ruff",
          version = "0.15.0",
          condition = function()
            return true
          end,
        },
      })
      assert.equals("3.13.5", wanted["lua-language-server"].version)
      assert.is_false(wanted.debugpy.enabled)
      assert.is_false(wanted.clangd.enabled)
      assert.is_true(wanted.stylua.enabled)
      local missing = intent.missing_packages(wanted, {
        is_installed = function()
          return false
        end,
      })
      assert.same(
        { "missing mason lua-language-server", "missing mason ruff", "missing mason stylua" },
        missing
      )
    end
  )

  it("checks actual installed versions and refuses incompatible pins", function()
    local wanted = intent.packages({ "lua_ls@3.13.5" }, {})
    local registry = {
      is_installed = function()
        return true
      end,
      get_package = function()
        return {
          get_installed_version = function()
            return "3.13.4"
          end,
        }
      end,
    }
    assert.same(
      { "missing mason lua-language-server@3.13.5 (installed: 3.13.4)" },
      intent.missing_packages(wanted, registry)
    )
    assert.has_error(function()
      intent.packages({ "lua_ls@3.13.5" }, { "lua-language-server@3.14.0" })
    end)
    registry.get_package = function()
      return {
        get_installed_version = function()
          return "3.13.5"
        end,
      }
    end
    assert.same({}, intent.missing_packages(wanted, registry))
  end)

  it("preserves empty selections and per-filetype formatter replacement", function()
    settings.configure({
      tools = { servers = {}, parsers = {}, packages = {}, formatters = { lua = {} } },
    })
    assert.same({}, intent.option("servers", { "lua_ls" }))
    assert.same({}, intent.option("parsers", { "lua" }))
    assert.same({}, intent.option("packages", { "stylua" }))
    assert.same(
      { lua = {}, c = { "clang_format" } },
      require("config.tooling").formatters({ lua = { "stylua" }, c = { "clang_format" } })
    )
  end)

  it("keeps Python features when only one provider is selected", function()
    settings.configure({ tools = { servers = { "ruff" } } })
    assert.same(
      { ruff_hover = true, organize_imports = "ruff", type_checking = "basic" },
      intent.python_policy()
    )
    settings.configure({ tools = { servers = { "pyright" } } })
    assert.same(
      { ruff_hover = false, organize_imports = "pyright", type_checking = "basic" },
      intent.python_policy()
    )
    settings.configure({
      tools = { servers = { "pyright", "ruff" } },
      lsp = { python = { ruff_hover = true, organize_imports = "none", type_checking = "strict" } },
    })
    assert.same(
      { ruff_hover = true, organize_imports = "none", type_checking = "strict" },
      intent.python_policy()
    )
    assert.same({ "ruff_format" }, require("config.tooling").python_formatters())
  end)

  it("keeps strict offline requirements before runtime prerequisite filtering", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local fixture, output = dir .. "/check.lua", dir .. "/report.json"
    local lines = {
      "vim.opt.rtp:prepend(" .. string.format("%q", vim.fn.getcwd()) .. ")",
      "local declared = { ['mason-lspconfig.nvim'] = { ensure_installed = {'lua_ls@3.13.5', 'rust_analyzer'} }, ['mason-tool-installer.nvim'] = { ensure_installed = {{'debugpy', condition=false}} } }",
      "package.loaded['lazy.core.config'] = { plugins = { ['mason-lspconfig.nvim'] = { _ = {installed=true} }, ['mason-tool-installer.nvim'] = { _ = {installed=true} } } }",
      "package.loaded['lazy.core.plugin'] = { values = function(p) for name, item in pairs(package.loaded['lazy.core.config'].plugins) do if item == p then return declared[name] end end return {} end }",
      "package.loaded.lazy = { load = function() end }",
      "package.loaded['mason-lspconfig'] = { get_mappings = function() return {lspconfig_to_package = {lua_ls='lua-language-server', rust_analyzer='rust-analyzer'}} end }",
      "package.loaded['mason-registry'] = { is_installed = function(name) return name == 'lua-language-server' end, get_package = function() return {get_installed_version=function() return '3.13.5' end} end }",
      "vim.env.OFFLINE_SEED_CHECK_OUT = " .. string.format("%q", output),
      "dofile(" .. string.format("%q", vim.fn.getcwd() .. "/scripts/offline-seed-check.lua") .. ")",
    }
    vim.fn.writefile(lines, fixture)
    local result = vim
      .system({ vim.v.progpath, "--headless", "--noplugin", "-u", "NONE", "-l", fixture }, { text = true })
      :wait(10000)
    local ok, err = pcall(function()
      assert.equals(0, result.code, result.stderr)
      assert.same(
        { version = 1, missing = { "missing mason rust-analyzer" } },
        vim.json.decode(table.concat(vim.fn.readfile(output), "\n"))
      )
    end)
    vim.fn.delete(dir, "rf")
    assert.is_true(ok, tostring(err))
  end)

  it("omits deliberately disabled parser provisioning from offline requirements", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local fixture, output = dir .. "/check.lua", dir .. "/report.json"
    local function check(automatic)
      vim.fn.writefile({
        "vim.opt.rtp:prepend(" .. string.format("%q", vim.fn.getcwd()) .. ")",
        "vim.g.treesitter_auto_install = " .. tostring(automatic),
        "package.loaded['lazy.core.config'] = { plugins = { ['nvim-treesitter'] = { _ = {installed=true}, opts = {parsers={'python'}} } } }",
        "package.loaded['lazy.core.plugin'] = { values = function(p) return p.opts end }",
        "package.loaded['nvim-treesitter.config'] = { get_installed = function() return {} end }",
        -- No compiler/download tools: this must not erase enabled intent.
        "vim.fn.executable = function() return 0 end",
        "vim.env.OFFLINE_SEED_CHECK_OUT = " .. string.format("%q", output),
        "dofile("
          .. string.format("%q", vim.fn.getcwd() .. "/scripts/offline-seed-check.lua")
          .. ")",
      }, fixture)
      local result = vim
        .system(
          { vim.v.progpath, "--headless", "--noplugin", "-u", "NONE", "-l", fixture },
          { text = true }
        )
        :wait(10000)
      assert.equals(0, result.code, result.stderr)
      return vim.json.decode(table.concat(vim.fn.readfile(output), "\n"))
    end
    local ok, err = pcall(function()
      assert.same({ version = 1, missing = {} }, check(false))
      assert.same({ version = 1, missing = { "missing parser python" } }, check(true))
    end)
    vim.fn.delete(dir, "rf")
    assert.is_true(ok, tostring(err))
  end)
end)

describe("Mason server aliases", function()
  local saved, preloads
  local modules = { "mason-lspconfig", "mason-registry" }

  before_each(function()
    saved, preloads = {}, {}
    for _, name in ipairs(modules) do
      saved[name], preloads[name] = package.loaded[name], package.preload[name]
      package.loaded[name] = nil
    end
  end)

  after_each(function()
    for _, name in ipairs(modules) do
      package.loaded[name], package.preload[name] = saved[name], preloads[name]
    end
  end)

  it("uses loaded registry metadata for custom aliases and retains shipped fallbacks", function()
    package.loaded["mason-registry"] = {
      get_all_package_specs = function()
        return {
          { name = "dockerfile-language-server", neovim = { lspconfig = "dockerls" } },
          { name = "package-without-server" },
          { name = "invalid", neovim = { lspconfig = {} } },
        }
      end,
    }
    local mapping = intent.mapping()
    assert.equals("dockerfile-language-server", mapping.dockerls)
    assert.equals("lua-language-server", mapping.lua_ls)
    local wanted = intent.packages({ "dockerls@0.14.1" }, {})
    assert.equals("0.14.1", wanted["dockerfile-language-server"].version)
    assert.is_nil(wanted.dockerls)
    assert.is_nil(intent.server_packages.dockerls)
  end)

  it("uses loaded bridge aliases and reflects metadata updates", function()
    local name = "dockerfile-language-server"
    package.loaded["mason-lspconfig"] = {
      get_mappings = function()
        return { lspconfig_to_package = { dockerls = name } }
      end,
    }
    assert.equals(name, intent.mapping().dockerls)
    name = "custom-docker-server"
    assert.equals(name, intent.mapping().dockerls)
  end)

  it("does not autoload either metadata owner when absent", function()
    local loads = 0
    for _, name in ipairs(modules) do
      package.preload[name] = function()
        loads = loads + 1
        error("metadata owner must stay unloaded")
      end
    end
    assert.same(intent.server_packages, intent.mapping())
    assert.equals(0, loads)
    for _, name in ipairs(modules) do
      assert.is_nil(package.loaded[name])
    end
  end)

  it("retains shipped aliases when loaded metadata cannot be read", function()
    package.loaded["mason-registry"] = {
      get_all_package_specs = function()
        error("registry is unavailable")
      end,
    }
    package.loaded["mason-lspconfig"] = {
      get_mappings = function()
        error("mapping is unavailable")
      end,
    }
    assert.same(intent.server_packages, intent.mapping())
  end)
end)

describe("installer requirement validation", function()
  local config, plugin, previous_plugins, previous_lsp, previous_installer, previous_registry, calls

  before_each(function()
    settings.reset()
    config, plugin = require("lazy.core.config"), require("lazy.core.plugin")
    previous_plugins = config.plugins
    previous_lsp = package.loaded["mason-lspconfig"]
    previous_installer = package.loaded["mason-tool-installer"]
    previous_registry = package.loaded["mason-registry"]
    calls = { servers = 0, packages = 0 }
    package.loaded["mason-lspconfig"] = {
      setup = function()
        calls.servers = calls.servers + 1
      end,
    }
    package.loaded["mason-tool-installer"] = {
      setup = function()
        calls.packages = calls.packages + 1
      end,
    }
  end)

  after_each(function()
    config.plugins = previous_plugins
    package.loaded["mason-lspconfig"] = previous_lsp
    package.loaded["mason-tool-installer"] = previous_installer
    package.loaded["mason-registry"] = previous_registry
    settings.reset()
  end)

  local function configure(servers, packages, native)
    settings.configure({
      tools = { servers = native and {} or servers, packages = native and {} or packages },
    })
    local specs = {
      dofile(vim.fn.getcwd() .. "/lua/plugins/lsp.lua")[2],
      dofile(vim.fn.getcwd() .. "/lua/plugins/formatting.lua")[2],
    }
    if native then
      specs[#specs + 1] = {
        "mason-org/mason-lspconfig.nvim",
        opts = function(_, opts)
          opts.ensure_installed = servers
        end,
      }
      specs[#specs + 1] = {
        "WhoIsSethDaniel/mason-tool-installer.nvim",
        opts = function(_, opts)
          return vim.tbl_extend("force", opts, { ensure_installed = packages })
        end,
      }
    end
    -- Exercise Lazy's actual opts inheritance/cache and the shipped config
    -- callbacks; direct intent.packages calls cannot catch missing wiring.
    config.plugins = plugin.Spec.new(specs, { pkg = false }).plugins
  end

  local function run(name)
    local spec = config.plugins[name]
    spec.config(spec, plugin.values(spec, "opts", false))
  end

  local owners = { "mason-lspconfig.nvim", "mason-tool-installer.nvim" }
  it(
    "rejects custom server/package pins using loaded registry metadata before either setup",
    function()
      package.loaded["mason-registry"] = {
        get_all_package_specs = function()
          return { { name = "dockerfile-language-server", neovim = { lspconfig = "dockerls" } } }
        end,
      }
      configure({ "dockerls@0.14.1" }, { "dockerfile-language-server@0.14.0" }, true)
      for _, owner in ipairs(owners) do
        local ok, err = pcall(run, owner)
        assert.is_false(ok)
        assert.is_truthy(
          tostring(err):find(
            "conflicting version requirements for Mason package dockerfile-language-server",
            1,
            true
          )
        )
        assert.same({ servers = 0, packages = 0 }, calls)
      end
    end
  )

  for _, native in ipairs({ false, true }) do
    local source = native and "native Lazy opts" or "tool settings"
    it(
      "rejects duplicate package pins from " .. source .. " before either installer setup",
      function()
        configure({}, { "stylua@2.3.0", { "stylua", version = "2.3.1" } }, native)
        for _, owner in ipairs(owners) do
          local ok, err = pcall(run, owner)
          assert.is_false(ok)
          assert.is_truthy(
            tostring(err):find("conflicting version requirements for Mason package stylua", 1, true)
          )
          assert.same({ servers = 0, packages = 0 }, calls)
        end
      end
    )

    it(
      "rejects server/package pin conflicts from " .. source .. " before either installer setup",
      function()
        configure({ "lua_ls@3.13.5" }, { "lua-language-server@3.14.0" }, native)
        for _, owner in ipairs(owners) do
          local ok, err = pcall(run, owner)
          assert.is_false(ok)
          assert.is_truthy(
            tostring(err):find(
              "conflicting version requirements for Mason package lua-language-server",
              1,
              true
            )
          )
          assert.same({ servers = 0, packages = 0 }, calls)
        end
      end
    )
  end

  it(
    "excludes boolean and function false conditions from conflicts before both installer setups",
    function()
      configure({ "lua_ls@3.13.5" }, {
        { "lua-language-server", version = "3.14.0", condition = false },
        {
          "stylua",
          version = "2.3.0",
          condition = function()
            return false
          end,
        },
        "stylua@2.3.1",
      }, true)
      for _, owner in ipairs(owners) do
        run(owner)
      end
      assert.same({ servers = 1, packages = 1 }, calls)
    end
  )
end)
