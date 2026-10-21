-- plugin/scoper.lua
--
-- User-command registration. This file runs once at startup (Neovim sources
-- everything under plugin/ automatically). We keep it small: just glue from
-- :ScoperFoo to require("scoper").foo(...). The heavy modules are still
-- lazy-required from inside scoper/init.lua.

if vim.g.loaded_scoper == 1 then return end
vim.g.loaded_scoper = 1

local function cmd(name, fn, opts)
  vim.api.nvim_create_user_command(name, fn, opts or {})
end

-- Helper for the "zero arguments OR whitespace-separated list" dispatcher
-- pattern used by :ScoperAdd / :ScoperRemove / :ScoperDelete. Lives in
-- scoper.util so it's importable for tests (a local function in this
-- plugin file would be invisible to require).
local split_args = require("scoper.util").split_args

-- The candidates that start with the word being completed. Neovim doesn't
-- filter what a Lua completion function returns.
local function starting_with(lead, list)
  return vim.tbl_filter(function(s)
    return vim.startswith(s, lead)
  end, list)
end

-- ---------------------------------------------------------------------------
-- Scope membership
-- ---------------------------------------------------------------------------
cmd("ScoperAdd", function(args)
  require("scoper").add(split_args(args.args))
end, { nargs = "*", complete = "dir", desc = "Add one or more directories to active scope" })

cmd("ScoperRemove", function(args)
  require("scoper").remove(split_args(args.args))
end, {
  nargs = "*",
  -- Complete from the scope's own entries (escaped like dir completion,
  -- which is also how the word being completed arrives), not from the
  -- filesystem: only those can be removed.
  complete = function(lead)
    local scope = require("scoper.state").active_scope()
    local escaped = vim.tbl_map(function(p)
      return (p:gsub(" ", "\\ "))
    end, scope and scope.include or {})
    return starting_with(lead, escaped)
  end,
  desc = "Remove one or more directories from active scope",
})

cmd("ScoperExclude", function(args)
  local s = require("scoper")
  if args.args == "" then
    s.exclude()
  else
    s.exclude({ args.args }) -- excludes are glob patterns, not split
  end
end, { nargs = "*", desc = "Add an exclude glob to active scope" })

cmd("ScoperRemoveExclude", function(args)
  local s = require("scoper")
  if args.args == "" then
    s.remove_exclude()
  else
    s.remove_exclude({ args.args }) -- symmetric with :ScoperExclude: the
    -- whole arg string is ONE glob, not split
  end
end, {
  nargs = "*",
  complete = function(lead)
    local scope = require("scoper.state").active_scope()
    return starting_with(lead, scope and scope.exclude or {})
  end,
  desc = "Remove an exclude glob from active scope (no arg → picker)",
})

cmd("ScoperClear", function()
  require("scoper").clear()
end, { desc = "Empty the active scope (keep excludes)" })

cmd("ScoperShow", function()
  require("scoper").show()
end, { desc = "Show active scope's includes and excludes" })

-- ---------------------------------------------------------------------------
-- Scope management
-- ---------------------------------------------------------------------------
cmd("ScoperNew", function(args)
  require("scoper").new(args.args ~= "" and args.args or nil)
end, { nargs = "?", desc = "Create a new scope and switch to it" })

cmd("ScoperUse", function(args)
  require("scoper").use(args.args ~= "" and args.args or nil)
end, {
  nargs = "?",
  complete = function(lead)
    return starting_with(lead, require("scoper.state").scope_names())
  end,
  desc = "Switch to a scope (no arg → picker)",
})

cmd("ScoperDelete", function(args)
  require("scoper").delete(split_args(args.args))
end, {
  nargs = "*",
  complete = function(lead)
    return starting_with(lead, require("scoper.state").scope_names())
  end,
  desc = "Delete one or more scopes",
})

cmd("ScoperScopes", function()
  require("scoper").scopes()
end, { desc = "List all scopes for this project" })

-- ---------------------------------------------------------------------------
-- Toggle / status
-- ---------------------------------------------------------------------------
cmd("ScoperToggle", function()
  require("scoper").toggle()
end, { desc = "Toggle scoping on/off" })

cmd("ScoperStatus", function()
  require("scoper").status()
end, { desc = "Print current scope status" })

-- ---------------------------------------------------------------------------
-- Scope-aware pickers
-- ---------------------------------------------------------------------------
cmd("ScoperFind", function()
  require("scoper").find()
end, { desc = "Find files within active scope" })

cmd("ScoperGrep", function(args)
  require("scoper").grep(args.args ~= "" and args.args or nil)
end, { nargs = "*", desc = "Live-grep within active scope" })

cmd("ScoperReplace", function()
  require("scoper").replace()
end, { desc = "Open grug-far scoped to active scope" })

cmd("ScoperTogglePicker", function()
  require("scoper").toggle_picker()
end, { desc = "Switch picker backend (fzf-lua ↔ telescope)" })

-- ---------------------------------------------------------------------------
-- LSP integration
-- ---------------------------------------------------------------------------
cmd("ScoperLspReload", function()
  require("scoper").lsp_reload()
end, { desc = "Reconfigure clangd for current scope and restart" })
