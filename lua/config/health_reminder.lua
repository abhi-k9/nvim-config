-- A periodic invitation to review tooling, not an automatic all-clear.
local M = {}
local shown, checking = nil, false
local DAY = 24 * 60 * 60

local function read_stamp(path)
  local stat = vim.uv.fs_stat(path)
  if not stat or stat.type ~= "file" or stat.size > 64 then return nil end
  local file = io.open(path, "r")
  if not file then return nil end
  local content = file:read(64)
  file:close()
  return tonumber(content)
end

local function save_stamp(path, now)
  local temp = path .. ".tmp-" .. vim.fn.getpid() .. "-" .. vim.uv.hrtime()
  local fd = vim.uv.fs_open(temp, "wx", 384)
  if not fd then return false end
  local value = tostring(now) .. "\n"
  local written = vim.uv.fs_write(fd, value, 0)
  vim.uv.fs_close(fd)
  local ok = written == #value and vim.uv.fs_rename(temp, path)
  if not ok then vim.uv.fs_unlink(temp) end
  return not not ok
end

function M.check()
  if checking or #vim.api.nvim_list_uis() == 0 then return end
  local days = vim.g.tooling_reminder_days
  if days == false or days == 0 then return end
  if type(days) ~= "number" or days <= 0 or days ~= days or days == math.huge then days = 30 end
  local now, interval = os.time(), days * DAY
  if shown and now >= shown and now - shown < interval then return end
  local dir = vim.fn.stdpath("state")
  local path = dir .. "/tooling-reminder"
  local last = read_stamp(path)
  if last and last >= 0 and last <= now and now - last < interval then
    shown = last
    return
  end

  -- Serialize simultaneous editor starts. A stale lease is cleared after a
  -- minute; the next focus/start retries, including after an interrupted write.
  local made = pcall(vim.fn.mkdir, dir, "p")
  local lock = path .. ".lock"
  local fd = made and vim.uv.fs_open(lock, "wx", 384)
  if not fd then
    local stat = vim.uv.fs_lstat(lock)
    if stat and stat.type == "file" then
      if now - stat.mtime.sec > 60 then vim.uv.fs_unlink(lock) end
      return
    end
  end
  checking = true
  local ok, err = pcall(function()
    -- Another process may have sent the reminder while we acquired the lease.
    last = read_stamp(path)
    if last and last >= 0 and last <= now and now - last < interval then
      shown = last
      return
    end
    local saved = fd and save_stamp(path, now)
    shown = now
    local message = "Tooling health review due: run :checkhealth config to review missing tools, "
      .. "skipped integrations, and version warnings."
    if not saved then
      message = message .. " Reminder timing could not be saved to " .. dir .. "."
    end
    vim.notify(message, vim.log.levels.INFO, { title = "Tooling health reminder" })
  end)
  if fd then
    vim.uv.fs_close(fd)
    vim.uv.fs_unlink(lock)
  end
  checking = false
  if not ok then error(err) end
end

function M.setup()
  vim.api.nvim_create_autocmd({ "VimEnter", "FocusGained" }, {
    group = vim.api.nvim_create_augroup("user_tooling_reminder", { clear = true }),
    callback = function()
      vim.schedule(M.check)
    end,
    desc = "Periodic reminder to review optional tool health",
  })
  if vim.v.vim_did_enter == 1 then vim.schedule(M.check) end
end

return M
