-- lua/plugins/folding.lua
--
-- nvim-ufo — drop-in upgrade for Vim's folding. Uses LSP and/or treesitter
-- to compute fold ranges, which gives you much smarter folds than the
-- built-in `foldmethod=indent` or `=syntax`. The fold UI is also nicer:
-- collapsed folds show their first line with a "↙ N" suffix (N hidden
-- lines).
--
-- foldcolumn, foldlevel and foldlevelstart are set globally in
-- `lua/config/options.lua` (they run before any plugin loads; 'foldenable'
-- keeps its default, on). We do NOT duplicate them in this file — having
-- one source of truth keeps "did I change this here or there?" questions
-- from arising.
--
-- ufo computes fold STRUCTURE (where folds are) fresh on every load; it does
-- not remember which folds you had open or closed. That STATE is persisted
-- separately, per file, by the `fold_persistence` autocmds in
-- `lua/config/autocmds/folds.lua` using native view files (:mkview / :loadview),
-- with `viewoptions = { "folds" }` set in options.lua. That mechanism is
-- intentionally decoupled from ufo (it never calls into it — it just restores
-- native fold state after ufo's async recompute settles), so nothing here
-- needs to change if fold persistence is tuned or turned off, and vice versa.

-- ---------------------------------------------------------------------------
-- Filetype overrides for ufo's provider selection. Module-level so it's
-- built once, not on every buffer open.
-- ---------------------------------------------------------------------------
local FT_PROVIDER = {
  -- stylua: ignore start
  vim    = "indent",
  python = { "indent" },
  git    = "",
  -- stylua: ignore end
}

-- Does this filetype have a treesitter `folds` query and an installed parser?
-- Without this check, ufo throws UfoFallbackException on buffers it can never
-- parse (e.g. :MasonLog, plain-text files), and the async promise goes
-- unhandled. We cache by LANGUAGE (not filetype) since different filetypes
-- can map to the same parser (tsx/typescriptreact → typescript) — caching
-- by ft would store two entries for one underlying lookup.
--
-- Only POSITIVE results are cached. A negative can be transient:
-- treesitter.lua installs parsers asynchronously in the background, so
-- on a fresh machine the first buffer of a language often opens BEFORE
-- its parser finishes compiling. Caching that `false` pinned the buffer
-- (and every later buffer of that language) to the indent provider for
-- the whole session even after the install completed. Re-probing on a
-- miss costs one pcall per buffer open for genuinely parserless
-- filetypes — negligible.
local has_ts_folds_cache = {}
local function has_ts_folds(bufnr, ft)
  -- get_lang() returns the registered language name for a filetype, or
  -- the filetype itself if no mapping was registered.
  local lang = vim.treesitter.language.get_lang(ft) or ft
  if has_ts_folds_cache[lang] then return true end
  -- On 0.12 get_parser() RETURNS nil for a missing parser instead of
  -- throwing, so the parser itself is tested; query.get() is pcall'd
  -- because it DOES throw when a folds.scm exists without its parser.
  local okp, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
  if not (okp and parser) then return false end
  local okq, query = pcall(vim.treesitter.query.get, lang, "folds")
  local result = okq and query ~= nil
  if result then has_ts_folds_cache[lang] = true end
  return result
end

return {
  "kevinhwang91/nvim-ufo",
  dependencies = { "kevinhwang91/promise-async" },
  event = { "BufReadPost", "BufNewFile" },
  keys = {
    -- stylua: ignore start
    { "zR", function() require("ufo").openAllFolds() end,  desc = "Open all folds" },
    { "zM", function() require("ufo").closeAllFolds() end, desc = "Close all folds" },
    -- stylua: ignore end
    -- stylua: ignore start
    { "zr", function() require("ufo").openFoldsExceptKinds() end, desc = "Open folds except certain kinds" },
    { "K",  function()
        -- Peek the folded text under the cursor. Otherwise LSP hover when a
        -- client offers it, else the built-in K ('keywordprg': :help in Vim
        -- script and help files, man pages, …) with its count.
        if require("ufo").peekFoldedLinesUnderCursor() then return end
        if next(vim.lsp.get_clients({ bufnr = 0, method = "textDocument/hover" })) then
          vim.lsp.buf.hover()
        else
          vim.cmd("normal! " .. (vim.v.count > 0 and vim.v.count or "") .. "K")
        end
      end, desc = "Peek fold / hover / keywordprg" },
    -- stylua: ignore end
  },
  opts = {
    open_fold_hl_timeout = 0, -- no animation on unfold

    -- Provider selector: ask LSP first, fall back to treesitter (or indent
    -- where treesitter has no fold query). For "special" buffers (terminal,
    -- quickfix, neo-tree, nofile, etc.) and big files
    -- (autocmds/bigfile.lua) return "" so ufo disables itself entirely on
    -- them.
    provider_selector = function(bufnr, filetype, buftype)
      if buftype ~= "" or vim.b[bufnr].big_file then return "" end
      if FT_PROVIDER[filetype] ~= nil then return FT_PROVIDER[filetype] end
      return has_ts_folds(bufnr, filetype) and { "lsp", "treesitter" } or { "lsp", "indent" }
    end,

    -- Custom fold-line text: the first line + a "↙ N" suffix (N = hidden
    -- lines).
    fold_virt_text_handler = function(virtText, lnum, endLnum, width, truncate)
      local newVirtText = {}
      local suffix = (" " .. require("config.icons").misc.fold .. " %d "):format(endLnum - lnum)
      local sufWidth = vim.fn.strdisplaywidth(suffix)
      local targetWidth = width - sufWidth
      local curWidth = 0
      for _, chunk in ipairs(virtText) do
        local chunkText = chunk[1]
        local chunkWidth = vim.fn.strdisplaywidth(chunkText)
        if targetWidth > curWidth + chunkWidth then
          table.insert(newVirtText, chunk)
        else
          chunkText = truncate(chunkText, targetWidth - curWidth)
          table.insert(newVirtText, { chunkText, chunk[2] })
          chunkWidth = vim.fn.strdisplaywidth(chunkText)
          if curWidth + chunkWidth < targetWidth then
            suffix = suffix .. (" "):rep(targetWidth - curWidth - chunkWidth)
          end
          break
        end
        curWidth = curWidth + chunkWidth
      end
      table.insert(newVirtText, { suffix, "MoreMsg" })
      return newVirtText
    end,
  },
}
