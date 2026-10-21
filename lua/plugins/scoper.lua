-- lua/plugins/scoper.lua
--
-- Local-plugin spec for scoper.nvim, which is bundled in this config under
-- `scoper.nvim/` (relative to this checkout). Resolve the path from this
-- spec's source so headless tests and `nvim -u /path/to/init.lua` also work
-- when stdpath("config") points at a different configuration.
--
-- Want to point at a clone of your own instead? Set `dir = "~/projects/scoper.nvim"`.
-- Want to use the published version once it's on GitHub? Replace the table
-- with `"<owner>/scoper.nvim"` (and drop `dir`).
--
-- Setup options:
--   lsp.clangd        – auto-rewrite compile_commands.json on scope change
--   lsp.clangd_args   – extra clangd flags (here: --query-driver for MinGW/MSYS2)
--   default_excludes  – seed every new scope, including a fresh project's default scope

local config_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")

return {
  {
    dir = vim.fs.joinpath(config_root, "scoper.nvim"),
    -- Loaded eagerly so :Scoper* commands are registered up front. The
    -- heavy modules inside scoper itself are still lazy-required on demand.
    lazy = false,
    config = function()
      -- MinGW/MSYS2 gcc reports its system headers to clangd only if the
      -- driver matches --query-driver (MSVC needs nothing). clangd runs
      -- whatever matches, so list the drivers rather than a catch-all glob.
      local drivers = {}
      for _, exe in ipairs({ "gcc", "g++", "cc", "c++" }) do
        local path = vim.fn.exepath(exe)
        if path ~= "" then
          -- clangd matches case-sensitively; exepath() spells the extension
          -- as $PATHEXT does (".EXE"), compile databases write ".exe".
          drivers[#drivers + 1] = (path:gsub("\\", "/"):gsub("%.[eE][xX][eE]$", "")) .. "*"
        end
      end
      if vim.fn.has("win32") == 1 then
        vim.list_extend(drivers, { "C:/msys64/*/bin/*gcc*", "C:/msys64/*/bin/*g++*" })
      end
      require("scoper").setup({
        lsp = {
          clangd = true, -- auto-rebuild compile_commands.json
          clangd_args = #drivers > 0 and { "--query-driver=" .. table.concat(drivers, ",") } or nil,
        },
        default_excludes = { -- seed every new scope, including the default one
          "**/node_modules/**",
          "**/.git/**",
          "**/target/**",
        },
      })
    end,
  },
}
