describe("configuration runtime path during cold installation", function()
  it("keeps checkout specs visible after lazy resets its discovery cache", function()
    local dir = vim.fn.tempname()
    local checkout = dir .. "/checkout"
    local manager = vim.fs.dirname(
      vim.fs.dirname(vim.fs.dirname(debug.getinfo(require("lazy").setup, "S").source:sub(2)))
    )
    vim.fn.mkdir(checkout .. "/lua/config", "p")
    vim.fn.mkdir(checkout .. "/lua/plugins", "p")
    vim.fn.writefile(vim.fn.readfile("lua/config/lazy.lua"), checkout .. "/lua/config/lazy.lua")
    vim.fn.writefile(
      vim.fn.readfile("lua/config/settings.lua"),
      checkout .. "/lua/config/settings.lua"
    )
    vim.fn.writefile(
      { 'return { { "audit/cold-fixture" } }' },
      checkout .. "/lua/plugins/probe.lua"
    )
    local script = ([=[
vim.opt.rtp:prepend(%q)
vim.opt.rtp:append(%q)
require('lazy')
local marker = vim.fn.stdpath('data') .. '/lazy/lazy.nvim/lua/lazy'
vim.fn.mkdir(marker, 'p')
vim.fn.writefile({ '-- already loaded manager' }, marker .. '/init.lua')
local installs = 0
package.preload['lazy.manage'] = function()
  return { install = function()
    installs = installs + 1
    -- Real plugin build hooks require new modules while installation is
    -- running, refreshing lazy's runtime discovery after its rtp reset.
    pcall(require, 'cold_install_uncached_module')
    vim.fn.mkdir(vim.fn.stdpath('data') .. '/lazy/cold-fixture', 'p')
  end }
end
vim.go.loadplugins = true
dofile(%q)
assert(installs == 1, 'fixture did not force a cold installation round')
assert(require('lazy.core.config').plugins['cold-fixture'], 'spec lost after cold install reset')
io.stdout:write('checkout specs survived cold reset\n')
]=]):format(checkout, manager, checkout .. "/lua/config/lazy.lua")
    vim.fn.writefile(vim.split(script, "\n", { plain = true }), dir .. "/run.lua")
    local result = vim
      .system({ vim.v.progpath, "--headless", "-u", "NONE", "-l", dir .. "/run.lua" }, {
        text = true,
        env = {
          XDG_CONFIG_HOME = dir .. "/unrelated-config",
          XDG_DATA_HOME = dir .. "/data",
          XDG_STATE_HOME = dir .. "/state",
          XDG_CACHE_HOME = dir .. "/cache",
          NVIM_APPNAME = "nvim",
          NVIM_LOG_FILE = dir .. "/nvim.log",
        },
      })
      :wait(10000)
    vim.fn.delete(dir, "rf")
    assert.equals(0, result.code, result.stderr)
    assert.is_truthy(result.stdout:find("checkout specs survived cold reset", 1, true))
  end)
end)
