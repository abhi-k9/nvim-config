-- lua/scoper/ui.lua
--
-- Floating-window UI primitives and selection helpers:
--   * show_lines(lines, title)        – read-only info panel (used by :ScoperShow)
--   * pick_one(items, opts, cb)       – vim.ui.select wrapper (used by M.use)
--   * pick_many(items, opts, cb)      – multi-select selector (used by M.remove,
--                                        M.delete); fzf-lua / telescope / vim.ui
--                                        backends, auto-detected at call time
--   * input(prompt, default, cb)      – vim.ui.input wrapper
--   * pick_dirs(cb)                   – iterative directory picker for :ScoperAdd
--
-- pick_one and input are thin wrappers over vim.ui.* so any UI
-- replacement (telescope-ui-select, dressing.nvim, fzf-lua's
-- ui_select) just works. pick_many and pick_dirs are designed to be
-- picker-plugin-aware: pick_many uses fzf-lua / telescope native
-- multi-select when available and falls back to a vim.ui.select loop
-- when neither is loaded; pick_dirs uses Vim-native `completion = "dir"`
-- which works without any picker plugin.

local M = {}

-- Backend detection lives in scoper.util (has / prefer_fzf), shared
-- with pickers.lua.
-- Re-checked per call so users installing/uninstalling a picker plugin
-- mid-session don't have to restart.
local Util = require("scoper.util")
local has = Util.has

-- ---------------------------------------------------------------------------
-- Read-only info panel: list lines in a centered float. `q` or <Esc> closes.
-- ---------------------------------------------------------------------------
function M.show_lines(lines, title)
  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = math.min(math.max(width + 4, 40), math.floor(vim.o.columns * 0.9))
  local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.8))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "scoper"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " " .. (title or "Scoper") .. " ",
    title_pos = "center",
  })

  -- Close keys.
  local close = function()
    pcall(vim.api.nvim_win_close, win, true)
  end
  -- stylua: ignore start
  vim.keymap.set("n", "q",     close, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true, silent = true })
  -- stylua: ignore end
end

-- ---------------------------------------------------------------------------
-- Pick one item from a list. Wraps vim.ui.select so any UI replacement
-- (telescope-ui-select, dressing.nvim, fzf-lua's ui_select) just works.
-- ---------------------------------------------------------------------------
function M.pick_one(items, opts, cb)
  vim.ui.select(items, opts or {}, function(choice, idx)
    if choice ~= nil then cb(choice, idx) end
  end)
end

-- ---------------------------------------------------------------------------
-- Pick ONE OR MORE items from a list. Three backends auto-detected at
-- call time so this works regardless of which picker plugins are loaded:
--
--   1. fzf-lua    – fzf_exec with `--multi`; <Tab> toggles, <C-a> toggles
--                   all, <CR> confirms whatever is selected (or just the
--                   highlighted entry if nothing was toggled).
--   2. telescope  – custom picker with multi-selection via
--                   actions.toggle_selection (<Tab> / <S-Tab>); <CR>
--                   reads get_multi_selection() if any toggles exist,
--                   otherwise the single highlighted entry.
--   3. plain vim  – looped vim.ui.select with a synthetic "(done)" item
--                   prepended. Each pick is added to the accumulator
--                   and removed from the remaining list; the user
--                   stops by selecting "(done)" or pressing Esc.
--
-- Backend preference matches pickers.lua: fzf-lua first, telescope when
-- `vim.g.scoper_picker == "telescope"` or fzf-lua isn't loaded, plain
-- vim when neither picker is available.
--
-- Callback signature: cb(picked) where picked is an array of strings.
-- Behaviour on abort varies by backend: the fzf-lua and telescope
-- branches do NOT fire cb at all when the user cancels (Esc / Ctrl-C);
-- the fallback DOES fire cb with whatever has been picked so far when
-- the user picks "(done)" or hits Esc — which may be an empty array.
-- Callers should treat both "cb not called" and "cb with empty list"
-- as no-ops; the typical guard is `if #picked > 0 then ...`.
-- ---------------------------------------------------------------------------
function M.pick_many(items, opts, cb)
  opts = opts or {}
  local prompt = opts.prompt or "Select"

  -- fzf-lua: built-in --multi via fzf_opts. The default action receives
  -- a list of strings (the selected items in selection order, or just
  -- the highlighted one if nothing was Tab-toggled).
  if Util.prefer_fzf() then
    require("fzf-lua").fzf_exec(items, {
      prompt = prompt .. "> ",
      fzf_opts = {
        ["--multi"] = true,
        ["--bind"] = "ctrl-a:toggle-all",
      },
      actions = {
        ["default"] = function(selected)
          cb(selected or {})
        end,
      },
    })
    return
  end

  -- telescope: custom picker. We can't use telescope.builtin for this
  -- (no generic multi-select builtin), so build the picker manually.
  -- `get_multi_selection()` returns the entries the user Tab-toggled;
  -- if they just hit <CR> on the highlighted row without toggling
  -- anything, fall back to that single entry.
  if has("telescope.pickers") then
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    pickers
      .new({}, {
        prompt_title = prompt,
        finder = finders.new_table({ results = items }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr)
          actions.select_default:replace(function()
            local picker = action_state.get_current_picker(prompt_bufnr)
            local multi = picker:get_multi_selection()
            local result = {}
            if multi and #multi > 0 then
              for _, entry in ipairs(multi) do
                -- entry.value is what new_table sets; entry[1] is its
                -- positional alias for plain string results.
                table.insert(result, entry.value or entry[1])
              end
            else
              local entry = action_state.get_selected_entry()
              if entry then table.insert(result, entry.value or entry[1]) end
            end
            actions.close(prompt_bufnr)
            cb(result)
          end)
          return true
        end,
      })
      :find()
    return
  end

  -- Plain-vim fallback: looped vim.ui.select. Prepend a "(done)"
  -- sentinel so the user can commit a partial selection without having
  -- to pick every remaining item. Esc also commits whatever's been
  -- picked so far (vim.ui.select calls cb with nil on cancel).
  local picked = {}
  local remaining = vim.list_extend({}, items)

  local function loop()
    if #remaining == 0 then
      cb(picked)
      return
    end
    local choices = vim.list_extend({ "(done)" }, remaining)
    local loop_prompt = prompt
    if #picked > 0 then loop_prompt = ("%s [%d picked]"):format(prompt, #picked) end
    vim.ui.select(choices, vim.tbl_extend("force", opts, { prompt = loop_prompt }), function(choice)
      if choice == nil or choice == "(done)" then
        cb(picked)
        return
      end
      table.insert(picked, choice)
      for i, v in ipairs(remaining) do
        if v == choice then
          table.remove(remaining, i)
          break
        end
      end
      loop()
    end)
  end
  loop()
end

-- ---------------------------------------------------------------------------
-- Prompt for free-form text. Same idea, vim.ui.input.
-- ---------------------------------------------------------------------------
function M.input(prompt, default, cb)
  vim.ui.input({ prompt = prompt, default = default or "" }, function(input)
    if input ~= nil and input ~= "" then cb(input) end
  end)
end

-- ---------------------------------------------------------------------------
-- Interactive directory picker.
--
-- Loops: each <CR> adds the typed path and re-prompts with the same parent
-- pre-filled (so adding sibling directories is quick). Empty input ends.
--
-- The `completion = "dir"` tells Vim to use directory completion on <Tab>
-- inside the input — works without any picker plugin.
--
-- The callback is called with an array of accumulated paths. If the user
-- aborts (Esc) on the first prompt, callback is called with an empty array.
-- ---------------------------------------------------------------------------
function M.pick_dirs(cb)
  local picked = {}

  local function ask(default)
    vim.ui.input({
      prompt = ("Scoper: add dir [#%d, empty to finish]: "):format(#picked + 1),
      default = default or "",
      completion = "dir",
    }, function(input)
      if input == nil or input == "" then
        cb(picked)
        return
      end
      -- `completion = "dir"` inserts a directory containing spaces as
      -- "my\ dir/"; unescape so the stored path is the real one.
      input = input:gsub("\\(%s)", "%1")
      table.insert(picked, input)
      -- Pre-fill the parent so it's easy to add another sibling. Without
      -- the trailing slash that completion leaves, or dirname() returns
      -- the directory itself.
      local parent = vim.fs.dirname((input:gsub("[/\\]+$", "")))
      if parent == "." then
        parent = ""
      elseif parent:sub(-1) ~= "/" then
        parent = parent .. "/"
      end
      ask(parent)
    end)
  end

  ask()
end

return M
