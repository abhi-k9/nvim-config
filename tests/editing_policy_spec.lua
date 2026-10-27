local settings = require("config.settings")

describe("editing policies", function()
  local buf, ambient
  before_each(function()
    settings.reset()
    ambient = vim.api.nvim_get_current_buf()
    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "keep trailing space  " })
    vim.bo[buf].filetype = "text"
  end)
  after_each(function()
    settings.reset()
    if vim.api.nvim_buf_is_valid(ambient) then vim.api.nvim_set_current_buf(ambient) end
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
  end)

  local function trim(bufnr)
    vim.api.nvim_exec_autocmds("BufWritePre", { group = "user_trim_whitespace", buffer = bufnr })
  end

  it("honors a disabled trim policy", function()
    settings.configure({ editing = { trim_whitespace = false } })
    trim(buf)
    assert.are.same({ "keep trailing space  " }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)

  it("evaluates the predicate with the written buffer and preserves ambient content", function()
    local called
    settings.configure({
      editing = {
        trim_whitespace = function(written)
          called = written
          return true
        end,
      },
    })
    local before = vim.api.nvim_buf_get_lines(ambient, 0, -1, false)
    trim(buf)
    assert.are.equal(buf, called)
    assert.are.same({ "keep trailing space" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    assert.are.same(before, vim.api.nvim_buf_get_lines(ambient, 0, -1, false))
    assert.are.equal(ambient, vim.api.nvim_get_current_buf())
  end)

  it("supports custom exceptions and an empty exception list", function()
    settings.configure({ editing = { trim_skip_filetypes = { "text" } } })
    trim(buf)
    assert.are.same({ "keep trailing space  " }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    settings.configure({ editing = { trim_skip_filetypes = {} } })
    trim(buf)
    assert.are.same({ "keep trailing space" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)

  it("keeps EditorConfig and buffer safety guards above the trim policy", function()
    settings.configure({ editing = { trim_skip_filetypes = {} } })
    vim.b[buf].editorconfig = { trim_trailing_whitespace = false }
    trim(buf)
    vim.b[buf].editorconfig = nil
    vim.bo[buf].readonly = true
    trim(buf)
    vim.bo[buf].readonly = false
    vim.bo[buf].binary = true
    trim(buf)
    vim.bo[buf].binary = false
    vim.b[buf].big_file = true
    trim(buf)
    vim.b[buf].big_file = nil
    vim.bo[buf].filetype = "diff"
    trim(buf)
    assert.are.same({ "keep trailing space  " }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)

  it("leaves comment continuation to the filetype when requested", function()
    settings.configure({ editing = { continue_comments = true } })
    vim.bo[buf].formatoptions = "croq"
    vim.api.nvim_exec_autocmds("FileType", { group = "user_formatoptions", buffer = buf })
    assert.are.equal("croq", vim.bo[buf].formatoptions)
    settings.configure({ editing = { continue_comments = false } })
    vim.api.nvim_exec_autocmds("FileType", { group = "user_formatoptions", buffer = buf })
    assert.are.equal("q", vim.bo[buf].formatoptions)
  end)

  it("removes only owned prose maps when the policy changes", function()
    vim.api.nvim_set_current_buf(buf)
    settings.configure({
      editing = { prose_undo = { filetypes = { "text" }, chars = { ",", "!" } } },
    })
    vim.api.nvim_exec_autocmds("FileType", { group = "user_undo_break", buffer = buf })
    assert.are.equal("!<c-g>u", vim.fn.maparg("!", "i", false, true).rhs:lower())
    vim.keymap.set("i", ",", "custom", { buffer = buf, desc = "user punctuation" })
    settings.configure({ editing = { prose_undo = { enabled = false } } })
    vim.api.nvim_exec_autocmds("FileType", { group = "user_undo_break", buffer = buf })
    assert.are.equal("", vim.fn.maparg("!", "i"))
    assert.are.equal("custom", vim.fn.maparg(",", "i"))
  end)
end)
