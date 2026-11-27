describe("machine-local startup policy", function()
  it("keeps project file discovery opt-in on a fresh startup", function()
    local result = vim
      .system({
        vim.v.progpath,
        "--headless",
        "-u",
        "NONE",
        "-l",
        "-",
      }, {
        text = true,
        stdin = [[
        vim.opt.rtp:prepend(vim.fn.getcwd())
        local settings = require("config.settings")
        vim.g.config_local_file = false
        settings.bootstrap(vim.fn.getcwd())
        require("config.options")
        settings.apply_options()
        assert(not vim.o.exrc, "project file discovery enabled without opting in")
        settings.configure({ options = { exrc = true } })
        settings.apply_options()
        assert(vim.o.exrc, "explicit opt-in ignored")
      ]],
      })
      :wait(5000)
    assert.equals(0, result.code, result.stderr)
  end)

  it("applies the real override file before maps and first plugin options", function()
    local result = vim
      .system({
        vim.v.progpath,
        "--headless",
        "--noplugin",
        "-u",
        "NONE",
        "-l",
        "tests/fixtures/settings_startup.lua",
      }, { text = true })
      :wait(10000)
    assert.equals(0, result.code, result.stderr)
    assert.is_truthy(result.stdout:find("local settings ready before maps and plugins", 1, true))
  end)
end)
