describe("periodic tooling health reminder", function()
  local previous, stdpath, uis, notify, time, interval, rename
  local dir, now, messages, reminder
  local DAY = 24 * 60 * 60

  local function reload()
    package.loaded["config.health_reminder"] = nil
    reminder = require("config.health_reminder")
  end

  before_each(function()
    previous = package.loaded["config.health_reminder"]
    stdpath, uis, notify, time, rename =
      vim.fn.stdpath, vim.api.nvim_list_uis, vim.notify, os.time, vim.uv.fs_rename
    interval = vim.g.tooling_reminder_days
    dir, now, messages = vim.fn.tempname(), 1800000000, {}
    vim.fn.mkdir(dir, "p")
    vim.fn.stdpath = function(kind)
      return kind == "state" and dir or stdpath(kind)
    end
    vim.api.nvim_list_uis = function()
      return { {} }
    end
    vim.notify = function(message, level)
      messages[#messages + 1] = { text = message, level = level }
    end
    os.time = function()
      return now
    end
    vim.g.tooling_reminder_days = nil
    reload()
  end)

  after_each(function()
    vim.fn.stdpath, vim.api.nvim_list_uis, vim.notify, os.time, vim.uv.fs_rename =
      stdpath, uis, notify, time, rename
    vim.g.tooling_reminder_days = interval
    package.loaded["config.health_reminder"] = previous
    vim.fn.delete(dir, "rf")
  end)

  it("reminds immediately and persists the default 30-day interval across restarts", function()
    reminder.check()
    assert.equals(1, #messages)
    assert.equals(vim.log.levels.INFO, messages[1].level)
    assert.is_truthy(messages[1].text:find(":checkhealth config", 1, true))
    reload()
    now = now + 30 * DAY - 1
    reminder.check()
    assert.equals(1, #messages)
    now = now + 1
    reminder.check()
    assert.equals(2, #messages)
  end)

  it("honors a custom interval and a live interval change", function()
    vim.g.tooling_reminder_days = 7
    reminder.check()
    now = now + 6 * DAY
    reminder.check()
    assert.equals(1, #messages)
    vim.g.tooling_reminder_days = 6
    reminder.check()
    assert.equals(2, #messages)
  end)

  it("can be disabled without writing reminder state", function()
    vim.g.tooling_reminder_days = 0
    reminder.check()
    assert.same({}, messages)
    assert.is_nil(vim.uv.fs_stat(dir .. "/tooling-reminder"))
  end)

  it("does not notify or write state in headless runs", function()
    vim.api.nvim_list_uis = function()
      return {}
    end
    reminder.check()
    assert.same({}, messages)
    assert.is_nil(vim.uv.fs_stat(dir .. "/tooling-reminder"))
  end)

  it("recovers from corrupt and future timestamps", function()
    for _, value in ipairs({ "invalid", tostring(now + 365 * DAY), string.rep("9", 100) }) do
      vim.fn.writefile({ value }, dir .. "/tooling-reminder")
      reload()
      reminder.check()
    end
    assert.equals(3, #messages)
  end)

  it("does not claim a concurrent editor's active lease", function()
    local path = dir .. "/tooling-reminder.lock"
    vim.fn.writefile({ "" }, path)
    vim.uv.fs_utime(path, now, now)
    reminder.check()
    assert.same({}, messages)
    vim.fn.delete(path)
    reminder.check()
    assert.equals(1, #messages)
  end)

  it("recovers an interrupted lease on the next check", function()
    local path = dir .. "/tooling-reminder.lock"
    vim.fn.writefile({ "" }, path)
    vim.uv.fs_utime(path, now - 61, now - 61)
    reminder.check()
    assert.same({}, messages)
    assert.is_nil(vim.uv.fs_stat(path))
    reminder.check()
    assert.equals(1, #messages)
  end)

  it("still reminds once when saving fails and cleans up temporary files", function()
    vim.uv.fs_rename = function()
      return nil, "simulated failure"
    end
    reminder.check()
    reminder.check()
    assert.equals(1, #messages)
    assert.is_truthy(messages[1].text:find("could not be saved", 1, true))
    assert.same({}, vim.fn.readdir(dir))
  end)

  it("handles a directory in place of the timestamp without a startup error", function()
    vim.fn.mkdir(dir .. "/tooling-reminder")
    reminder.check()
    assert.equals(1, #messages)
    assert.is_truthy(messages[1].text:find("could not be saved", 1, true))
  end)

  it("registers once and checks a long-running editor when focus returns", function()
    reminder.setup()
    reminder.setup()
    assert.equals(2, #vim.api.nvim_get_autocmds({ group = "user_tooling_reminder" }))
    vim.api.nvim_exec_autocmds("FocusGained", { group = "user_tooling_reminder" })
    vim.wait(100, function()
      return #messages == 1
    end)
    now = now + 30 * DAY
    vim.api.nvim_exec_autocmds("FocusGained", { group = "user_tooling_reminder" })
    vim.wait(100, function()
      return #messages == 2
    end)
    assert.equals(2, #messages)
  end)
end)
