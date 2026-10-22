describe("LSP buffer and capability lifecycle", function()
  local original_client, original_detach, original_inlay, original_linked, original_clients
  local original_notify, old_buf, buffers, clients, detached, hints, linked

  local function buffer(name, filetype, buftype)
    local buf = vim.api.nvim_create_buf(true, false)
    buffers[#buffers + 1] = buf
    if name then vim.api.nvim_buf_set_name(buf, name) end
    vim.bo[buf].filetype = filetype or "lua"
    vim.bo[buf].buftype = buftype or ""
    return buf
  end

  local function client(id, caps)
    local result = setmetatable({
      id = id,
      name = "audit-client-" .. id,
      server_capabilities = caps or {},
      capabilities = vim.lsp.protocol.make_client_capabilities(),
      registrations = {},
      attached_buffers = {},
      _get_language_id = function(_, buf)
        return vim.bo[buf].filetype
      end,
    }, { __index = require("vim.lsp.client") })
    clients[id] = result
    return result
  end

  local function attach(buf, c)
    c.attached_buffers[buf] = vim.bo[buf].filetype
    vim.api.nvim_exec_autocmds("LspAttach", {
      group = "user_lsp_attach",
      buffer = buf,
      data = { client_id = c.id },
    })
    vim.wait(20, function()
      return false
    end)
  end

  before_each(function()
    require("lazy.core.loader").load("nvim-lspconfig", { cmd = "spec" })
    -- The full-config harness normally enables real installed servers.
    -- These lifecycle cases supply controlled clients, so do not race
    -- asynchronous server attachment against the event under examination.
    for name in pairs(vim.lsp._enabled_configs) do
      vim.lsp.enable(name, false)
    end
    old_buf = vim.api.nvim_get_current_buf()
    buffers, clients, detached, hints, linked = {}, {}, {}, {}, {}
    original_client, original_detach = vim.lsp.get_client_by_id, vim.lsp.buf_detach_client
    original_inlay, original_linked = vim.lsp.inlay_hint.enable, vim.lsp.linked_editing_range.enable
    original_clients, original_notify = vim.lsp.get_clients, vim.notify
    vim.lsp.get_client_by_id = function(id)
      return clients[id] or original_client(id)
    end
    vim.lsp.buf_detach_client = function(buf, id)
      detached[#detached + 1] = { buf, id }
    end
    vim.lsp.inlay_hint.enable = function(on, filter)
      hints[#hints + 1] = { on, filter.bufnr }
    end
    vim.lsp.linked_editing_range.enable = function(on, filter)
      linked[#linked + 1] = { on, filter.client_id }
    end
    vim.notify = function() end
    dofile(vim.fn.getcwd() .. "/lua/plugins/lsp.lua")[3].config()
  end)

  after_each(function()
    vim.lsp.get_client_by_id, vim.lsp.buf_detach_client = original_client, original_detach
    vim.lsp.inlay_hint.enable, vim.lsp.linked_editing_range.enable = original_inlay, original_linked
    vim.lsp.get_clients, vim.notify = original_clients, original_notify
    if vim.api.nvim_buf_is_valid(old_buf) then vim.api.nvim_set_current_buf(old_buf) end
    for _, buf in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    end
    vim.g.user_inlay_hints_enabled, vim.g.user_linked_editing = nil, nil
  end)

  it("detaches servers from named virtual nofile buffers before enabling features", function()
    local buf = buffer("fugitive:///audit/example.cpp", "cpp", "nofile")
    attach(buf, client(9101, { inlayHintProvider = true }))
    assert.are.same({ { buf, 9101 } }, detached)
    assert.are.same({}, hints)
  end)

  it("also excludes named special buffers whose names resemble regular file paths", function()
    local buf = buffer(vim.fn.tempname() .. ".lua", "lua", "prompt")
    attach(buf, client(9102))
    assert.are.same({ { buf, 9102 } }, detached)
  end)

  it("keeps unnamed ordinary editing buffers eligible for language servers", function()
    local buf = buffer(nil, "lua")
    attach(buf, client(9103, { inlayHintProvider = true }))
    assert.are.same({}, detached)
    assert.are.same({ { true, buf } }, hints)
  end)

  it("checks dynamic capabilities against the attaching background buffer", function()
    local target = buffer(vim.fn.tempname() .. ".lua", "lua")
    local other = buffer(vim.fn.tempname() .. ".txt", "text")
    vim.api.nvim_set_current_buf(other)
    local c = client(9104)
    c:_register_dynamic({
      {
        id = "lua-hints",
        method = "textDocument/inlayHint",
        registerOptions = { documentSelector = { { language = "lua", scheme = "file" } } },
      },
    })
    assert.is_true(c:supports_method("textDocument/inlayHint", target))
    assert.is_false(c:supports_method("textDocument/inlayHint", other))
    attach(target, c)
    assert.are.same({ { true, target } }, hints)
  end)

  it(
    "retains highlights when a background buffer still has a dynamically capable client",
    function()
      local target = buffer(vim.fn.tempname() .. ".lua", "lua")
      local other = buffer(vim.fn.tempname() .. ".txt", "text")
      local leaving = client(9105, { documentHighlightProvider = true })
      attach(target, leaving)
      local remaining = client(9106)
      remaining.capabilities.textDocument.documentHighlight.dynamicRegistration = true
      remaining:_register_dynamic({
        {
          id = "lua-highlights",
          method = "textDocument/documentHighlight",
          registerOptions = { documentSelector = { { language = "lua" } } },
        },
      })
      remaining.attached_buffers[target] = "lua"
      vim.lsp.get_clients = function()
        return { remaining }
      end
      vim.api.nvim_set_current_buf(other)
      vim.api.nvim_exec_autocmds("LspDetach", {
        group = "user_lsp_highlight_detach_" .. target,
        buffer = target,
        data = { client_id = leaving.id },
      })
      assert.is_true(#vim.api.nvim_get_autocmds({ group = "user_lsp_highlight_" .. target }) > 0)
    end
  )

  it("applies linked-editing toggles to clients supported in their other buffers", function()
    local first = buffer(vim.fn.tempname() .. ".html", "html")
    local second = buffer(vim.fn.tempname() .. ".html", "html")
    local one = client(9107, { linkedEditingRangeProvider = true })
    attach(first, one)
    local two = client(9108)
    two.capabilities.textDocument.linkedEditingRange.dynamicRegistration = true
    two:_register_dynamic({
      {
        id = "other-html",
        method = "textDocument/linkedEditingRange",
        registerOptions = { documentSelector = { { pattern = vim.api.nvim_buf_get_name(second) } } },
      },
    })
    two.attached_buffers[second] = "html"
    vim.api.nvim_set_current_buf(first)
    vim.lsp.get_clients = function()
      return { one, two }
    end
    for _, key in ipairs(vim.api.nvim_buf_get_keymap(first, "n")) do
      if key.desc == "LSP: Toggle linked tag editing" then key.callback() end
    end
    assert.are.same({ { true, one.id }, { false, one.id }, { false, two.id } }, linked)
  end)
end)
