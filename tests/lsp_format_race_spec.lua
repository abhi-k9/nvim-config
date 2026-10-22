describe("asynchronous LSP formatting", function()
  local original_clients, original_client, original_notify, old_buf, buf, response
  local client, cancelled, messages, request_count, other_buffers

  before_each(function()
    require("lazy.core.loader").load("mason-lspconfig.nvim", { cmd = "spec" })
    for name in pairs(vim.lsp._enabled_configs) do
      vim.lsp.enable(name, false)
    end
    old_buf = vim.api.nvim_get_current_buf()
    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. ".lua")
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'local value = "😀";local x=1' })
    response = nil
    cancelled, messages, other_buffers, request_count = {}, {}, {}, 0
    client = {
      id = 9201,
      name = "delayed-formatter",
      offset_encoding = "utf-16",
      handlers = {},
      attached_buffers = { [buf] = true },
      server_capabilities = { documentFormattingProvider = true },
      supports_method = function(_, method)
        return method == "textDocument/formatting"
      end,
      request = function(_, method, params, callback, target)
        assert.are.equal("textDocument/formatting", method)
        assert.are.equal(vim.uri_from_bufnr(buf), params.textDocument.uri)
        assert.are.equal(buf, target)
        response = function(err, edits)
          callback(
            err,
            edits
              or (
                not err
                  and {
                    -- The character after the emoji is UTF-16 offset 18, byte 20.
                    {
                      range = {
                        start = { line = 0, character = 18 },
                        ["end"] = { line = 0, character = 28 },
                      },
                      newText = "; local x = 1",
                    },
                  }
                or nil
              ),
            { client_id = 9201, bufnr = target, method = method }
          )
        end
        request_count = request_count + 1
        return true, request_count
      end,
      cancel_request = function(_, id)
        cancelled[#cancelled + 1] = id
        return true
      end,
    }
    original_clients, original_client, original_notify =
      vim.lsp.get_clients, vim.lsp.get_client_by_id, vim.notify
    vim.lsp.get_clients = function(filter)
      if not filter or not filter.method or filter.method == "textDocument/formatting" then
        return { client }
      end
      return {}
    end
    vim.lsp.get_client_by_id = function(id)
      return id == client.id and client or original_client(id)
    end
    vim.notify = function(message)
      messages[#messages + 1] = message
    end
    dofile(vim.fn.getcwd() .. "/lua/plugins/lsp.lua")[3].config()
    vim.api.nvim_exec_autocmds("LspAttach", {
      group = "user_lsp_attach",
      buffer = buf,
      data = { client_id = client.id },
    })
    for _, key in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
      if key.desc == "LSP: Format" then key.callback() end
    end
    assert.is_function(response)
  end)

  after_each(function()
    vim.lsp.get_clients, vim.lsp.get_client_by_id, vim.notify =
      original_clients, original_client, original_notify
    if vim.api.nvim_buf_is_valid(old_buf) then vim.api.nvim_set_current_buf(old_buf) end
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    for _, other in ipairs(other_buffers) do
      if vim.api.nvim_buf_is_valid(other) then vim.api.nvim_buf_delete(other, { force = true }) end
    end
  end)

  it("applies a delayed formatter response using its negotiated UTF-16 offsets", function()
    response()
    assert.are.same(
      { 'local value = "😀"; local x = 1' },
      vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    )
  end)

  it("preserves edits made while the formatter response is outstanding", function()
    local changed = { 'local value = "😀";local important=2' }
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, changed)
    response()
    assert.are.same(changed, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end)

  it("ignores a late response after its buffer was deleted", function()
    vim.api.nvim_buf_delete(buf, { force = true })
    assert.are.same({ 1 }, cancelled)
    assert.has_no.errors(response)
    assert.is_false(vim.api.nvim_buf_is_valid(buf))
  end)

  it("cancels superseded requests and ignores their responses", function()
    local stale = response
    require("config.lsp_format").format(buf)
    assert.are.same({ 1 }, cancelled)
    stale()
    assert.are.equal(
      'local value = "😀";local x=1',
      vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    )
    response()
    assert.are.equal(
      'local value = "😀"; local x = 1',
      vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    )
  end)

  it("cancels a request if the buffer is renamed before its response", function()
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. ".lua")
    assert.are.same({ 1 }, cancelled)
    response()
    assert.are.equal(
      'local value = "😀";local x=1',
      vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    )
  end)

  it("cancels a request when its server detaches", function()
    vim.api.nvim_exec_autocmds("LspDetach", { buffer = buf, data = { client_id = client.id } })
    assert.are.same({ 1 }, cancelled)
    response()
    assert.are.equal(
      'local value = "😀";local x=1',
      vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    )
  end)

  it("bounds a stalled request and ignores a response arriving after timeout", function()
    require("config.lsp_format").format(buf, { timeout_ms = 15 })
    assert.is_true(vim.wait(1000, function()
      return #cancelled == 2
    end, 5))
    assert.are.same({ 1, 2 }, cancelled)
    assert.are.equal("[LSP] Formatting timed out", messages[#messages])
    response()
    assert.are.equal(
      'local value = "😀";local x=1',
      vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    )
  end)

  it("reports server errors without applying text or leaving the request active", function()
    response({ code = -32603, message = "format failed" })
    assert.are.equal("[LSP] delayed-formatter: format failed", messages[#messages])
    response()
    assert.are.equal(
      'local value = "😀";local x=1',
      vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    )
  end)

  it("does not run a CLI formatter when no LSP formatter is attached", function()
    vim.lsp.get_clients = function()
      return {}
    end
    require("config.lsp_format").format(buf)
    assert.are.same({ 1 }, cancelled)
    assert.are.equal(
      "[LSP] Format request failed, no matching language servers.",
      messages[#messages]
    )
    assert.are.equal(
      'local value = "😀";local x=1',
      vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    )
  end)

  it("reports a request refused by a stopped server", function()
    client.request = function()
      return false
    end
    require("config.lsp_format").format(buf)
    assert.are.equal("[LSP] delayed-formatter: format request failed", messages[#messages])
    assert.are.same({}, vim.api.nvim_get_autocmds({ event = "BufFilePost", buffer = buf }))
  end)

  it("keeps later servers on the original buffer after focus changes", function()
    local reply
    local second = vim.tbl_extend("force", client, {
      id = 9202,
      request = function(_, _, params, callback, target)
        assert.are.equal(buf, target)
        assert.are.equal(vim.uri_from_bufnr(buf), params.textDocument.uri)
        assert.are.equal(6, params.options.tabSize)
        assert.is_true(params.options.insertSpaces)
        reply = callback
        return true, 99
      end,
    })
    vim.bo[buf].shiftwidth, vim.bo[buf].expandtab = 6, true
    vim.lsp.get_clients = function()
      return { client, second }
    end
    require("config.lsp_format").format(buf)
    local other = vim.api.nvim_create_buf(true, false)
    other_buffers[#other_buffers + 1] = other
    vim.bo[other].shiftwidth, vim.bo[other].expandtab = 3, false
    vim.api.nvim_set_current_buf(other)
    response()
    assert.is_function(reply)
    reply(nil, {})
    assert.are.equal(
      'local value = "😀"; local x = 1',
      vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    )
    assert.are.same({ "" }, vim.api.nvim_buf_get_lines(other, 0, -1, false))
  end)

  it("tracks the outstanding request after a synchronous in-process response", function()
    local immediate = vim.tbl_extend("force", client, {
      id = 9203,
      request = function(_, _, _, callback)
        callback(nil, vim.NIL)
        return true, 88
      end,
    })
    vim.lsp.get_clients = function()
      return { immediate, client }
    end
    require("config.lsp_format").format(buf)
    require("config.lsp_format").format(buf)
    assert.are.same({ 1, 2 }, cancelled)
    response(nil, {})
    assert.are.equal(
      'local value = "😀";local x=1',
      vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    )
  end)
end)
