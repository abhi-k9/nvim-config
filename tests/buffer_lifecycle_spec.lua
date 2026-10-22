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
