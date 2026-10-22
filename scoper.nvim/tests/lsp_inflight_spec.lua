local Scoper = require("scoper")
local LSP = require("scoper.lsp")

describe("Scoper automatic reload cancellation", function()
  local data, old_data, config, original, pending, applied, reattached

  before_each(function()
    data, old_data = vim.fn.tempname(), vim.env.XDG_DATA_HOME
    vim.env.XDG_DATA_HOME = data
    config = vim.deepcopy(Scoper.config)
    original = {
      filter = LSP._filter_async,
      apply = LSP._apply,
      initial = LSP.apply_initial,
      reattach = LSP._reattach,
      clients = vim.lsp.get_clients,
      client = vim.lsp.get_client_by_id,
      timing = LSP._timing,
    }
    pending, applied, reattached = {}, {}, 0
    LSP._filter_async = function(callback)
      pending[#pending + 1] = callback
    end
    LSP._apply = function(cmd)
      applied[#applied + 1] = cmd
    end
    LSP.apply_initial = function() end
    LSP._reattach = function()
      reattached = reattached + 1
    end
    vim.lsp.get_clients = function()
      return {}
    end
    Scoper.setup({ lsp = { clangd = true } })
  end)

  after_each(function()
    LSP.detach_auto()
    LSP._filter_async, LSP._apply = original.filter, original.apply
    LSP.apply_initial, LSP._reattach = original.initial, original.reattach
    LSP._timing = original.timing
    LSP._reloading, LSP._pending = false, false
    vim.lsp.get_clients, vim.lsp.get_client_by_id = original.clients, original.client
    Scoper.config = config
    pcall(vim.api.nvim_del_augroup_by_name, "scoper_dir")
    vim.env.XDG_DATA_HOME = old_data
    vim.fn.delete(data, "rf")
  end)

  local function disable()
    Scoper.setup({ lsp = { clangd = false } })
  end

  local function complete(index)
    pending[index]("/tmp/filtered-" .. index, "filtered", true)
  end

  it("does not apply an automatic filter result after integration is disabled", function()
    LSP.reload_clangd({ auto = true })
    disable()
    complete(1)
    assert.equals(0, #applied)
    assert.is_false(LSP._reloading)
  end)

  it("continues an explicitly requested manual reload", function()
    LSP.reload_clangd()
    disable()
    complete(1)
    assert.equals(1, #applied)
    assert.equals(1, reattached)
    assert.is_false(LSP._reloading)
  end)

  it("does not replay an automatic request queued before disable", function()
    LSP.reload_clangd({ auto = true })
    LSP.reload_clangd({ auto = true })
    complete(1)
    -- _finish_reload has scheduled a pending request, but it has not run.
    disable()
    vim.wait(20, function()
      return false
    end, 1)
    assert.equals(1, #pending)
    assert.is_false(LSP._reloading)
  end)

  it("preserves a forced pending request when canceling an automatic filter", function()
    LSP.reload_clangd({ auto = true })
    LSP.reload_clangd()
    disable()
    complete(1)
    assert.is_true(vim.wait(100, function()
      return #pending == 2
    end, 1))
    complete(2)
    assert.equals(1, #applied)
    assert.equals(1, reattached)
    assert.is_false(LSP._reloading)
  end)

  it("stops obsolete automatic restart polling without reattaching clients", function()
    local client = { id = 42, root_dir = vim.fn.getcwd(), attached_buffers = {} }
    client.is_stopped = function()
      return false
    end
    client.stop = function() end
    vim.lsp.get_clients = function()
      return { client }
    end
    vim.lsp.get_client_by_id = function()
      return nil
    end
    LSP._timing = { poll = 1, grace = 2, kill = 2 }
    LSP.reload_clangd({ auto = true })
    complete(1)
    disable()
    assert.is_true(vim.wait(100, function()
      return not LSP._reloading
    end, 1))
    assert.equals(0, reattached)
  end)

  it("runs a newly enabled generation after discarding the old filter result", function()
    LSP.reload_clangd({ auto = true })
    disable()
    Scoper.setup({ lsp = { clangd = true } })
    LSP.reload_clangd({ auto = true })
    complete(1)
    assert.is_true(vim.wait(100, function()
      return #pending == 2
    end, 1))
    complete(2)
    assert.equals(1, #applied)
    assert.equals("--compile-commands-dir=/tmp/filtered-2", applied[1][2])
    assert.is_false(LSP._reloading)
  end)
end)
