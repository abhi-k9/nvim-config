describe("Blink completion mappings", function()
  it("keeps ordinary Lua completion available when LazyDev is absent", function()
    require("lazy").load({ plugins = { "blink.cmp" } })
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_call(buf, function()
      vim.bo.filetype = "lua"
      local sources = require("blink.cmp.sources.lib")
      local available = sources.get_enabled_provider_ids("default")
      local loaded = package.loaded.lazydev
      package.loaded.lazydev = nil
      local ok, absent = pcall(sources.get_enabled_provider_ids, "default")
      package.loaded.lazydev = loaded
      assert.is_true(ok)
      assert.is_true(vim.tbl_contains(available, "lazydev"))
      assert.is_false(vim.tbl_contains(absent, "lazydev"))
      assert.is_true(vim.tbl_contains(absent, "lsp"))
    end)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
  it("passes shell argument completion through to the native command line", function()
    require("lazy").load({ plugins = { "blink.cmp" } })
    assert.is_true(vim.wait(2000, function()
      return (vim.fn.maparg("<Tab>", "c", false, true).desc or ""):find("blink", 1, true) ~= nil
    end))
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({}, dir .. "/candidate.txt")
    local lines = {}
    vim.keymap.set("c", "<F12>", function()
      lines[#lines + 1] = vim.fn.getcmdline()
      return "<C-c>"
    end, { expr = true })
    local path = vim.fn.fnameescape(dir .. "/candidate")
    for _, key in ipairs({ "<Tab>", "<S-Tab>" }) do
      local keys = ":!echo " .. path .. key .. "<F12>"
      vim.api.nvim_feedkeys(vim.keycode(keys), "xt", false)
    end
    vim.keymap.del("c", "<F12>")
    vim.fn.delete(dir, "rf")
    assert.equals(2, #lines)
    for _, line in ipairs(lines) do
      assert.is_truthy(line:find("candidate.txt", 1, true), line)
    end
  end)
end)
