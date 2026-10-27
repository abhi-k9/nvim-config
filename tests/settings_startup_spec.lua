describe("machine-local startup policy", function()
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
