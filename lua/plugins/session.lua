-- lua/plugins/session.lua
--
-- auto-session — saves/restores your buffer list, window layout, and cwd
-- per directory. Open Neovim in a project and pick up exactly where you
-- left off. Pairs nicely with bufferline + telescope buffers.
--
-- Keymaps live under <leader>w (window+session). Save-session uses the
-- uppercase form (<leader>wS) so the lowercase <leader>ws can keep its
-- "horizontal split" meaning from keymaps.lua.
--
-- Load order: scope.nvim and bufferline (lua/plugins/ui.lua) load at
-- startup because this plugin restores the session in VimEnter and both
-- hook SessionLoadPost; the session picker loads telescope on demand.

-- Directories where auto-restoring a session on a bare `nvim` is more
-- annoying than helpful: home, Downloads, temp dirs and the filesystem
-- root.
--
-- auto-session compares these against getcwd() as plain strings (after
-- stripping trailing "/"), and getcwd() uses the platform's NATIVE
-- separator. So on Windows the entries need backslashes: forward-slash
-- entries such as "C:/Users/me/Downloads" never matched the cwd
-- "C:\Users\me\Downloads", and "/" can't match "C:\". Entries are expanded
-- and realpath-resolved up front: %TEMP% is often an 8.3 short name
-- (C:\Users\JOHNDO~1\...) and macOS $TMPDIR sits behind the /var ->
-- /private/var symlink, while getcwd() reports the long / resolved path.
local suppressed_dirs = {}
do
  local is_win = vim.fn.has("win32") == 1
  local function add(p)
    if not p or p == "" then return end
    p = vim.fn.expand(p)
    p = vim.uv.fs_realpath(p) or p
    local variants = { p }
    -- Both separator styles on Windows: getcwd() is backslashed normally
    -- but forward-slashed when 'shellslash' is set.
    if is_win then variants = { (p:gsub("/", "\\")), (p:gsub("\\", "/")) } end
    for _, v in ipairs(variants) do
      if not vim.tbl_contains(suppressed_dirs, v) then table.insert(suppressed_dirs, v) end
    end
  end
  add("~")
  add("~/Downloads")
  add(vim.env.TEMP)
  add(vim.env.TMP)
  add(vim.env.TMPDIR)
  if is_win then
    add((vim.env.SystemDrive or "C:") .. "\\")
  else
    add("/tmp")
    table.insert(suppressed_dirs, "/")
  end
end

-- Set by pre_save when a mid-session save closed dap-ui; post_save reopens it.
local reopen_dapui_after_save = false

-- Filetypes the post-restore rescue pass never re-lists (see post_restore).
local RESCUE_SKIP_FT = { gitcommit = true, gitrebase = true, gittag = true }

return {
  "rmagatti/auto-session",
  lazy = false, -- must hook into VimEnter early
  keys = {
    -- stylua: ignore start
    { "<leader>wf", "<cmd>AutoSession search<cr>",  desc = "Find session" },
    { "<leader>wS", "<cmd>AutoSession save<cr>",    desc = "Save session" },
    { "<leader>wr", "<cmd>AutoSession restore<cr>", desc = "Restore session" },
    { "<leader>wD", "<cmd>AutoSession delete<cr>",  desc = "Delete session" },
    -- stylua: ignore end
    -- Neovim's ZR (:restart) saves and restores its own session, written
    -- before pre_save_cmds run (so with neo-tree and DAP windows), and
    -- auto-session restores on top of it. :restart! skips Neovim's
    -- session; the old instance auto-saves and the new one auto-restores.
    -- 9ZR keeps its meaning: don't check for changes.
    {
      "ZR",
      function()
        vim.cmd(vim.v.count == 9 and "restart! +qall!" or "restart!")
      end,
      desc = "Restart Neovim (auto-session restores)",
    },
  },
  opts = {
    -- Only the :AutoSession command; the Session* aliases print a
    -- deprecation notice on every use.
    legacy_cmds = false,
    auto_save = true,
    auto_restore = true,
    -- Launched with files (`nvim foo.c`)? auto-session's default is to
    -- never auto-save then. We save only when the work grew into
    -- something worth keeping — 2+ real file buffers or 2+ tabs — so a
    -- quick one-file edit never overwrites the project's session.
    args_allow_files_auto_save = function()
      if #vim.api.nvim_list_tabpages() > 1 then return true end
      local files = 0
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[b].buflisted and require("config.util").is_file_buffer(b) then
          files = files + 1
        end
      end
      return files >= 2
    end,
    -- Don't auto-restore in the home directory or a temp dir; restoring a
    -- random session because you ran `nvim` with no args is annoying. The
    -- list (including the platform temp dir) is built above.
    suppressed_dirs = suppressed_dirs,

    -- Session picker (:AutoSession search / <leader>wf). load_on_setup
    -- would require telescope at startup just to register
    -- :Telescope session-lens.
    session_lens = {
      load_on_setup = false,
      picker_opts = { previewer = true },
    },

    -- pre_save_cmds runs right before auto-session writes the session
    -- file. We use it to close anything that can't survive a round-trip:
    --
    --   * Neo-tree   – its internal buffer collides with a fresh one on
    --                  restore (E95).
    --   * DAP UI panels and the [dap-terminal]/[dap-repl] buffers — these
    --                  are stateful runtime-only buffers, and `mksession`
    --                  encodes them by name, so restore fails with E94
    --                  ("No matching buffer for [dap-terminal] Debug…")
    --                  when the original child process is long gone.
    pre_save_cmds = {
      -- Close neo-tree ONLY if it was ever loaded: a bare "Neotree close"
      -- would hit lazy.nvim's command stub and LOAD neo-tree (and its
      -- deps) during quit just to close a tree that was never open.
      function()
        if package.loaded["neo-tree"] then pcall(vim.cmd, "Neotree close") end
      end,
      function()
        local ok_ui, dapui = pcall(require, "dapui")
        local ok_dap, dap = pcall(require, "dap")
        local debugging = ok_dap and dap.session() ~= nil
        local function is_dap_buf(buf)
          local name = vim.api.nvim_buf_get_name(buf)
          return name:match("%[dap%-") or name:match("%[dap_")
        end
        -- Close DAP UI panels (watches, stacks, breakpoints, scopes, console).
        if ok_ui then pcall(dapui.close) end
        if vim.v.exiting ~= vim.NIL then
          -- Quitting: terminate the debuggee (tears down [dap-terminal];
          -- asynchronous, hence the wipe below), then force-wipe every
          -- [dap-*] buffer so the session script can't try to recreate one.
          if debugging then pcall(dap.terminate) end
          for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if is_dap_buf(buf) then pcall(vim.api.nvim_buf_delete, buf, { force = true }) end
          end
        else
          -- A save WHILE Neovim keeps running (:AutoSession save, switching
          -- sessions): terminating here killed the program being debugged.
          -- Only close the windows showing [dap-*] buffers — mksession
          -- records windows, and these buffers are unlisted/terminal ones
          -- it doesn't recreate otherwise — and reopen the UI afterwards
          -- (post_save_cmds).
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            if is_dap_buf(vim.api.nvim_win_get_buf(win)) then
              pcall(vim.api.nvim_win_close, win, true)
            end
          end
          reopen_dapui_after_save = debugging and ok_ui
        end
      end,
      -- Serialize scope.nvim's per-tab buffer map into a global so it lands
      -- in the session file (sessionoptions includes "globals"). Runs LAST,
      -- after the dap-buffer wipe above, so the saved map can't reference
      -- buffers we're about to delete.
      "ScopeSaveState",
    },

    -- After auto-session restores, re-apply scope.nvim's per-tab buffer map
    -- from the restored global. Without this, every tab would show every
    -- buffer again until the next manual tab switch.
    --
    -- Then reconcile. scope.nvim persists a per-tab list of buffer NAMES and,
    -- on restore, unlists every buffer before re-listing only the ones in that
    -- saved list. On some quits the most-recently-opened buffer doesn't make it
    -- into scope's cache in time (a race in scope's own capture — sporadic by
    -- nature), yet mksession still restores the file as the window's buffer. The
    -- result is a buffer that's loaded but left `buflisted = false`, so it never
    -- appears in bufferline — "I opened it, it's gone from the tabs". The
    -- function below is a safety net: any restored, real-file buffer that scope
    -- accounts for in NO tab gets adopted into the CURRENT tab (listed + added
    -- to scope's cache) so it shows up again. Buffers legitimately scoped to
    -- another tab are in that tab's cache, so they're recognised as accounted
    -- and correctly left hidden — this only rescues the ones scope actually lost.
    post_save_cmds = {
      function()
        if not reopen_dapui_after_save then return end
        reopen_dapui_after_save = false
        pcall(function()
          require("dapui").open()
        end)
      end,
    },
    post_restore_cmds = {
      function()
        if vim.g.ScopeState == nil then return end
        vim.cmd("ScopeLoadState")
        -- ScopeLoadState rebuilds the cache as a list in saved-tab order,
        -- but scope looks entries up by tabpage handle, and handles equal
        -- positions only in a fresh Neovim (not after switching sessions).
        -- Re-key by the restored tabs, then redo scope's own unlist +
        -- tab-enter with the corrected map.
        local ok, core = pcall(require, "scope.core")
        if not ok or type(core.cache) ~= "table" then return end
        local tabs = vim.api.nvim_list_tabpages()
        local by_handle, shifted = {}, false
        for i, tab in ipairs(tabs) do
          by_handle[tab] = core.cache[i]
          shifted = shifted or tab ~= i
        end
        if not shifted then return end
        core.cache = by_handle
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
          if vim.bo[b].buflisted then vim.bo[b].buflisted = false end
        end
        core.on_tab_enter()
      end,
      function()
        local ok, core = pcall(require, "scope.core")
        if not ok then return end
        -- NOTE: core.cache is scope.nvim INTERNAL state (tabpage →
        -- list-of-bufnrs today). It has no stability guarantee, so
        -- every access below is type-guarded: if an upstream update
        -- reshapes it, this rescue pass degrades to a no-op instead of
        -- erroring in the middle of session restore.
        if type(core.cache) ~= "table" then return end
        -- Every buffer scope currently accounts for, across all tabs.
        local accounted = {}
        for _, bufs in pairs(core.cache) do
          if type(bufs) == "table" then
            for _, b in ipairs(bufs) do
              accounted[b] = true
            end
          end
        end
        local cur = vim.api.nvim_get_current_tabpage()
        if type(core.cache[cur]) ~= "table" then core.cache[cur] = {} end
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
          -- Only genuine, named file buffers scope has lost track of. buftype
          -- == "" excludes terminals, help, quickfix, neo-tree, dap panels, etc.
          -- Git message buffers (commit/rebase/tag) are left alone: they
          -- are deliberately unlisted elsewhere and are one-shot by nature.
          if
            not accounted[b]
            and require("config.util").is_file_buffer(b)
            and not RESCUE_SKIP_FT[vim.bo[b].filetype]
          then
            vim.bo[b].buflisted = true
            table.insert(core.cache[cur], b)
          end
        end
      end,
    },

    -- Even if a panel slips past pre_save_cmds (e.g. user opened dapui
    -- without an active session), close it by filetype before saving.
    -- "checkhealth" is auto-session's own default for this list.
    close_filetypes_on_save = {
      "checkhealth",
      "dapui_watches",
      "dapui_stacks",
      "dapui_breakpoints",
      "dapui_scopes",
      "dapui_console",
      "dap-repl",
    },
  },
}
