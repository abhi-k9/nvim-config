local Scoper = require("scoper")
local State = require("scoper.state")
local LSP = require("scoper.lsp")

describe("Scoper LSP setup lifecycle", function()
  local root, data, cache, previous, old_data, old_cache, config
  local apply, reload, defer, calls

  before_each(function()
    root, data, cache = vim.fn.tempname(), vim.fn.tempname(), vim.fn.tempname()
    previous, old_data, old_cache = vim.fn.getcwd(), vim.env.XDG_DATA_HOME, vim.env.XDG_CACHE_HOME
    vim.fn.mkdir(root .. "/src", "p")
    vim.env.XDG_DATA_HOME, vim.env.XDG_CACHE_HOME = data, cache
    vim.cmd.cd(root)
    config = vim.deepcopy(Scoper.config)
    apply, reload, calls = LSP._apply, LSP.reload_clangd, 0
    defer = vim.defer_fn
    LSP._apply = function() end
    LSP.reload_clangd = function()
      calls = calls + 1
    end
    Scoper.setup({ lsp = { clangd = false } })
  end)

  after_each(function()
    LSP.detach_auto()
    LSP._apply, LSP.reload_clangd = apply, reload
    vim.defer_fn = defer
    Scoper.config = config
    pcall(vim.api.nvim_del_augroup_by_name, "scoper_dir")
    vim.cmd.cd(previous)
    vim.env.XDG_DATA_HOME, vim.env.XDG_CACHE_HOME = old_data, old_cache
    for _, dir in ipairs({ root, data, cache }) do
      vim.fn.delete(dir, "rf")
    end
  end)

  local function flush()
    -- Give the actual 500 ms debounce enough time to fire if still active.
    vim.wait(600, function()
      return false
    end, 10)
  end

  it("cancels a pending debounce when integration is disabled", function()
    Scoper.setup({ lsp = { clangd = true } })
    State.add_paths("src")
    assert.is_not_nil(LSP._timer)
    Scoper.setup({ lsp = { clangd = false } })
    flush()
    assert.equals(0, calls)
    assert.is_nil(LSP._timer)
  end)

  it("does not reload after later scope edits while disabled", function()
    Scoper.setup({ lsp = { clangd = true } })
    Scoper.setup({ lsp = { clangd = false } })
    State.add_paths("src")
    flush()
    assert.equals(0, calls)
  end)

  it("can be enabled again with a single debounced listener", function()
    Scoper.setup({ lsp = { clangd = true } })
    Scoper.setup({ lsp = { clangd = false } })
    Scoper.setup({ lsp = { clangd = true } })
    State.add_paths("src")
    State.add_excludes("generated")
    flush()
    assert.equals(1, calls)
  end)

  it("does not schedule an old listener from setup's state load", function()
    Scoper.setup({ lsp = { clangd = true } })
    Scoper.setup({ lsp = { clangd = true } })
    flush()
    assert.equals(0, calls)
  end)

  it("cancels the queued initial cache refresh when disabled", function()
    vim.fn.writefile(
      { vim.json.encode({ { file = "src/main.c", directory = root } }) },
      root .. "/compile_commands.json"
    )
    State.add_paths("src")
    State.toggle()
    Scoper.setup({ lsp = { clangd = true } })
    -- apply_initial's vim.schedule callback has not run yet.
    Scoper.setup({ lsp = { clangd = false } })
    vim.wait(20, function()
      return false
    end, 1)
    assert.equals(0, calls)
  end)

  it("ignores an old queued debounce without losing the replacement timer", function()
    local pending = {}
    vim.defer_fn = function(callback)
      local timer = { closing = false }
      function timer:is_closing()
        return self.closing
      end
      timer.stop = function() end
      function timer:close()
        self.closing = true
      end
      pending[#pending + 1] = { callback = callback, timer = timer }
      return timer
    end
    Scoper.setup({ lsp = { clangd = true } })
    State.add_paths("src")
    State.add_excludes("generated")
    assert.equals(2, #pending)
    -- Model a defer_fn callback queued before its uv timer was closed.
    pending[1].callback()
    assert.equals(0, calls)
    assert.equals(pending[2].timer, LSP._timer)
    pending[2].callback()
    assert.equals(1, calls)
    assert.is_nil(LSP._timer)
  end)
end)
