describe("first language-server initialization", function()
  it("configures overrides and completion before Mason can enable servers", function()
    local result = vim
      .system({
        vim.v.progpath,
        "--headless",
        "--noplugin",
        "-u",
        "NONE",
        "-l",
        "tests/fixtures/lsp_initialization.lua",
      }, { text = true })
      :wait(10000)
    assert.are.equal(0, result.code, result.stderr)
    assert.is_truthy(result.stdout:find("settings and capabilities ready", 1, true))
  end)
end)
