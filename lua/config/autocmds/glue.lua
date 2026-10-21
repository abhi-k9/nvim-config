-- lua/config/autocmds/glue.lua
--
-- Small plugin glue: filetype after session restore, LuaSnip session
-- cleanup.

local augroup = require("config.util").augroup

-- ---------------------------------------------------------------------------
-- Re-run filetype detection on session-restored buffers. Restored buffers
-- normally get `filetype` back through sessionoptions' `localoptions`;
-- this native SessionLoadPost handler (not a User event) is the fallback
-- for any buffer still without one. (The treesitter re-attach for
-- restored buffers lives with its FileType handler in plugins/treesitter.lua.)
-- Deferred so the first frame of the restored layout paints first.
-- ---------------------------------------------------------------------------
vim.api.nvim_create_autocmd("SessionLoadPost", {
  group = augroup("filetype_session_restore"),
  callback = function()
    vim.schedule(function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if
          vim.api.nvim_buf_is_valid(buf)
          and vim.api.nvim_buf_is_loaded(buf)
          and vim.bo[buf].filetype == ""
        then
          vim.api.nvim_buf_call(buf, function()
            vim.cmd("filetype detect")
          end)
        end
      end
    end)
  end,
})

-- ---------------------------------------------------------------------------
-- Unlink a lingering LuaSnip session when you leave it.
-- ---------------------------------------------------------------------------
-- Backstop for the same problem region_check_events handles in completion.lua:
-- LuaSnip can keep a snippet "active" (jumpable) after you've stepped out of
-- it. Because blink's default <Tab> is { 'snippet_forward', 'fallback' }, a
-- still-active session makes <Tab> jump back into the old snippet (frequently
-- a few lines UP) instead of indenting. This fires when you leave insert mode
-- (i -> n) or exit select mode (s -> n) without an active jump, and clears the
-- stale session so the next <Tab> indents normally. (LuaSnip's documented
-- snippet for this exact issue.) package.loaded, not require(): a mode
-- change must never be what loads LuaSnip.
vim.api.nvim_create_autocmd("ModeChanged", {
  group = augroup("luasnip_unlink_on_leave"),
  pattern = { "s:n", "i:*" },
  callback = function()
    local ls = package.loaded.luasnip
    if
      ls
      and ls.session.current_nodes[vim.api.nvim_get_current_buf()]
      and not ls.session.jump_active
    then
      ls.unlink_current()
    end
  end,
})
