describe("context keymap help", function()
  local spec, loaded, preload, windows, bufnr, current, original_buf, buffers

  local function mapping(lhs)
    for _, key in ipairs(spec.keys) do
      if key[1] == lhs then return key end
    end
    error("Missing context-help mapping: " .. lhs)
  end

  before_each(function()
    spec = dofile("lua/plugins/which-key.lua")
    loaded, preload = package.loaded["which-key"], package.preload["which-key"]
    current, windows = vim.api.nvim_get_current_win(), {}
    original_buf, buffers = vim.api.nvim_get_current_buf(), {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      buffers[buf] = true
    end
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      windows[win] = true
    end
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
  end)

  after_each(function()
    package.loaded["which-key"], package.preload["which-key"] = loaded, preload
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if not windows[win] then pcall(vim.api.nvim_win_close, win, true) end
    end
    if vim.api.nvim_win_is_valid(current) then
      vim.api.nvim_set_current_win(current)
      if vim.api.nvim_buf_is_valid(original_buf) then
        vim.api.nvim_win_set_buf(current, original_buf)
      end
    end
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if not buffers[buf] and (buf == bufnr or vim.bo[buf].buftype == "help") then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
    bufnr = nil
  end)

  it("shows current buffer mappings from both normal-mode entry points", function()
    local calls = {}
    package.loaded["which-key"] = {
      show = function(opts)
        calls[#calls + 1] = opts
      end,
    }
    vim.keymap.set("n", "zx", function() end, { buffer = bufnr, desc = "Local fixture action" })
    local f1, leader = mapping("<F1>"), mapping("<leader>?")
    assert.equals("n", f1.mode)
    assert.equals("n", leader.mode)
    f1[2]()
    leader[2]()
    assert.same({ { global = false }, { global = false } }, calls)
  end)

  it("opens built-in help if which-key cannot be loaded", function()
    vim.keymap.set("n", "zx", function() end, { buffer = bufnr, desc = "Local fixture action" })
    package.loaded["which-key"] = nil
    package.preload["which-key"] = function()
      error("which-key unavailable")
    end
    mapping("<F1>")[2]()
    assert.equals("help", vim.bo.buftype)
    assert.is_truthy(vim.api.nvim_buf_get_name(0):match("help%.txt$"))
  end)

  it("opens built-in help instead of an empty keymap view", function()
    package.loaded["which-key"] = {
      show = function()
        error("Empty buffer must not open a keymap view")
      end,
    }
    assert.equals(0, #vim.api.nvim_buf_get_keymap(bufnr, "n"))
    mapping("<F1>")[2]()
    assert.equals("help", vim.bo.buftype)
    assert.is_truthy(vim.api.nvim_buf_get_name(0):match("help%.txt$"))
  end)

  it("lets native buffer-local F1 help override the normal-mode fallback", function()
    local native, fallback = 0, 0
    package.loaded["which-key"] = {
      show = function()
        fallback = fallback + 1
      end,
    }
    vim.keymap.set("n", "<F1>", function()
      native = native + 1
    end, { buffer = bufnr })
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<F1>", true, false, true), "xt", false)
    assert.equals(1, native)
    assert.equals(0, fallback)
    -- No global insert/terminal mapping consumes help or typed query text.
    for _, mode in ipairs({ "i", "t" }) do
      for _, key in ipairs(vim.api.nvim_get_keymap(mode)) do
        assert.is_not.equal("<F1>", key.lhs)
      end
    end
  end)

  it("maps Trouble aliases to its existing live help action", function()
    local trouble = dofile("lua/plugins/trouble.lua")
    assert.equals("help", trouble.opts.keys["<F1>"])
    assert.equals("help", trouble.opts.keys["g?"])
    local effective = require("trouble.config").get(trouble.opts)
    assert.equals("help", effective.keys["?"])
  end)
end)
