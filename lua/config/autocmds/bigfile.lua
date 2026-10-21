-- lua/config/autocmds/bigfile.lua
--
-- Big-file mode: files over the threshold skip treesitter, folding, and
-- other per-buffer work.

local augroup = require("config.util").augroup

-- ---------------------------------------------------------------------------
-- Disable certain features for huge files to keep things snappy.
--
-- Threshold: vim.g.big_file_size in bytes (default 1 MB), read at each
-- file open, so it can be changed at runtime (`:let g:big_file_size =
-- 5000000`) or set in your own config before this loads.
--
-- BufReadPre fires BEFORE the buffer is read, so no syntax/treesitter is
-- attached yet — we can't "clear" syntax here, we have to prevent it from
-- attaching. We do that by setting a buffer-local marker (`b:big_file`)
-- that the rest of the config reads (treesitter.lua skips the buffer,
-- lsp.lua detaches its clients, folding.lua turns ufo off), and by
-- applying the per-buffer cheapeners on BufReadPost.
--
-- Load-order rule: these handlers are registered before lazy.nvim sources
-- filetype.lua, so on BufReadPost they run BEFORE filetype detection.
-- Anything that detection (FileType, the `syntaxset` handler) would undo
-- has to be deferred to a buffer-local FileType autocmd.
-- ---------------------------------------------------------------------------
vim.api.nvim_create_autocmd("BufReadPre", {
  group = augroup("big_file_mark"),
  callback = function(args)
    local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(args.buf))
    local limit = tonumber(vim.g.big_file_size) or 1024 * 1024
    if ok and stats and stats.size > limit then
      vim.b[args.buf].big_file = true
      -- Cache the size so the BufReadPost handler doesn't fs_stat again
      -- just to format the notification.
      vim.b[args.buf].big_file_bytes = stats.size
      -- Swap opt-out must happen HERE, not in the BufReadPost handler:
      -- Vim creates the swap file and copies the entire file into it
      -- when the buffer loads, so by BufReadPost a big file has
      -- already paid a full extra write. Pre-read is the only moment
      -- the opt-out actually prevents the work. The previous value is kept
      -- so a re-read below the limit can restore it.
      if vim.b[args.buf].big_file_swapfile == nil then
        vim.b[args.buf].big_file_swapfile = vim.bo[args.buf].swapfile
      end
      vim.bo[args.buf].swapfile = false
    elseif vim.b[args.buf].big_file then
      -- Re-read (:e!) after the file shrank under the limit: swap
      -- protection comes back (unless it was off before big-file mode).
      -- The other cheapeners stay until the buffer is reopened.
      if vim.b[args.buf].big_file_swapfile then vim.bo[args.buf].swapfile = true end
      vim.b[args.buf].big_file = nil
      vim.b[args.buf].big_file_bytes = nil
      vim.b[args.buf].big_file_swapfile = nil
    end
  end,
})

vim.api.nvim_create_autocmd("BufReadPost", {
  group = augroup("big_file_apply"),
  callback = function(args)
    if not vim.b[args.buf].big_file then return end
    -- Per-buffer cheapeners. These actually apply on this buffer only and
    -- won't ripple to other buffers like `syntax clear` did. (The swap
    -- opt-out lives in the BufReadPre handler above — it's only
    -- effective before the file is read.)
    vim.opt_local.foldmethod = "manual"
    vim.opt_local.spell = false
    -- Disable the regex syntax engine for THIS buffer once its filetype is
    -- known (see the load-order rule above). treesitter.lua doesn't attach
    -- big files, but Neovim's own ftplugins start it for lua, help, query
    -- and markdown; stop it once every FileType handler has run. Stopping
    -- it turns regex syntax back on, so clear 'syntax' again after.
    vim.api.nvim_create_autocmd("FileType", {
      buffer = args.buf,
      once = true,
      desc = "big_file: no regex syntax, no treesitter",
      callback = function(ev)
        vim.bo[ev.buf].syntax = ""
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(ev.buf) then
            vim.treesitter.stop(ev.buf)
            vim.bo[ev.buf].syntax = ""
          end
        end)
      end,
    })
    -- LSP clients are detached in lsp.lua's LspAttach guard and ufo skips
    -- the buffer; the notification explains the missing features.
    vim.notify(
      ("big_file mode: %s (%.1f MB)"):format(
        vim.fn.fnamemodify(vim.api.nvim_buf_get_name(args.buf), ":t"),
        (vim.b[args.buf].big_file_bytes or 0) / 1048576
      ),
      vim.log.levels.INFO
    )
  end,
})
