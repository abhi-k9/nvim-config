describe("bundled Scoper plugin location", function()
  it("resolves from the checkout even when stdpath(config) points elsewhere", function()
    local original_stdpath = vim.fn.stdpath
    vim.fn.stdpath = function(name)
      if name == "config" then return "/not-the-checkout/nvim" end
      return original_stdpath(name)
    end
    local ok, spec = pcall(dofile, vim.fn.getcwd() .. "/lua/plugins/scoper.lua")
    vim.fn.stdpath = original_stdpath
    assert.is_true(ok, spec)
    assert.are.equal(
      vim.fs.normalize(vim.fn.getcwd() .. "/scoper.nvim"),
      vim.fs.normalize(spec[1].dir)
    )
  end)
end)
