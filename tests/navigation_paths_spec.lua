describe("finder path clipboard action", function()
  local action, state, original_selected, original_picker, original_setreg, original_notify
  local root, old_cwd, registers, selected, picker

  before_each(function()
    require("lazy.core.loader").load("telescope.nvim", { cmd = "spec" })
    state = require("telescope.actions.state")
    action = require("plugins.finder")[1].opts().defaults.mappings.i["<C-y>"]
    original_selected, original_picker = state.get_selected_entry, state.get_current_picker
    original_setreg, original_notify = vim.fn.setreg, vim.notify
    old_cwd = vim.fn.getcwd()
    root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/picker/sub", "p")
    vim.fn.mkdir(root .. "/caller", "p")
    vim.fn.writefile({ "hello" }, root .. "/picker/sub/file.lua")
    vim.cmd.cd(root .. "/caller")
    registers, picker = {}, { cwd = root .. "/picker" }
    state.get_selected_entry = function()
      return selected
    end
    state.get_current_picker = function()
      return picker
    end
    vim.fn.setreg = function(register, value)
      registers[register] = value
    end
    vim.notify = function() end
  end)

  after_each(function()
    state.get_selected_entry, state.get_current_picker = original_selected, original_picker
    vim.fn.setreg, vim.notify = original_setreg, original_notify
    vim.cmd.cd(old_cwd)
    vim.fn.delete(root, "rf")
  end)

  it("copies a real Telescope file entry relative to its picker, not the caller", function()
    selected = require("telescope.make_entry").gen_from_file({ cwd = picker.cwd })("sub/file.lua")
    assert.equals("sub/file.lua", selected.filename)
    action(0)
    assert.equals(root .. "/picker/sub/file.lua", registers["+"])
    assert.equals(registers["+"], registers['"'])
  end)

  it("anchors entries that only provide a relative filename to the picker cwd", function()
    selected = { filename = "sub/file.lua" }
    action(0)
    assert.equals(root .. "/picker/sub/file.lua", registers["+"])
  end)

  it("does not stringify non-file picker values into invented paths", function()
    for _, entry in ipairs({
      { value = { symbol = "method" } },
      { value = "help-tag" },
      { filename = "[No Name]" },
    }) do
      selected = entry
      action(0)
      assert.is_nil(registers["+"])
    end
  end)

  it("preserves a URI instead of treating its scheme as a directory name", function()
    selected = { filename = "diffview://project/revision/file.lua" }
    action(0)
    assert.equals(selected.filename, registers["+"])
  end)
end)
