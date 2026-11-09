-- Keep Bufferline-specific inspection out of the shared safe-delete helpers.
-- Validate the public snapshot and pin query before selecting any close targets.
local M = {}

function M.unpinned_buffers()
  local ok, result = pcall(function()
    local line = require("bufferline")
    assert(type(line.get_elements) == "function", "buffer list API unavailable")
    assert(type(line.is_pinned) == "function", "pin inspection API unavailable")
    local snapshot = line.get_elements()
    assert(type(snapshot) == "table" and snapshot.mode == "buffers", "not in buffer mode")
    assert(
      type(snapshot.elements) == "table" and vim.islist(snapshot.elements),
      "invalid buffer list"
    )
    local buffers, seen = {}, {}
    for _, element in ipairs(snapshot.elements) do
      assert(
        type(element) == "table"
          and type(element.id) == "number"
          and element.id > 0
          and element.id % 1 == 0,
        "invalid buffer entry"
      )
      local buf = element.id
      -- Rendered state can lag a tab switch. Scope owns buflisted; never close
      -- a hidden tab's buffer merely because it appeared in the last redraw.
      if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted then
        local pinned = line.is_pinned(buf)
        assert(type(pinned) == "boolean", "unknown pin state")
        if not pinned and not seen[buf] then
          buffers[#buffers + 1], seen[buf] = buf, true
        end
      end
    end
    return buffers
  end)
  if ok then return result end
  return nil, tostring(result)
end

function M.close_unpinned()
  local buffers, err = M.unpinned_buffers()
  if not buffers then
    vim.notify("Close unpinned cancelled: " .. err, vim.log.levels.WARN)
    return
  end
  local util = require("config.util")
  util.notify_bulk_result(util.delete_buffers_keep_windows(buffers))
end

return M
