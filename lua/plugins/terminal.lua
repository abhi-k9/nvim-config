-- lua/plugins/terminal.lua
--
-- toggleterm — float / horizontal / vertical terminals and named
-- terminals you can summon (e.g. a "lazygit" terminal).

local Settings = require("config.settings")
-- Keep separate handles only when requested. Existing processes are never
-- killed merely because the editor moves to another project.
local lazygit_terms = {}

local function toggle(direction)
  return function()
    -- Toggleterm expands an absolute cwd again before spawning. A relative
    -- dot survives both expansions and termopen resolves the active cwd
    -- literally, including window-local directories containing "$NAME".
    require("toggleterm").toggle(vim.v.count, nil, ".", direction)
  end
end

return {
  -- -------------------------------------------------------------------------
  -- toggleterm
  -- -------------------------------------------------------------------------
  {
    "akinsho/toggleterm.nvim",
    cmd = { "ToggleTerm", "TermExec" },
    -- <C-\> is mapped in NORMAL mode only. toggleterm's own open_mapping
    -- would also map it in terminal mode, but <C-\> is the prefix of the
    -- built-in <C-\><C-n>; a terminal-mode map would make that escape wait
    -- or break. From inside the terminal: <Esc><Esc> (keymaps.lua), then
    -- <C-\>.
    keys = {
      -- stylua: ignore start
      { "<C-\\>",     toggle("float"),      desc = "Toggle floating terminal" },
      { "<leader>tt", toggle("float"),      desc = "Float terminal" },
      { "<leader>th", toggle("horizontal"), desc = "Horizontal terminal" },
      { "<leader>tv", toggle("vertical"),   desc = "Vertical terminal" },
      { "<leader>tg", function()                                  -- lazygit in a float
          if vim.fn.executable("lazygit") == 0 then
            vim.notify("lazygit is not on PATH", vim.log.levels.WARN)
            return
          end
          local key = Settings.get("terminal.lazygit_per_project", false)
              and Settings.project_root() or "session"
          local lazygit_term = lazygit_terms[key]
          if not lazygit_term then
            lazygit_term = require("toggleterm.terminal").Terminal:new({
              cmd = "lazygit",
              dir = ".", -- preserve literal cwd as for the shell mappings
              hidden = true,
              direction = "float",
              float_opts = { border = "rounded" },
              -- Replaces the opts.on_create below: no window-nav keys in
              -- the float, and <Esc> reaches lazygit at once instead of
              -- after the <Esc><Esc> timeout (keymaps.lua).
              on_create = function(term)
                vim.keymap.set("t", "<Esc>", "<Esc>", { buffer = term.bufnr, nowait = true })
              end,
              -- Quitting lazygit (q) ends the job; drop the handle so the
              -- next press starts a fresh one rather than toggling a
              -- dead terminal.
              on_exit = function()
                if lazygit_terms[key] == lazygit_term then lazygit_terms[key] = nil end
              end,
            })
            lazygit_terms[key] = lazygit_term
          end
          lazygit_term:toggle()
        end, desc = "Lazygit" },
      -- stylua: ignore end
    },
    opts = {
      size = function(term)
        if term.direction == "horizontal" then
          return 15
        elseif term.direction == "vertical" then
          return math.floor(vim.o.columns * 0.4)
        end
        -- Float: toggleterm sizes via float_opts, so size()'s return value
        -- is unused. Returning nothing explicitly (rather than letting
        -- control fall off an `end` mid-branch) keeps intent clear if
        -- toggleterm ever starts reading this value for floats.
      end,
      -- We do NOT set `open_mapping` here. The `<C-\>` chord is already
      -- declared in `keys = { ... }` above; setting both made toggleterm
      -- register the mapping twice and made the source of truth ambiguous.
      --
      -- Inherit the configured shell unless explicitly overridden. "legacy"
      -- retains the earlier Windows PowerShell preference for users who want it.
      shell = function()
        local shell = Settings.get("terminal.shell")
        if type(shell) == "function" then shell = shell() end
        if shell == "legacy" then
          shell = vim.fn.has("win32") == 1 and vim.fn.executable("pwsh") == 1 and "pwsh -NoLogo"
            or nil
        end
        assert(
          shell == nil or type(shell) == "string" and shell ~= "",
          "terminal.shell must be a nonempty string"
        )
        return shell or vim.o.shell
      end,
      -- Navigate OUT of a terminal window with the same <C-h/j/k/l> keys
      -- you use everywhere else. Set per terminal here, not from a
      -- TermOpen pattern: toggleterm's buffer names depend on the shell
      -- ("::toggleterm::" under cmd.exe, "#toggleterm#" elsewhere).
      on_create = function(term)
        local function k(lhs, rhs, desc)
          vim.keymap.set("t", lhs, rhs, { buffer = term.bufnr, desc = desc })
        end
        k("<C-h>", "<Cmd>wincmd h<CR>", "Go to left window")
        k("<C-j>", "<Cmd>wincmd j<CR>", "Go to lower window")
        k("<C-k>", "<Cmd>wincmd k<CR>", "Go to upper window")
        k("<C-l>", "<Cmd>wincmd l<CR>", "Go to right window")
      end,
      shade_terminals = true,
      shading_factor = 2,
      start_in_insert = true,
      persist_size = true,
      persist_mode = true,
      -- Preserve existing jobs' directories. Enabling autochdir would also
      -- make upstream expand absolute project paths before the spawn.
      autochdir = false,
      direction = "float",
      close_on_exit = true,
      float_opts = {
        border = "rounded",
        winblend = 0,
      },
    },
  },
}
