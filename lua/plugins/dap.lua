-- lua/plugins/dap.lua
--
-- Debug Adapter Protocol (DAP) — Neovim's debugger.
--
--   * nvim-dap       — the protocol implementation
--   * nvim-dap-ui    — the panels (variables, stack, breakpoints, …)
--
-- DAP itself is language-agnostic. To debug language X you also need an
-- "adapter" for X (e.g. debugpy for Python, codelldb for C/C++/Rust).
-- lua/config/dap.lua registers the adapters; Mason installs them
-- (mason-tool-installer's list in lua/plugins/formatting.lua).

return {
  -- -------------------------------------------------------------------------
  -- nvim-dap — core
  -- -------------------------------------------------------------------------
  {
    "mfussenegger/nvim-dap",
    keys = {
      -- ---- Breakpoints ----------------------------------------------------
      -- These use persistent-breakpoints.nvim's wrappers so the breakpoint
      -- is saved to disk and reloaded next time you open the file.
      {
        "<leader>db",
        function()
          require("persistent-breakpoints.api").toggle_breakpoint()
        end,
        desc = "Toggle breakpoint",
      },
      {
        "<leader>dB",
        function()
          -- Conditional and/or hit-count breakpoint. persistent-breakpoints'
          -- own set_conditional_breakpoint() only asks for a condition (so a
          -- hit count was unreachable) and turns a cancelled prompt into a
          -- plain breakpoint. Ask for both here; leave both empty to cancel.
          -- breakpoints_changed_in_current_buffer() persists the result
          -- (hitCondition round-trips through the store).
          local cond = vim.fn.input("Condition (empty = none): ")
          local hits = vim.fn.input("Hit count, e.g. 5 or >= 5 (empty = none): ")
          if cond == "" and hits == "" then
            vim.notify("Conditional breakpoint cancelled (no condition, no hit count)")
            return
          end
          require("dap").set_breakpoint(cond ~= "" and cond or nil, hits ~= "" and hits or nil)
          require("persistent-breakpoints.api").breakpoints_changed_in_current_buffer()
        end,
        desc = "Conditional breakpoint (condition / hit count)",
      },
      {
        "<leader>dP",
        function()
          -- Log point — prints a message instead of breaking. {expr} inside
          -- the string evaluates expressions, just like VS Code log points.
          -- Example: "i={i}, value={values[i]}"
          local msg = vim.fn.input("Log message ({expr} for variables): ")
          if msg == "" then return end
          -- Set via dap (persistent-breakpoints' set_log_point() has its own
          -- terse prompt and no cancel), then persist like <leader>dB:
          -- breakpoints_changed_in_current_buffer() updates the plugin's
          -- in-memory set and writes it. store_breakpoints() would write
          -- without updating that set, so the next breakpoint change in
          -- any other file would write the log point away again.
          require("dap").set_breakpoint(nil, nil, msg)
          require("persistent-breakpoints.api").breakpoints_changed_in_current_buffer()
        end,
        desc = "Log point (no break, just print)",
      },
      {
        "<leader>dx",
        function()
          -- List all breakpoints. dap.list_breakpoints() populates the
          -- quickfix list; Trouble (already configured) renders it nicely.
          require("dap").list_breakpoints()
          vim.cmd("Trouble qflist open")
        end,
        desc = "List breakpoints (Trouble)",
      },
      {
        "<leader>dX",
        function()
          -- Use persistent-breakpoints' clear_all_breakpoints(): it calls
          -- dap.clear_breakpoints() AND writes the now-empty set to disk.
          -- Calling dap.clear_breakpoints() directly only clears the
          -- running session — the on-disk store keeps the old
          -- breakpoints, so they reappear on the next BufReadPost, on :cd (the
          -- plugin reloads on DirChanged), or on the next nvim start. There is
          -- no generic save listener to catch a raw dap call.
          require("persistent-breakpoints.api").clear_all_breakpoints()
          vim.notify("All breakpoints cleared")
        end,
        desc = "Clear all breakpoints",
      },
      -- stylua: ignore start
      { "<leader>dc", function() require("dap").continue() end,         desc = "Continue / start" },
      { "<leader>dC", function() require("dap").run_to_cursor() end,    desc = "Run to cursor" },
      { "<leader>di", function() require("dap").step_into() end,        desc = "Step into" },
      { "<leader>do", function() require("dap").step_over() end,        desc = "Step over" },
      { "<leader>dO", function() require("dap").step_out() end,         desc = "Step out" },
      { "<leader>dr", function() require("dap").repl.toggle() end,      desc = "Toggle REPL" },
      { "<leader>dl", function() require("dap").run_last() end,         desc = "Run last" },
      -- stylua: ignore end
      {
        "<leader>dt",
        function()
          require("dap").terminate()
          -- Some adapters (notably cppdbg / OpenDebugAD7) don't emit a
          -- `terminated`/`exited` event on a client-initiated terminate, so the
          -- event_terminated listener that normally closes dap-ui never fires
          -- and the panels linger after an explicit Terminate. Honor the same
          -- vim.g.dap_autoclose_ui flag here so Terminate always leaves a clean
          -- layout. dapui.close() is idempotent, so adapters that DO emit the
          -- event (e.g. codelldb) simply close once.
          if vim.g.dap_autoclose_ui ~= false then
            pcall(function()
              require("dapui").close()
            end)
          end
        end,
        desc = "Terminate",
      },
      -- stylua: ignore start
      { "<leader>dk", function() require("dap").up() end,               desc = "Up (stack)" },
      { "<leader>dj", function() require("dap").down() end,             desc = "Down (stack)" },
      { "<leader>dL", "<cmd>DapLoadLaunchJSON<cr>",                      desc = "Validate launch.json" },
      -- stylua: ignore end
      -- ---- Pause / flow ---------------------------------------------------
      {
        "<leader>dp",
        function()
          require("dap").pause()
        end,
        desc = "Pause (first thread; no picker)",
      },
      {
        "<leader>dT",
        function()
          vim.g.dap_pause_pick_thread = not vim.g.dap_pause_pick_thread
          vim.notify(
            "DAP pause → "
              .. (
                vim.g.dap_pause_pick_thread and "PICK thread (per-thread granularity)"
                or "first thread (no picker)"
              )
          )
        end,
        desc = "Toggle pause thread-picker",
      },
      -- stylua: ignore start
      { "<leader>dg", function() require("dap").goto_() end,            desc = "Set next statement (jump exec to cursor)" },
      { "<leader>dR", function() require("dap").restart() end,          desc = "Restart session" },
      -- stylua: ignore end
      {
        "<leader>dE",
        function()
          require("dap").set_exception_breakpoints()
        end,
        desc = "Exception breakpoints (toggle filters)",
      },
      -- ---- Inspect --------------------------------------------------------
      -- Lightweight hover on the symbol under the cursor (or the visual
      -- selection) in a small floating window, without opening the whole
      -- dap-ui. The float is focusable/scrollable — press <leader>dw again to
      -- jump into it, then q or <Esc> to close. Complements <leader>de, which
      -- routes through dapui.eval and its Watches/expression panel.
      {
        "<leader>dw",
        function()
          require("dap.ui.widgets").hover()
        end,
        mode = { "n", "x" },
        desc = "Hover value (widgets float)",
      },
      -- ---- VS Code function keys (unmodified only) ------------------------
      -- Muscle memory for VS Code migrants, sitting alongside the <leader>d*
      -- chords. Only the UNMODIFIED F-keys are bound here: a plain function key
      -- has an unambiguous legacy encoding that every terminal transmits,
      -- whereas the modified keys VS Code also uses — Shift+F5 (stop),
      -- Shift+F11 (step out), Ctrl+Shift+F5 (restart) — need the kitty keyboard
      -- protocol to arrive distinctly and won't reach nvim on legacy terminals
      -- (the Windows console, or zellij/tmux running over one). That's the same
      -- limitation that makes <C-Space> unreliable, so those three actions
      -- deliberately stay on <leader>dt / <leader>dO / <leader>dR instead.
      -- stylua: ignore start
      { "<F5>",  function() require("dap").continue() end,   desc = "Debug: continue / start (VS F5)" },
      { "<F6>",  function() require("dap").pause() end,       desc = "Debug: pause (VS F6)" },
      { "<F9>",  function() require("persistent-breakpoints.api").toggle_breakpoint() end,
        desc = "Debug: toggle breakpoint (VS F9)" }, -- persistent variant, matches <leader>db
      -- stylua: ignore end
      -- stylua: ignore start
      { "<F10>", function() require("dap").step_over() end,   desc = "Debug: step over (VS F10)" },
      { "<F11>", function() require("dap").step_into() end,   desc = "Debug: step into (VS F11)" },
      -- stylua: ignore end
    },
    config = function()
      require("config.dap").setup()
    end,
  },

  -- -------------------------------------------------------------------------
  -- nvim-dap-virtual-text — inline variable values shown as faded text at the
  -- end of each line while stopped. The closest analogue to Visual Studio's
  -- inline values (the grey "x = 5" VS paints after each statement). Reads the
  -- current stack frame's scopes and renders them in-buffer.
  --
  -- Loads on VeryLazy for the same reason as dap-ui: it registers
  -- dap.listeners during setup(), which must exist before a session starts.
  -- It finds variables with Neovim's own treesitter and the parser's
  -- `locals` query (installed with the parsers by nvim-treesitter); a
  -- buffer without a parser or that query just shows no inline values.
  -- -------------------------------------------------------------------------
  {
    "theHamsta/nvim-dap-virtual-text",
    event = "VeryLazy",
    dependencies = { "mfussenegger/nvim-dap" },
    -- Toggle the end-of-line inline values on/off for when they get noisy
    -- (deep frames, long values). The :DapVirtualTextToggle command is
    -- registered by THIS plugin's setup(), so hanging the key off this spec
    -- guarantees the plugin is loaded before the command runs.
    keys = {
      { "<leader>dv", "<cmd>DapVirtualTextToggle<cr>", desc = "Toggle inline debug values" },
    },
    opts = {
      enabled = true,
      commented = false, -- don't prefix the value with the comment string
      virt_text_pos = "eol", -- end-of-line, so code columns don't shift
      all_frames = false, -- only the frame you're stopped in
      clear_on_continue = false,
    },
    config = function(_, opts)
      require("nvim-dap-virtual-text").setup(opts)
    end,
  },

  -- -------------------------------------------------------------------------
  -- nvim-dap-ui — the debugger panels (scopes/variables, call stack,
  -- breakpoints, watches, REPL/console).
  --
  -- Loads on VeryLazy, NOT only on its <leader>du / <leader>de keys. The
  -- auto-open/close listeners below are registered in this spec's `config`,
  -- and dap.listeners only fire for listeners that already exist when a
  -- session starts. If the plugin loaded only on the first <leader>du/<leader>de
  -- press, those listeners wouldn't exist yet, so the FIRST debug session of
  -- an nvim instance would come up with NO UI — just the dap REPL / the
  -- debuggee's console split — until you manually pressed <leader>du.
  -- VeryLazy registers the listeners at startup so the UI auto-opens on every
  -- session. dapui.setup() opens no windows on its own, so the early load is
  -- cheap; the <leader>du/<leader>de keys still work as before.
  -- -------------------------------------------------------------------------
  {
    "rcarriga/nvim-dap-ui",
    event = "VeryLazy",
    dependencies = {
      "mfussenegger/nvim-dap",
      "nvim-neotest/nvim-nio", -- async IO; required by dap-ui ≥ v3
    },
    keys = {
      -- stylua: ignore start
      { "<leader>du", function() require("dapui").toggle() end,             desc = "Toggle DAP UI" },
      { "<leader>de", function() require("dapui").eval() end, mode = { "n", "x" }, desc = "Eval expression" },
      -- stylua: ignore end
      -- Toggle whether the UI auto-closes when the debuggee exits (the
      -- vim.g.dap_autoclose_ui option documented in config below). Mirrors the
      -- <leader>dT pause-picker toggle pattern: a vim.g flag flipped with a
      -- notify. Takes effect immediately — the listeners read the flag at
      -- event time, so no session restart is needed.
      {
        "<leader>dU",
        function()
          local cur = vim.g.dap_autoclose_ui
          if cur == nil then cur = true end
          vim.g.dap_autoclose_ui = not cur
          vim.notify(
            "DAP UI on exit → "
              .. (vim.g.dap_autoclose_ui and "auto-close" or "stay open (inspect post-mortem)")
          )
        end,
        desc = "Toggle DAP UI auto-close on exit",
      },
    },
    opts = {
      controls = { enabled = true },
      floating = { border = "rounded" },
    },
    config = function(_, opts)
      local dap, dapui = require("dap"), require("dapui")
      dapui.setup(opts)

      -- Auto-close the UI when the debuggee exits?
      --   true  (default) — close on terminate/exit for a clean session end.
      --   false           — leave the panels + REPL up so you can inspect the
      --                     final variable state or scroll the console AFTER
      --                     the program has finished; close it yourself with
      --                     <leader>du.
      -- Flip it at runtime with <leader>dU, or pin a preference in your own
      -- config BEFORE this plugin loads (e.g. `vim.g.dap_autoclose_ui = false`).
      -- We only seed the default when the user hasn't already set one, so a
      -- pre-set preference is never clobbered.
      if vim.g.dap_autoclose_ui == nil then vim.g.dap_autoclose_ui = true end

      -- Open the UI automatically when a session starts.
      dap.listeners.before.attach.dapui_config = function()
        dapui.open()
      end
      dap.listeners.before.launch.dapui_config = function()
        dapui.open()
      end
      -- A launch/attach that FAILS (bad program path, adapter error) ends
      -- the session without any terminated/exited event, so the panels
      -- opened above would stay up, empty. Close them on the error reply.
      -- (Not gated on dap_autoclose_ui: there is nothing to inspect.)
      for _, req in ipairs({ "launch", "attach" }) do
        dap.listeners.after[req].dapui_config = function(_, err)
          if err then dapui.close() end
        end
      end
      -- Close on exit only when auto-close is enabled. The flag is read here,
      -- at event time (not captured above), so <leader>dU applies to the
      -- session already running.
      dap.listeners.before.event_terminated.dapui_config = function()
        if vim.g.dap_autoclose_ui ~= false then dapui.close() end
      end
      dap.listeners.before.event_exited.dapui_config = function()
        if vim.g.dap_autoclose_ui ~= false then dapui.close() end
      end
    end,
  },

  -- -------------------------------------------------------------------------
  -- persistent-breakpoints.nvim — save/load breakpoints across nvim sessions.
  --
  -- Stores them in stdpath("data")/nvim_checkpoints/, one JSON file per
  -- working directory (keyed by file path inside it), so re-opening the
  -- same project — from the same cwd — picks them back up. Conditional breakpoints, log points, and hit-count
  -- breakpoints all round-trip correctly.
  --
  -- We bind the same <leader>db / <leader>dB chords to the persistent
  -- variants so you don't have to remember a second set of keys. The
  -- non-persistent dap.toggle_breakpoint() is still available via lua if
  -- you want a one-off non-saved breakpoint.
  --
  -- Load order: this spec declares nvim-dap as a dependency, which means
  -- lazy.nvim loads nvim-dap TOGETHER WITH IT on BufReadPost — and dap-ui
  -- and dap-virtual-text (event = VeryLazy, also depending on nvim-dap)
  -- pull it in around startup regardless. So despite nvim-dap's `keys`
  -- spec, DAP is effectively loaded shortly after startup; the `keys`
  -- entries act as the keymaps' source of truth, not as a meaningful
  -- lazy-load gate. Note the plugin has no change listener: it only writes
  -- to disk from its own api calls, which is why every breakpoint key here
  -- goes through its api (or calls it right after a raw dap call).
  -- -------------------------------------------------------------------------
  {
    "Weissle/persistent-breakpoints.nvim",
    event = "BufReadPost",
    dependencies = { "mfussenegger/nvim-dap" },
    opts = {
      load_breakpoints_event = { "BufReadPost" },
      always_reload = false, -- only load each file's breakpoints once per session
    },
  },
}
