-- tests/config_spec.lua
--
-- Two checks on the Neovim config itself:
--
--   1. Smoke test — minimal_init.lua already loaded init.lua before this
--      spec ran. If it had thrown, we wouldn't be here. So the smoke
--      portion is implicit; we just assert a couple of post-conditions
--      to confirm the load reached the end.
--
--   2. Duplicate <leader> registration guard. tests/minimal_init.lua hooks
--      vim.api.nvim_set_keymap during the synchronous config load and logs
--      every (mode, lhs); the spec below fails if one <leader> key is
--      registered twice in the same mode — across keymaps.lua AND every
--      lazy.nvim `keys` spec. Known blind spots: buffer-local maps
--      (LspAttach, gitsigns on_attach, picker prompts), maps a plugin sets
--      itself inside config(), and prefix shadowing between distinct LHSs.
--      The only intentionally repeated leader LHS is <leader>sr, split
--      across modes n and x (search.lua).
--
-- These tests run inside a headless Neovim that has the real config loaded.

describe("nvim config", function()
  describe("smoke test", function()
    it("loaded options.lua (mapleader is set)", function()
      assert.equals(" ", vim.g.mapleader)
    end)

    it("loaded the plugin manager", function()
      -- minimal_init.lua sourced init.lua → config.lazy → require("lazy").
      -- If the require succeeded, `package.loaded["lazy"]` is non-nil.
      assert.is_not_nil(package.loaded["lazy"])
    end)

    it("loaded the bundled local plugin from this checkout", function()
      assert.equals(2, vim.fn.exists(":ScoperStatus"), "bundled scoper.nvim did not load")
    end)
  end)

  -- The duplicate-registration guard. It reads the log that
  -- tests/minimal_init.lua fills by hooking nvim_set_keymap (the single
  -- low-level chokepoint all global maps funnel through) across the synchronous
  -- config load. Two config sites mapping the same <leader> key in the same
  -- mode both appear in that log, so they're caught.
  describe("leader keymap registrations (synchronous config load)", function()
    local log = _G.__config_keymap_registrations

    it("were captured (harness sanity)", function()
      -- If this fails, the spec wasn't run through tests/minimal_init.lua, so
      -- the duplicate check below would be silently meaningless.
      assert.is_table(log)
      assert.is_true(
        #log > 0,
        "no keymap registrations captured — was tests/minimal_init.lua used?"
      )
    end)

    it("contain no duplicate <leader> map within one mode", function()
      local mapleader = vim.g.mapleader or " "
      local function leader_key(lhs)
        if type(lhs) ~= "string" then return nil end
        -- Registrations carry the lhs as written: usually the literal
        -- "<leader>x", occasionally the expanded "<space>x". Normalize both.
        if lhs:sub(1, 8):lower() == "<leader>" then return "<leader>" .. lhs:sub(9) end
        if #mapleader > 0 and lhs:sub(1, #mapleader) == mapleader then
          return "<leader>" .. lhs:sub(#mapleader + 1)
        end
        return nil
      end

      local seen, dupes = {}, {}
      -- Every lazy `keys` entry, as one registration each (mode, lhs).
      local ok_cfg, LazyCfg = pcall(require, "lazy.core.config")
      local lazy_regs = {}
      if ok_cfg and LazyCfg.plugins then
        for name, plugin in pairs(LazyCfg.plugins) do
          local keys = plugin._ and plugin._.handlers and plugin._.handlers.keys or {}
          for _, k in pairs(keys) do
            lazy_regs[#lazy_regs + 1] = { mode = k.mode or "n", lhs = k.lhs, src = name }
          end
        end
      end
      local all = {}
      for _, reg in ipairs(log or {}) do
        if not reg.lazy then all[#all + 1] = reg end
      end
      vim.list_extend(all, lazy_regs)
      for _, reg in ipairs(all) do
        local key = leader_key(reg.lhs)
        if key then
          local id = reg.mode .. "  " .. key
          if seen[id] then
            dupes[#dupes + 1] = id
          else
            seen[id] = true
          end
        end
      end
      assert.are.same(
        {},
        dupes,
        "duplicate <leader> registrations (mode  key): " .. vim.inspect(dupes)
      )
    end)

    it("saw the plugin specs' keys (harness sanity: lazy actually loaded)", function()
      local LazyCfg = require("lazy.core.config")
      assert.is_true(
        vim.tbl_count(LazyCfg.plugins or {}) > 10,
        "lazy.nvim loaded no plugin specs — the suite would test nothing plugin-backed"
      )
    end)
  end)
end)
