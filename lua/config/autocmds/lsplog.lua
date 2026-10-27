-- lua/config/autocmds/lsplog.lua
--
-- LSP log rotation at startup.

-- ---------------------------------------------------------------------------
-- LSP-log janitor. lsp.log is never rotated by Neovim and collects every
-- server's stderr, so it grows without bound (135 MB seen). At startup,
-- past 20 MB, it is renamed to lsp.log.old — one previous generation kept,
-- which is the one :DiagnosticDump needs after a hang + restart. Runs at
-- require time, before any server opens the log. With another instance
-- running: on Windows the rename fails (skipped); on Unix it succeeds and
-- that instance keeps writing into lsp.log.old — nothing is lost.
-- ---------------------------------------------------------------------------
do
  local limit = require("config.settings").get("retention.log_max_bytes", 20 * 1024 * 1024)
  if limit == false then return end
  if type(limit) ~= "number" or limit <= 0 or limit ~= limit or limit == math.huge then
    vim.notify("retention.log_max_bytes must be a positive number or false", vim.log.levels.WARN)
    return
  end
  -- vim.lsp.log.get_filename() is the non-deprecated spelling of the
  -- old vim.lsp.get_log_path() (which 0.12 warns about and 0.13 removes).
  -- Required as the SUBMODULE: touching `vim.lsp` itself loads the whole
  -- LSP client at startup — even for `nvim` with no file, or a plain text
  -- file — just to stat one path. vim.lsp.log pulls in only
  -- vim.lsp.protocol, not the client.
  local log = require("vim.lsp.log").get_filename()
  local st = vim.uv.fs_stat(log)
  if st and st.size and st.size > limit then
    -- libuv's rename replaces an existing lsp.log.old (MoveFileEx with
    -- REPLACE_EXISTING on Windows), so no unlink first: if the rename then
    -- fails, the previous generation is still there.
    local ok = vim.uv.fs_rename(log, log .. ".old")
    if ok then
      -- Scheduled: notify plugins (nvim-notify etc.) aren't loaded yet
      -- this early in startup; scheduling lets the message render once
      -- the UI is up instead of vanishing into the pre-UI void.
      vim.schedule(function()
        vim.notify(
          ("Rotated LSP log (%.0f MB) → lsp.log.old"):format(st.size / 1024 / 1024),
          vim.log.levels.INFO
        )
      end)
    end
  end
end
