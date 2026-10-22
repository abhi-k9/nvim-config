describe("current-file search preserves literal names", function()
  local root, original_grug, original_notify, original_variable, opened, notes, buf, previous
  local callback
  for _, key in ipairs(require("plugins.search").keys) do
    if key[1] == "<leader>sf" then callback = key[2] end
  end

  before_each(function()
    previous = vim.api.nvim_get_current_buf()
    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    original_grug, original_notify = package.loaded["grug-far"], vim.notify
    original_variable = vim.env.NVIM_AUDIT_LITERAL_NAME
    opened, notes = nil, {}
    package.loaded["grug-far"] = {
      open = function(opts)
        opened = opts
      end,
    }
    vim.notify = function(message)
      notes[#notes + 1] = message
    end
  end)

  after_each(function()
    package.loaded["grug-far"], vim.notify = original_grug, original_notify
    vim.env.NVIM_AUDIT_LITERAL_NAME = original_variable
    if vim.api.nvim_buf_is_valid(previous) then vim.api.nvim_set_current_buf(previous) end
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    vim.fn.delete(root, "rf")
  end)

  it("refuses a literal variable-shaped filename instead of targeting its expansion", function()
    local literal, expanded = root .. "/$NVIM_AUDIT_LITERAL_NAME.lua", root .. "/other.lua"
    vim.fn.writefile({ "literal contents" }, literal)
    vim.fn.writefile({ "unrelated contents" }, expanded)
    vim.env.NVIM_AUDIT_LITERAL_NAME = "other"
    vim.api.nvim_buf_set_name(buf, literal)
    callback()
    assert.is_nil(opened)
    assert.is_truthy(table.concat(notes, "\n"):find("literal $NAME", 1, true))
    assert.are.same({ "literal contents" }, vim.fn.readfile(literal))
    assert.are.same({ "unrelated contents" }, vim.fn.readfile(expanded))
  end)

  it("also refuses currently unset names that may expand at deferred execution time", function()
    local literal = root .. "/$NVIM_AUDIT_LITERAL_NAME.lua"
    vim.fn.writefile({ "literal contents" }, literal)
    vim.env.NVIM_AUDIT_LITERAL_NAME = nil
    vim.api.nvim_buf_set_name(buf, literal)
    callback()
    assert.is_nil(opened)
  end)

  it("allows a dollar sign that cannot be expanded as a variable", function()
    local literal = root .. "/price$.lua"
    vim.fn.writefile({ "literal contents" }, literal)
    vim.api.nvim_buf_set_name(buf, literal)
    callback()
    assert.equals(literal, opened.prefills.paths)
  end)
end)
