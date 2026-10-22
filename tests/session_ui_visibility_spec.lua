describe("session saves preserve debugger UI visibility", function()
  local original_dap, original_ui, original_windows, spec, active, opened, closed, layouts

  before_each(function()
    original_dap = package.loaded.dap
    original_ui = package.loaded.dapui
    original_windows = package.loaded["dapui.windows"]
    opened, closed, layouts = {}, 0, {}
    active = {}
    package.loaded.dap = {
      session = function()
        return active
      end,
    }
    package.loaded.dapui = {
      close = function()
        closed = closed + 1
      end,
      open = function(opts)
        opened[#opened + 1] = opts.layout
      end,
    }
    package.loaded["dapui.windows"] = { layouts = layouts }
    spec = dofile(vim.fn.getcwd() .. "/lua/plugins/session.lua")
  end)

  after_each(function()
    package.loaded.dap = original_dap
    package.loaded.dapui = original_ui
    package.loaded["dapui.windows"] = original_windows
  end)

  local function layout(visible)
    return {
      is_open = function()
        return visible
      end,
      opened_wins = {},
    }
  end

  local function save()
    spec.opts.pre_save_cmds[2]()
    spec.opts.post_save_cmds[1]()
  end

  it("does not open a deliberately closed UI during active debugging", function()
    layouts[1], layouts[2] = layout(false), layout(false)
    save()
    assert.equals(1, closed)
    assert.are.same({}, opened)
  end)

  it("restores only the previously visible layout", function()
    layouts[1], layouts[2] = layout(false), layout(true)
    save()
    assert.are.same({ 2 }, opened)
    spec.opts.post_save_cmds[1]()
    assert.are.same({ 2 }, opened)
  end)

  it("preserves explicitly open post-mortem panels without an active session", function()
    active = nil
    layouts[1], layouts[2] = layout(true), layout(false)
    save()
    assert.are.same({ 1 }, opened)
  end)

  it("does not reopen layouts if debugging ends during save", function()
    layouts[1] = layout(true)
    spec.opts.pre_save_cmds[2]()
    active = nil
    spec.opts.post_save_cmds[1]()
    assert.are.same({}, opened)
  end)

  it("does not require an unused debugger while saving", function()
    local old_dap, old_ui = package.preload.dap, package.preload.dapui
    package.loaded.dap, package.loaded.dapui = nil, nil
    local loaded = {}
    package.preload.dap = function()
      loaded[#loaded + 1] = "dap"
      return {}
    end
    package.preload.dapui = function()
      loaded[#loaded + 1] = "dapui"
      return {}
    end
    local ok, err = pcall(save)
    package.preload.dap, package.preload.dapui = old_dap, old_ui
    assert.is_true(ok, err)
    assert.are.same({}, loaded)
  end)

  it("degrades safely if upstream layout visibility state is unavailable", function()
    package.loaded["dapui.windows"] = nil
    save()
    assert.are.same({}, opened)
  end)
end)

describe("session saves preserve debugger layout tabs", function()
  local dapui, first, second, original_win

  before_each(function()
    require("lazy.core.loader").load("nvim-dap-ui", { cmd = "spec" })
    dapui = require("dapui")
    dapui.close()
    original_win = vim.api.nvim_get_current_win()
    first = vim.api.nvim_get_current_tabpage()
    vim.cmd("tabnew")
    second = vim.api.nvim_get_current_tabpage()
    dapui.open({ layout = 2 })
    vim.api.nvim_set_current_tabpage(first)
    dapui.open({ layout = 1 })
  end)

  after_each(function()
    dapui.close()
    if vim.api.nvim_tabpage_is_valid(second) then
      vim.api.nvim_set_current_tabpage(second)
      vim.cmd("tabclose!")
    end
    if vim.api.nvim_win_is_valid(original_win) then vim.api.nvim_set_current_win(original_win) end
  end)

  local function layout_tab(index)
    for _, win in ipairs(require("dapui.windows").layouts[index].opened_wins) do
      if vim.api.nvim_win_is_valid(win) then return vim.api.nvim_win_get_tabpage(win) end
    end
  end

  it(
    "restores separate layouts in their original tabs without relocating earlier layouts",
    function()
      assert.equals(first, layout_tab(1))
      assert.equals(second, layout_tab(2))
      local spec = dofile(vim.fn.getcwd() .. "/lua/plugins/session.lua")
      spec.opts.pre_save_cmds[2]()
      spec.opts.post_save_cmds[1]()
      assert.equals(first, layout_tab(1))
      assert.equals(second, layout_tab(2))
      assert.equals(original_win, vim.api.nvim_get_current_win())
    end
  )
end)
