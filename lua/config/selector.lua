-- One owner for vim.ui.select. Keep the previous provider available when the
-- optional picker or executable is unavailable; never replay a delivered choice.
local M = {}
local router, previous, select_fzf

local function available()
  return vim.fn.executable("fzf") == 1
end

local function menu_options(ui_opts, items)
  local preview = ui_opts.kind == "codeaction" or ui_opts.preview_item ~= nil
  return {
    no_resume = true,
    winopts = {
      border = "rounded",
      width = preview and 0.75 or 0.6,
      height = preview and 0.6 or math.min(0.5, (#items + 4) / math.max(vim.o.lines, 1)),
    },
  }
end

function M.setup(provider)
  provider = provider == nil and "fzf" or provider
  if provider == "telescope" then provider = "fzf" end
  if provider ~= "fzf" then
    if provider ~= false and provider ~= "native" then
      vim.notify(
        "Unknown selector.provider; keeping the previous selection UI",
        vim.log.levels.WARN
      )
    end
    return
  end
  -- Repeated setup must neither wrap itself nor take over a later provider.
  if router then return end
  previous = vim.ui.select
  router = function(items, opts, on_choice)
    opts = opts or {}
    local delivered = false
    local function once(item, index)
      if delivered then return end
      delivered = true
      -- Providers may coerce false items to nil; the index identifies the original.
      if index ~= nil then item = items[index] end
      return on_choice(item, index)
    end
    if #items == 0 then
      once(nil, nil)
      return
    end
    if not available() then return previous(items, opts, once) end
    if not select_fzf then
      -- fzf-lua remembers the function it replaces for deregistration. Give it
      -- the fallback, not this dispatcher, so it cannot capture a recursive hook.
      local owner = vim.ui.select
      vim.ui.select = previous
      local ok, err = pcall(function()
        require("fzf-lua").register_ui_select(menu_options, true)
        if vim.ui.select ~= previous then select_fzf = vim.ui.select end
      end)
      vim.ui.select = owner
      if not ok then
        vim.notify("fzf selector unavailable: " .. tostring(err), vim.log.levels.WARN)
      end
      if not select_fzf then return previous(items, opts, once) end
    end
    local ok, err = pcall(select_fzf, items, opts, once)
    if not ok then
      if delivered then error(err) end
      vim.notify("fzf selector failed: " .. tostring(err), vim.log.levels.WARN)
      return previous(items, opts, once)
    end
  end
  vim.ui.select = router
end

return M
