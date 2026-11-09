describe("Bufferline inspection boundary", function()
  local boundary = require("config.bufferline")
  local saved_line, saved_groups, notify, buffers, elements, pins, line, groups, warnings
  before_each(function()
    saved_line, saved_groups = package.loaded.bufferline, package.loaded["bufferline.groups"]
    notify, warnings, buffers, elements, pins = vim.notify, {}, {}, {}, {}
    vim.notify = function(message)
      warnings[#warnings + 1] = message
    end
    for _ = 1, 3 do
      local buf = vim.api.nvim_create_buf(true, false)
      buffers[#buffers + 1], elements[#elements + 1] = buf, { id = buf }
    end
    line = {
      get_elements = function()
        return { mode = "buffers", elements = elements }
      end,
    }
    line.is_pinned = function(bufnr)
      return pins[bufnr] == true
    end
    groups = {}
    package.loaded.bufferline, package.loaded["bufferline.groups"] = line, groups
  end)
  after_each(function()
    package.loaded.bufferline, package.loaded["bufferline.groups"] = saved_line, saved_groups
    vim.notify = notify
    for _, buf in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    end
  end)

  it("keeps display order, excludes pins and deduplicates entries", function()
    pins[buffers[2]] = true
    elements = { elements[3], elements[2], elements[1], elements[3] }
    assert.same({ buffers[3], buffers[1] }, boundary.unpinned_buffers())
  end)

  it("ignores stale rendered entries hidden by scope or already deleted", function()
    vim.bo[buffers[1]].buflisted = false
    vim.api.nvim_buf_delete(buffers[2], { force = true })
    assert.same({ buffers[3] }, boundary.unpinned_buffers())
  end)

  it("refuses the entire close when any pin state is unknown", function()
    line.is_pinned = function(bufnr)
      if bufnr ~= buffers[3] then return false end
    end
    boundary.close_unpinned()
    for _, buf in ipairs(buffers) do
      assert.is_true(vim.api.nvim_buf_is_valid(buf))
    end
    assert.equals(1, #warnings)
    assert.is_truthy(warnings[1]:find("unknown pin state", 1, true))
  end)

  it("refuses missing or incompatible APIs and tabpage-mode IDs", function()
    local original = line.is_pinned
    line.is_pinned = nil
    assert.is_nil(boundary.unpinned_buffers())
    line.is_pinned = original
    line.get_elements = function()
      return { mode = "tabs", elements = elements }
    end
    assert.is_nil(boundary.unpinned_buffers())
    line.get_elements = function()
      return { mode = "buffers", elements = { { id = 0 } } }
    end
    assert.is_nil(boundary.unpinned_buffers())
    line.get_elements = nil
    assert.is_nil(boundary.unpinned_buffers())
  end)

  it("uses shared deletion to preserve pinned and dirty buffers", function()
    pins[buffers[1]] = true
    vim.api.nvim_buf_set_lines(buffers[3], 0, -1, false, { "unsaved" })
    boundary.close_unpinned()
    assert.is_true(vim.api.nvim_buf_is_valid(buffers[1]))
    assert.is_false(vim.api.nvim_buf_is_valid(buffers[2]))
    assert.is_true(vim.api.nvim_buf_is_valid(buffers[3]))
    assert.is_true(vim.bo[buffers[3]].modified)
  end)
end)
