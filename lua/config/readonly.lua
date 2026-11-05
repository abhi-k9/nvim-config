-- Small on-demand reader shared by config reports and existing Markdown guides.
local M = {}

function M.open(lines, opts)
  opts = opts or {}
  if #lines == 0 then lines = { "" } end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = "wipe"
  -- References do not need FileType-driven LSP/parser/tool provisioning.
  vim.api.nvim_buf_call(buf, function()
    vim.api.nvim_cmd({
      cmd = "setlocal",
      args = { "filetype=" .. (opts.filetype or "config-info") },
      mods = { noautocmd = true },
    }, {})
  end)
  vim.bo[buf].modifiable = false
  local width = math.max(1, math.min(100, math.floor(vim.o.columns * 0.9)))
  local height = math.max(1, math.min(#lines, math.floor((vim.o.lines - vim.o.cmdheight) * 0.8)))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height - 2) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)),
    style = "minimal",
    border = "rounded",
    title = " " .. (opts.title or "Configuration") .. " ",
    title_pos = "center",
    footer = opts.footer or " q / Esc: close | /: search ",
    footer_pos = "right",
  })
  vim.wo[win].wrap = true
  local function close()
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      vim.api.nvim_win_close(win, true)
    end
  end
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set(
      "n",
      key,
      close,
      { buffer = buf, nowait = true, silent = true, desc = "Close this reference" }
    )
  end
  for key, action in pairs(opts.actions or {}) do
    vim.keymap.set("n", key, function()
      close()
      action.run()
    end, { buffer = buf, desc = action.desc })
  end
  if opts.line then vim.api.nvim_win_set_cursor(win, { math.min(opts.line, #lines), 0 }) end
  return { buf = buf, win = win, close = close }
end

return M
