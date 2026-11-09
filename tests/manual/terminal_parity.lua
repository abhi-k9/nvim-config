-- Opt-in comparison, not a CI matrix expansion. The runner owns a disposable
-- process tree and a 45-second deadline per backend. Differences are recorded;
-- successful execution alone does NOT certify migration parity.
local backend = arg[1]
assert(backend == "toggleterm" or backend == "snacks", "unknown terminal backend")
assert(#vim.api.nvim_list_uis() > 0, "use scripts/terminal-parity.py")
local repo, root = vim.fn.getcwd(), assert(vim.env.NVIM_TERMINAL_AUDIT_ROOT)
vim.opt.rtp:prepend(repo)
vim.opt.rtp:append(assert(vim.env.NVIM_TERMINAL_AUDIT_PLUGINS) .. "/" .. backend .. ".nvim")
vim.g.config_local_file = false
require("config.options")
require("config.keymaps")
local spec = dofile(repo .. "/lua/plugins/terminal.lua")[1]
local start = vim.uv.hrtime()
local api
if backend == "toggleterm" then
  api = require("toggleterm")
  api.setup(spec.opts)
else
  require("snacks").setup(dofile(repo .. "/lua/plugins/images.lua").opts())
  api = require("snacks.terminal")
end
local result = {
  backend = backend,
  platform = vim.uv.os_uname().sysname,
  shell = vim.o.shell,
  load_ms = (vim.uv.hrtime() - start) / 1e6,
  notifications = {},
}
-- Record expected Snacks exit notices without opening hit-enter prompts.
-- luacheck: ignore 122
vim.notify = function(message)
  result.notifications[#result.notifications + 1] = tostring(message)
end

local terms, jobs = {}, {}
local argv = {
  vim.v.progpath,
  "--headless",
  "--noplugin",
  "-u",
  "NONE",
  "-i",
  "NONE",
  "-l",
  repo .. "/tests/fixtures/terminal_child.lua",
}
local function command(args)
  -- Toggleterm accepts shell text, not an argv array. Quote each argument
  -- using the host's configured shell; Snacks receives the original array.
  return table.concat(vim.tbl_map(vim.fn.shellescape, args), " ")
end
local function buf(term)
  return term.bufnr or term.buf
end
local function win(term)
  return term.window or term.win
end
local function job(term)
  return vim.b[buf(term)].terminal_job_id
end
local function track(term)
  terms[term] = true
  jobs[job(term)] = true
  return term
end
local function hide(term)
  if backend == "toggleterm" then
    term:close()
  else
    term:hide()
  end
end
local function dispose(term)
  if backend == "toggleterm" then
    term:shutdown()
  else
    term:close()
  end
end
local function clean()
  for term in pairs(terms) do
    dispose(term)
  end
  terms = {}
end
local function cd(path)
  -- Avoid Ex filename/environment expansion, including Windows %NAME%.
  assert(vim.uv.chdir(path))
  vim.api.nvim_set_current_dir(".")
end
local function same_path(left, right)
  return vim.fs.normalize(assert(vim.uv.fs_realpath(left)))
    == vim.fs.normalize(assert(vim.uv.fs_realpath(right)))
end
local function toggle(count, direction, literal_identity)
  if backend == "toggleterm" then
    api.toggle(count, nil, ".", direction)
    return count > 0 and track(require("toggleterm.terminal").get(count, true)) or nil
  end
  return track(api.toggle(nil, {
    count = count > 0 and count or nil,
    cwd = literal_identity and "." or nil,
    shell = spec.opts.shell(),
    win = {
      position = ({ float = "float", horizontal = "bottom", vertical = "right" })[direction],
      border = "rounded",
      backdrop = false,
      height = direction == "horizontal" and 15 or 0.9,
      width = direction == "vertical" and math.floor(vim.o.columns * 0.4) or 0.9,
    },
  }))
end
local function reports(term)
  local found = {}
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf(term), 0, -1, false)) do
    local json = line:match("TERMINAL_AUDIT ({.*})")
    if json then found[#found + 1] = vim.json.decode(json) end
  end
  return found
end
local function report(term, count)
  assert(
    vim.wait(3000, function()
      return #reports(term) >= count
    end),
    "child report timed out"
  )
  return reports(term)[count]
end
local function worker()
  local term
  if backend == "toggleterm" then
    term = require("toggleterm.terminal").Terminal:new({
      cmd = command(argv),
      dir = ".",
      hidden = true,
      direction = "horizontal",
    })
    term:open()
  else
    term = api.toggle(argv, { cwd = ".", win = { position = "bottom", height = 15 } })
  end
  track(term)
  report(term, 1)
  return term
end

local a, b = root .. "/A $NVIM_TERM_LITERAL %NVIM_TERM_LITERAL% # space", root .. "/B"
vim.fn.mkdir(a, "p")
vim.fn.mkdir(b, "p")
vim.env.NVIM_TERM_LITERAL = "expanded"
local ok, err = xpcall(function()
  cd(a)
  vim.env.NVIM_TERMINAL_AUDIT_MARKER = "first"
  start = vim.uv.hrtime()
  local first = toggle(1, "horizontal", true)
  result.first_open_ms = (vim.uv.hrtime() - start) / 1e6
  local id = job(first)
  result.horizontal_height = vim.api.nvim_win_get_height(win(first))
  local probe = vim.list_extend(vim.deepcopy(argv), { "probe" })
  vim.fn.chansend(id, command(probe) .. "\r")
  assert(report(first, 1).cwd == vim.uv.cwd(), "literal spawn cwd differs")
  hide(first)
  local again = toggle(1, "horizontal", true)
  assert(job(again) == id, "repeat toggles replaced a running job")
  vim.api.nvim_win_set_height(win(again), 21)
  hide(again)
  again = toggle(1, "horizontal", true)
  result.resized_height = vim.api.nvim_win_get_height(win(again))
  hide(again)
  cd(b)
  vim.env.NVIM_TERMINAL_AUDIT_MARKER = "second"
  again = toggle(1, "horizontal", true)
  result.literal_identity_reuses_across_projects = job(again) == id
  vim.fn.chansend(job(again), command(probe) .. "\r")
  local retained = report(again, 2)
  result.original_cwd_and_environment = same_path(retained.cwd, a) and retained.marker == "first"
  assert(result.original_cwd_and_environment, "running process changed cwd/environment")
  clean()

  cd(a)
  first = toggle(1, "horizontal", false)
  id = job(first)
  hide(first)
  cd(b)
  again = toggle(1, "horizontal", false)
  result.default_identity_reuses_across_projects = job(again) == id
  clean()

  first = toggle(1, "horizontal", true)
  local second = toggle(2, "horizontal", true)
  assert(job(first) ~= job(second), "counts did not isolate jobs")
  result.numbered_jobs_isolated = true
  result.multiple_windows = #vim.api.nvim_list_wins()
  toggle(0, "horizontal", true)
  result.uncounted_hide_windows = #vim.api.nvim_list_wins()
  toggle(0, "horizontal", true)
  result.uncounted_restore_windows = #vim.api.nvim_list_wins()
  clean()

  first = toggle(1, "vertical", true)
  result.vertical_width = vim.api.nvim_win_get_width(win(first))
  hide(first)
  again = toggle(1, "float", true)
  result.direction_change_to_float = vim.api.nvim_win_get_config(win(again)).relative ~= ""
  clean()

  for _, code in ipairs({ 0, 7 }) do
    for _, hidden in ipairs({ false, true }) do
      local term = worker()
      local buffer, channel = buf(term), job(term)
      if hidden then hide(term) end
      vim.fn.chansend(channel, "exit:" .. code .. "\r")
      assert(
        vim.wait(3000, function()
          return vim.fn.jobwait({ channel }, 0)[1] ~= -1
        end),
        "exit timed out"
      )
      vim.wait(50, function()
        return not vim.api.nvim_buf_is_valid(buffer)
      end)
      local label = "exit_" .. code .. "_" .. (hidden and "hidden" or "visible")
      result[label .. "_cleaned"] = not vim.api.nvim_buf_is_valid(buffer)
      if backend == "snacks" and hidden then
        local reopened = api.toggle(argv, { cwd = ".", win = { position = "bottom", height = 15 } })
        track(reopened)
        result[label .. "_reopened_dead_buffer"] = buf(reopened) == buffer
      end
      clean()
    end
  end

  -- mksession uses the shipped sessionoptions; no terminal/job is serialized.
  vim.cmd.enew()
  local file = root .. "/ordinary.txt"
  vim.fn.writefile({ "session sample" }, file)
  vim.cmd.edit({ args = { file }, magic = { file = false } })
  first = toggle(1, "horizontal", true)
  hide(first)
  toggle(2, "vertical", true)
  local session = root .. "/Session.vim"
  vim.cmd.mksession({ args = { session }, bang = true, magic = { file = false } })
  local contents = table.concat(vim.fn.readfile(session), "\n")
  result.session_excludes_terminals = not contents:find("term://", 1, true)
    and not contents:find("termopen(", 1, true)
  assert(result.session_excludes_terminals, "session serialized a terminal")
  clean()
  vim.cmd.source({ args = { session }, magic = { file = false } })
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    assert(vim.bo[buffer].buftype ~= "terminal", "restored a terminal buffer")
  end
  result.session_restore_clean = true
  if backend == "toggleterm" then
    assert(result.resized_height == 21 and result.direction_change_to_float)
    assert(result.default_identity_reuses_across_projects)
    assert(result.uncounted_hide_windows == 1 and result.uncounted_restore_windows == 3)
    for _, code in ipairs({ 0, 7 }) do
      assert(
        result["exit_" .. code .. "_visible_cleaned"]
          and result["exit_" .. code .. "_hidden_cleaned"]
      )
    end
  end
end, debug.traceback)
for term in pairs(terms) do
  pcall(dispose, term)
end
for channel in pairs(jobs) do
  pcall(vim.fn.jobstop, channel)
end
assert(
  vim.wait(1000, function()
    for channel in pairs(jobs) do
      if vim.fn.jobwait({ channel }, 0)[1] == -1 then return false end
    end
    return true
  end),
  "owned terminal job survived teardown"
)
cd(repo)
assert(ok, err)
assert(#vim.api.nvim_list_wins() == 1, "terminal window survived teardown")
result.teardown_clean = true
return result
