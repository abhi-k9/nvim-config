describe("health reports effective tool intent", function()
  local saved, handlers, messages, probed, tooling, install_supported, skipped

  before_each(function()
    require("config.settings").reset()
    saved, handlers, messages, probed = {}, {}, {}, {}
    for _, name in ipairs({
      "lazy.core.config",
      "lazy.core.plugin",
      "mason",
      "mason-lspconfig",
      "mason-registry",
    }) do
      saved[name] = package.loaded[name]
    end
    package.loaded["mason"] = {}
    package.loaded["lazy.core.config"] = {
      plugins = {
        ["mason-lspconfig.nvim"] = { opts = { ensure_installed = { "lua_ls@3.13.5" } } },
        ["mason-tool-installer.nvim"] = {
          opts = { ensure_installed = { { "debugpy", condition = false } } },
        },
        ["nvim-treesitter"] = { opts = { parsers = {} } },
      },
    }
    package.loaded["lazy.core.plugin"] = {
      values = function(plugin)
        return plugin.opts
      end,
    }
    tooling = require("config.tooling")
    install_supported, skipped = tooling.install_supported, tooling.skipped
    tooling.install_supported = function(name)
      probed[name] = true
      return false
    end
    tooling.skipped = function()
      return { ["Mason install: lua-language-server"] = "tar" }
    end
    for _, level in ipairs({ "start", "info", "ok", "warn", "error" }) do
      handlers[level] = vim.health[level]
      vim.health[level] = function(message)
        messages[#messages + 1] = message
      end
    end
  end)

  after_each(function()
    require("config.settings").reset()
    for name, value in pairs(saved) do
      package.loaded[name] = value
    end
    -- pairs() cannot retain absent module values.
    for _, name in ipairs({
      "lazy.core.config",
      "lazy.core.plugin",
      "mason",
      "mason-lspconfig",
      "mason-registry",
    }) do
      if saved[name] == nil then package.loaded[name] = nil end
    end
    tooling.install_supported, tooling.skipped = install_supported, skipped
    for level, handler in pairs(handlers) do
      vim.health[level] = handler
    end
  end)

  it(
    "probes requested pinned identities, exposes disabled packages and retains missing-prerequisite reasons",
    function()
      require("config.health").check()
      assert.same({ ["lua-language-server"] = true }, probed)
      local report = table.concat(messages, "\n")
      assert.is_truthy(report:find("Intentionally disabled Mason package: debugpy", 1, true))
      assert.is_truthy(
        report:find(
          "Automatic parser builds are disabled or no parser languages are selected.",
          1,
          true
        )
      )
      assert.is_truthy(report:find("Mason install: lua-language-server: missing tar", 1, true))
      assert.is_truthy(report:find("Rust language-server tooling is not selected.", 1, true))
    end
  )

  it("treats the legacy automatic parser opt-out as intentional disablement", function()
    local previous = vim.g.treesitter_auto_install
    vim.g.treesitter_auto_install = false
    package.loaded["lazy.core.config"].plugins["nvim-treesitter"].opts.parsers = { "python" }
    local ok, err = pcall(function()
      require("config.health").check()
      assert.is_truthy(
        table
          .concat(messages, "\n")
          :find(
            "Automatic parser builds are disabled or no parser languages are selected.",
            1,
            true
          )
      )
    end)
    vim.g.treesitter_auto_install = previous
    assert.is_true(ok, tostring(err))
  end)

  it("reports custom server package identities from loaded registry metadata", function()
    package.loaded["mason-lspconfig"] = nil
    package.loaded["mason-registry"] = {
      get_all_package_specs = function()
        return { { name = "dockerfile-language-server", neovim = { lspconfig = "dockerls" } } }
      end,
    }
    package.loaded["lazy.core.config"].plugins["mason-lspconfig.nvim"].opts.ensure_installed =
      { "dockerls@0.14.1" }
    require("config.health").check()
    assert.same({ ["dockerfile-language-server"] = true }, probed)
    assert.is_nil(package.loaded["mason-lspconfig"])
  end)
end)
