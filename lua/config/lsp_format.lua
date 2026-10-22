-- LSP-only asynchronous formatting. Native async formatting applies edits to
-- whatever text is present when a response arrives, even after more typing.
local M = {}
local pending = {}
local method = "textDocument/formatting"

function M.format(buf, opts)
  opts = opts or {}
  buf = buf or vim.api.nvim_get_current_buf()
  if pending[buf] then pending[buf].cancel() end
  if not vim.api.nvim_buf_is_loaded(buf) then return end
  local clients = vim.lsp.get_clients({ bufnr = buf, method = method })
  if #clients == 0 then
    vim.notify("[LSP] Format request failed, no matching language servers.")
    return
  end

  local state = { tick = vim.api.nvim_buf_get_changedtick(buf), uri = vim.uri_from_bufnr(buf) }
  pending[buf] = state
  local function finish(message)
    if pending[buf] ~= state then return end
    -- Invalidate first: cancel_request may synchronously deliver a response.
    pending[buf] = nil
    if state.timer and not state.timer:is_closing() then
      state.timer:stop()
      state.timer:close()
    end
    if state.autocmd then pcall(vim.api.nvim_del_autocmd, state.autocmd) end
    if state.client and state.request_id then
      pcall(state.client.cancel_request, state.client, state.request_id)
    end
    if message then vim.notify("[LSP] " .. message, vim.log.levels.WARN) end
  end
  state.cancel = finish
  state.autocmd = vim.api.nvim_create_autocmd(
    { "BufUnload", "BufWipeout", "BufFilePost", "LspDetach" },
    {
      buffer = buf,
      callback = function(ev)
        if ev.event ~= "LspDetach" or (state.client and ev.data.client_id == state.client.id) then
          finish()
        end
      end,
    }
  )
  state.timer = vim.defer_fn(function()
    finish("Formatting timed out")
  end, opts.timeout_ms or 5000)

  local function unchanged()
    return vim.api.nvim_buf_is_loaded(buf)
      and vim.uri_from_bufnr(buf) == state.uri
      and vim.api.nvim_buf_get_changedtick(buf) == state.tick
  end
  local function next_client(index)
    if pending[buf] ~= state then return end
    if not unchanged() then return finish("Formatting discarded: buffer changed") end
    local client = clients[index]
    if not client then return finish() end
    if not client.attached_buffers[buf] or not client:supports_method(method, buf) then
      return next_client(index + 1)
    end
    -- Build parameters for the target buffer again for each server. The user
    -- can switch buffers while an earlier server's request is outstanding.
    local params = {
      textDocument = { uri = state.uri },
      options = {
        tabSize = vim.lsp.util.get_effective_tabstop(buf),
        insertSpaces = vim.bo[buf].expandtab,
      },
    }
    state.client, state.request_id = client, nil
    local responded = false
    local ok, id = client:request(method, params, function(err, edits)
      responded = true
      if pending[buf] ~= state then return end
      state.client, state.request_id = nil, nil
      if not unchanged() then return finish("Formatting discarded: buffer changed") end
      if err then return finish(client.name .. ": " .. (err.message or tostring(err))) end
      if edits and edits ~= vim.NIL then
        local applied, apply_err =
          pcall(vim.lsp.util.apply_text_edits, edits, buf, client.offset_encoding)
        if not applied then return finish(client.name .. ": " .. tostring(apply_err)) end
      end
      if pending[buf] ~= state then return end
      state.tick = vim.api.nvim_buf_get_changedtick(buf)
      next_client(index + 1)
    end, buf)
    -- In-process servers can respond before request() returns; do not
    -- overwrite the next server's pending request in that case.
    if not responded and pending[buf] == state then
      if not ok then return finish(client.name .. ": format request failed") end
      state.request_id = id
    end
  end
  next_client(1)
end

return M
