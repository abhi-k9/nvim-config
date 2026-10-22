local punctuation = { ",", ".", "!", "?", ";", ":" }

local function insert_map(buf, key)
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, "i")) do
    if mapping.lhs == key then return mapping end
  end
end

describe("prose undo mappings follow filetype changes", function()
  local buf
  before_each(function()
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
  end)
  after_each(function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("removes prose punctuation undo breaks when switching to code", function()
    vim.bo[buf].filetype = "markdown"
    for _, ch in ipairs(punctuation) do
      assert.are.equal(ch .. "<C-G>u", insert_map(buf, ch).rhs)
    end
    vim.bo[buf].filetype = "lua"
    for _, ch in ipairs(punctuation) do
      assert.is_nil(insert_map(buf, ch))
    end
  end)

  it("keeps punctuation breaks when switching between prose types", function()
    vim.bo[buf].filetype = "text"
    vim.bo[buf].filetype = "gitcommit"
    assert.are.equal(",<C-G>u", insert_map(buf, ",").rhs)
  end)

  it("preserves a buffer-local mapping installed after the prose mapping", function()
    vim.bo[buf].filetype = "markdown"
    vim.keymap.set("i", ",", ",custom", { buffer = buf, desc = "custom punctuation" })
    vim.bo[buf].filetype = "lua"
    assert.are.equal(",custom", insert_map(buf, ",").rhs)
  end)
end)
