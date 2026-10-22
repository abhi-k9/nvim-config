describe("plain Scoper multi-selection", function()
  local UI, original_select, original_preference, original_has, original_ui

  before_each(function()
    local util = require("scoper.util")
    original_preference, original_has = util.prefer_fzf, util.has
    original_ui = package.loaded["scoper.ui"]
    util.prefer_fzf = function()
      return false
    end
    util.has = function()
      return false
    end
    package.loaded["scoper.ui"] = nil
    UI = require("scoper.ui")
    original_select = vim.ui.select
  end)

  after_each(function()
    vim.ui.select = original_select
    local util = require("scoper.util")
    util.prefer_fzf, util.has = original_preference, original_has
    package.loaded["scoper.ui"] = original_ui
  end)

  it("can select a real item named like the done sentinel", function()
    local result, calls = nil, 0
    vim.ui.select = function(choices, _, callback)
      calls = calls + 1
      if calls == 1 then
        assert.same({ "(done)", "(done)", "other" }, choices)
        callback(choices[2], 2)
      else
        assert.same({ "(done)", "other" }, choices)
        callback(choices[1], 1)
      end
    end
    UI.pick_many({ "(done)", "other" }, {}, function(picked)
      result = picked
    end)
    assert.same({ "(done)" }, result)
  end)

  it("still finishes without selection when the sentinel row is selected", function()
    local result
    vim.ui.select = function(choices, _, callback)
      callback(choices[1], 1)
    end
    UI.pick_many({ "(done)", "other" }, {}, function(picked)
      result = picked
    end)
    assert.same({}, result)
  end)

  it("preserves the documented partial-selection behavior on Escape", function()
    local result, calls = nil, 0
    vim.ui.select = function(choices, _, callback)
      calls = calls + 1
      if calls == 1 then
        callback(choices[3], 3)
      else
        callback(nil, nil)
      end
    end
    UI.pick_many({ "(done)", "other" }, {}, function(picked)
      result = picked
    end)
    assert.same({ "other" }, result)
  end)
end)
