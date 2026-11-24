local util = require("config.util")

describe("buffer deletion under window autocmds", function()
  local group
  before_each(function()
    vim.cmd("silent! tabonly!")
    vim.cmd("silent! only!")
    vim.cmd("silent! %bwipe!")
    vim.o.confirm = false
    group = vim.api.nvim_create_augroup("buffer_lifecycle_spec", { clear = true })
  end)
  after_each(function()
    vim.api.nvim_del_augroup_by_id(group)
    vim.cmd("silent! %bwipe!")
  end)

  it("closes the last empty unnamed buffer while keeping both splits", function()
    local victim = vim.api.nvim_get_current_buf()
    vim.cmd("split")
    local wins = vim.api.nvim_list_wins()
    assert.equals("deleted", util.delete_buffer_keep_windows(victim))
    assert.is_false(vim.api.nvim_buf_is_valid(victim))
    assert.equals(vim.api.nvim_win_get_buf(wins[1]), vim.api.nvim_win_get_buf(wins[2]))
    for _, win in ipairs(wins) do
      local buf = vim.api.nvim_win_get_buf(win)
      assert.equals("", vim.api.nvim_buf_get_name(buf))
      assert.is_true(vim.bo[buf].buflisted)
    end
  end)

  it("closes hidden clean targets while preserving hidden edits and focus", function()
    local current = vim.api.nvim_get_current_buf()
    local clean = vim.api.nvim_create_buf(true, false)
    local dirty = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(dirty, vim.fn.tempname() .. "-dirty.txt")
    vim.api.nvim_buf_set_lines(dirty, 0, -1, false, { "unsaved" })
    local result = util.delete_buffers_keep_windows({ clean, dirty })
    assert.equals(1, result.deleted)
    assert.equals(1, #result.skipped)
    assert.same({}, result.failed)
    assert.is_false(vim.api.nvim_buf_is_valid(clean))
    assert.same({ "unsaved" }, vim.api.nvim_buf_get_lines(dirty, 0, -1, false))
    assert.equals(current, vim.api.nvim_get_current_buf())
  end)

  it("tolerates replacement hooks closing other windows", function()
    local victim = vim.api.nvim_get_current_buf()
    vim.cmd("vsplit")
    vim.cmd("vsplit")
    local wins = vim.api.nvim_list_wins()
    local survivor = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_create_autocmd("BufWinEnter", {
      group = group,
      buffer = survivor,
      once = true,
      callback = function()
        local current = vim.api.nvim_get_current_win()
        for _, win in ipairs(wins) do
          if win ~= current and vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
          end
        end
      end,
    })

    assert.are.equal("deleted", util.delete_buffer_keep_windows(victim))
    assert.is_false(vim.api.nvim_buf_is_valid(victim))
    assert.are.equal(survivor, vim.api.nvim_get_current_buf())
  end)

  it("keeps a window opened on the target by a replacement hook", function()
    local victim = vim.api.nvim_get_current_buf()
    local survivor = vim.api.nvim_create_buf(true, false)
    local reopened
    vim.api.nvim_create_autocmd("BufWinEnter", {
      group = group,
      buffer = survivor,
      once = true,
      callback = function()
        reopened = vim.api.nvim_open_win(victim, false, { split = "right" })
      end,
    })

    assert.are.equal("failed", util.delete_buffer_keep_windows(victim))
    assert.are.equal(victim, vim.api.nvim_win_get_buf(reopened))
    assert.are.equal(survivor, vim.api.nvim_get_current_buf())
  end)

  it("detaches a current-buffer target in both tabs without moving focus", function()
    local victim = vim.api.nvim_get_current_buf()
    local first = vim.api.nvim_get_current_win()
    vim.cmd("tab split")
    local second = vim.api.nvim_get_current_win()
    local survivor = vim.api.nvim_create_buf(true, false)

    assert.are.same(
      { deleted = 1, skipped = {}, failed = {} },
      util.delete_buffers_keep_windows({ 0, victim })
    )
    assert.are.equal(second, vim.api.nvim_get_current_win())
    assert.are.equal(survivor, vim.api.nvim_win_get_buf(first))
    assert.are.equal(survivor, vim.api.nvim_win_get_buf(second))
  end)

  it("treats a target removed by a replacement hook as deleted", function()
    local victim = vim.api.nvim_get_current_buf()
    local survivor = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_create_autocmd("BufWinEnter", {
      group = group,
      buffer = survivor,
      once = true,
      callback = function()
        vim.api.nvim_buf_delete(victim, {})
      end,
    })

    assert.are.equal("deleted", util.delete_buffer_keep_windows(victim))
  end)

  it("counts bulk targets already removed by a replacement hook", function()
    local first = vim.api.nvim_get_current_buf()
    local second = vim.api.nvim_create_buf(true, false)
    local survivor = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_create_autocmd("BufWinEnter", {
      group = group,
      buffer = survivor,
      once = true,
      callback = function()
        vim.api.nvim_buf_delete(second, {})
      end,
    })

    assert.are.same(
      { deleted = 2, skipped = {}, failed = {} },
      util.delete_buffers_keep_windows({ first, second })
    )
  end)

  it("preserves edits made to a target by a replacement hook", function()
    local victim = vim.api.nvim_get_current_buf()
    local survivor = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_create_autocmd("BufWinEnter", {
      group = group,
      buffer = survivor,
      once = true,
      callback = function()
        vim.api.nvim_buf_set_lines(victim, 0, -1, false, { "keep me" })
      end,
    })

    assert.are.equal("failed", util.delete_buffer_keep_windows(victim))
    assert.are.same({ "keep me" }, vim.api.nvim_buf_get_lines(victim, 0, -1, false))
    assert.is_true(vim.bo[victim].modified)
  end)
end)
