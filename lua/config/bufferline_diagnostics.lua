-- Bufferline has no custom diagnostic-source hook. Replace only its getter,
-- delegating other providers, and leave Neovim's diagnostic APIs untouched.
local M = {}
local attachment
local levels = { "error", "warning", "info", "hint", "other" }
local insert_mode = { i = true, ic = true, ix = true, R = true, Rc = true, Rx = true }
local missing = {
  __index = function()
    return { count = 0 }
  end,
}

local function count_by_namespace(diagnostics)
  local buffers = {}
  for _, diagnostic in ipairs(diagnostics) do
    local groups = buffers[diagnostic.bufnr] or {}
    buffers[diagnostic.bufnr] = groups
    local summary = groups[diagnostic.namespace] or { count = 0, severity = 5, errors = {} }
    groups[diagnostic.namespace] = summary
    summary.count = summary.count + 1
    summary.severity = math.min(summary.severity, diagnostic.severity)
    local level = levels[diagnostic.severity] or "other"
    summary.errors[level] = (summary.errors[level] or 0) + 1
  end
  return buffers
end

function M.dispose()
  if not attachment then return end
  -- Restore only our own function; preserve a later independent override.
  if attachment.owner.get == attachment.get then attachment.owner.get = attachment.original end
  vim.api.nvim_del_augroup_by_id(attachment.group)
  attachment = nil
end

function M.setup()
  local owner = require("bufferline.diagnostics")
  if attachment and owner.get == attachment.get then return end
  M.dispose()
  local original = owner.get
  assert(type(original) == "function", "Unsupported Bufferline diagnostic getter")
  local counts, result
  local dirty = {}
  local last = setmetatable({}, missing)
  local group = vim.api.nvim_create_augroup("user_bufferline_diagnostic_cache", { clear = true })
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = group,
    callback = function(args)
      if counts then dirty[args.buf] = true end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(args)
      if counts then counts[args.buf] = nil end
      dirty[args.buf], result = nil, nil
    end,
  })

  local function get(opts)
    if opts.diagnostics ~= "nvim_lsp" then return original(opts) end
    local mode = vim.api.nvim_get_mode().mode
    if insert_mode[mode] and not vim.diagnostic.config().update_in_insert then return last end
    if not counts then counts = count_by_namespace(vim.diagnostic.get()) end
    for bufnr in pairs(dirty) do
      counts[bufnr] = count_by_namespace(vim.diagnostic.get(bufnr))[bufnr]
      result = nil
    end
    dirty = {}
    -- Enable/disable does not emit DiagnosticChanged. Check once per group,
    -- rather than once per diagnostic, so every supported filter stays live.
    for bufnr, groups in pairs(counts) do
      for namespace, summary in pairs(groups) do
        local enabled = vim.diagnostic.is_enabled({ bufnr = bufnr, ns_id = namespace })
        if summary.enabled ~= enabled then result = nil end
        summary.enabled = enabled
      end
    end
    if not result then
      result = setmetatable({}, missing)
      for bufnr, groups in pairs(counts) do
        local summary = { count = 0, errors = {} }
        local severity = 5
        for _, item in pairs(groups) do
          if item.enabled then
            summary.count = summary.count + item.count
            severity = math.min(severity, item.severity)
            for level, count in pairs(item.errors) do
              summary.errors[level] = (summary.errors[level] or 0) + count
            end
          end
        end
        if summary.count > 0 then
          summary.level = levels[severity]
          result[bufnr] = summary
        end
      end
    end
    last = result
    return result
  end

  attachment = { owner = owner, original = original, get = get, group = group }
  owner.get = get
end

return M
