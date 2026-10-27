-- lua/plugins/search.lua
--
-- grug-far.nvim — project-wide search & replace with a live preview pane.
-- Think VS Code's "search across files" view, but inside Neovim and backed
-- by ripgrep / ast-grep. Far more pleasant than `:cdo s/foo/bar/g | update`.

local function open(prefills)
  local opts = require("config.search").replace_options(prefills)
  if opts then require("grug-far").open(opts) end
end

return {
  "MagicDuck/grug-far.nvim",
  cmd = { "GrugFar" },
  keys = {
    -- ---- Project-wide search/replace --------------------------------------
    -- `<leader>sr` is bound TWICE on purpose: once for normal mode (open
    -- empty) and once for visual mode ("x" — not "v", which would also
    -- catch select mode inside snippet placeholders) to prefill the
    -- selected text.
    -- A naive duplicate-keymap detector might flag these as a conflict;
    -- the test suite's `tests/config_spec.lua` checker is mode-aware and
    -- correctly treats them as distinct bindings.
    {
      "<leader>sr",
      function()
        open()
      end,
      desc = "Search/Replace (project)",
    },

    -- Search/replace the word under the cursor. `<cword>` is Vim's
    -- "current word" expansion — letters, digits, underscores — so this
    -- works for identifiers in any language without language-specific
    -- helpers.
    {
      "<leader>sw",
      function()
        open({ search = vim.fn.expand("<cword>") })
      end,
      desc = "Search/Replace word under cursor",
    },

    -- Restrict the search to the current file by prefilling `paths`.
    -- Useful for repetitive in-file edits where :substitute would lose
    -- you to typos in the regex.
    {
      "<leader>sf",
      function()
        local path = vim.api.nvim_buf_get_name(0)
        if vim.bo.buftype ~= "" or path == "" or vim.fn.filereadable(path) == 0 then
          vim.notify("Current-file search requires a saved file buffer", vim.log.levels.WARN)
          return
        end
        -- A newline becomes a path separator in grug-far's input. Refuse
        -- names that cannot be represented without widening the search.
        if path:find("[\r\n]") then
          vim.notify(
            "Current-file search cannot represent newlines in a file name",
            vim.log.levels.WARN
          )
          return
        end
        -- The pinned backend expands $NAME while normalizing paths. It has
        -- no literal-path option, so passing such a file could target a
        -- different existing file. Refuse even unset names: environment
        -- variables can change before a deferred search or replacement.
        if path:find("%$[%w_]+") then
          vim.notify(
            "Current-file search cannot preserve literal $NAME in a file name",
            vim.log.levels.WARN
          )
          return
        end
        -- grug-far splits `paths` on spaces itself and only understands a
        -- BACKSLASH-escaped space ("my\ dir/f.c"); double quotes are
        -- passed through literally, so `"my dir/f.c"` searched nothing.
        -- Use the absolute buffer name: the pinned parser drops a single
        -- character prefill (e.g. "x"), which otherwise searches the cwd.
        path = path:gsub(" ", "\\ ")
        require("grug-far").open({ prefills = { paths = path } })
      end,
      desc = "Search/Replace (current file)",
    },

    -- Visual-mode variant of <leader>sr: open() called from visual mode
    -- prefills the "search" field with the live selection itself.
    {
      "<leader>sr",
      function()
        open()
      end,
      mode = "x",
      desc = "Search/Replace selection",
    },
  },
  -- grug-far's in-buffer actions are <localleader>-prefixed by default, so
  -- they don't collide with global <leader> bindings. Our <localleader> is
  -- "\" (lua/config/options.lua): `\r` replace, `\q` quickfix, `\s` sync,
  -- `\e` swaps the engine (rg → ast-grep → ast-grep rules), g? lists them
  -- all. <down>/<up> step match by match and <enter> jumps.
  opts = {},
  -- grug-far has no "next file" action: buffer-local ]f / [f jump between
  -- result paths using their highlight extmarks. Text is ambiguous: a
  -- source match after an empty matching line also follows a blank line.
  init = function()
    vim.api.nvim_create_autocmd("FileType", {
      group = require("config.util").augroup("grugfar_file_nav"),
      pattern = "grug-far",
      callback = function(ev)
        local function jump_file_header(backward)
          local row = vim.api.nvim_win_get_cursor(0)[1] - 1
          local marks = vim.api.nvim_buf_get_extmarks(
            ev.buf,
            -1,
            { row, 0 },
            backward and 0 or -1,
            {
              details = true,
              type = "highlight",
            }
          )
          for _, mark in ipairs(marks) do
            local details = mark[4]
            if
              mark[2] ~= row
              and not details.invalid
              and details.hl_group == "GrugFarResultsPath"
            then
              vim.api.nvim_win_set_cursor(0, { mark[2] + 1, 0 })
              return
            end
          end
        end
        vim.keymap.set("n", "]f", function()
          jump_file_header(false)
        end, { buffer = ev.buf, desc = "Next file header (grug-far)" })
        vim.keymap.set("n", "[f", function()
          jump_file_header(true)
        end, { buffer = ev.buf, desc = "Prev file header (grug-far)" })
      end,
    })
  end,
}
