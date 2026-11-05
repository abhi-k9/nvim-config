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

describe("Scoper context hints", function()
  it("shows close hints and named mappings without a help-plugin dependency", function()
    local current = vim.api.nvim_get_current_win()
    require("scoper.ui").show_lines({ "Status" }, "Scoper status")
    local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
    local footer = vim.api.nvim_win_get_config(win).footer
    assert.is_truthy(vim.inspect(footer):find("q / Esc: close", 1, true))
    assert.is_false(vim.bo[buf].modifiable)
    local keys = {}
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      keys[mapping.lhs] = mapping
    end
    assert.equals("Close Scoper panel", keys.q.desc)
    keys.q.callback()
    assert.is_false(vim.api.nvim_win_is_valid(win))
    assert.equals(current, vim.api.nvim_get_current_win())
  end)

  it("names the fzf confirmation action and preserves selected values", function()
    local util = require("scoper.util")
    local preference, fzf = util.prefer_fzf, package.loaded["fzf-lua"]
    local options, result
    util.prefer_fzf = function()
      return true
    end
    package.loaded["fzf-lua"] = {
      fzf_exec = function(_, opts)
        options = opts
      end,
    }
    local ok, err = pcall(require("scoper.ui").pick_many, { "alpha" }, {}, function(picked)
      result = picked
    end)
    util.prefer_fzf, package.loaded["fzf-lua"] = preference, fzf
    assert.is_true(ok, err)
    assert.equals("Confirm selected items", options.actions.default.desc)
    assert.equals("toggle-all", options.keymap.fzf["ctrl-a"])
    options.actions.default.fn({ "alpha" })
    assert.same({ "alpha" }, result)
  end)
end)
