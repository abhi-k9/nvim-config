-- tests/behavior_spec.lua
--
-- Regression specs for behaviour fixed during the audits (see CHANGES.md).
-- Each case was first reproduced by hand; these keep it from coming back.
-- They run inside the real config (tests/minimal_init.lua dofile()s
-- init.lua), so plugins are loaded on demand through lazy.nvim exactly as
-- in normal use.

local function tmpdir()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  return d
end

local function write(path, lines)
  vim.fn.writefile(lines, path)
  return path
end

-- Feed keys and process them fully (lazy.nvim key stubs re-feed too).
local function feed(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), "xt", false)
end

local function normal_wins()
  local n = 0
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(w).relative == "" then n = n + 1 end
  end
  return n
end

local function reset()
  pcall(vim.cmd, "silent! tabonly!")
  pcall(vim.cmd, "silent! only!")
  pcall(vim.cmd, "silent! %bwipe!")
end

describe("buffer deletion keeps windows", function()
  local util = require("config.util")
  before_each(function()
    reset()
    vim.o.confirm = false -- a prompt would hide the failure mode being tested
  end)

  it("bulk delete force-closes a RUNNING terminal", function()
    vim.cmd("enew")
    local keep = vim.api.nvim_get_current_buf()
    vim.cmd("terminal sleep 60")
    local term = vim.api.nvim_get_current_buf()
    vim.api.nvim_set_current_buf(keep)

    local res = util.delete_buffers_keep_windows({ term })

    assert.are.equal(1, res.deleted)
    assert.are.same({}, res.failed)
    assert.is_false(vim.api.nvim_buf_is_valid(term))
  end)

  it("keeps the split layout when deleting a buffer shown in two windows", function()
    local dir = tmpdir()
    vim.cmd("edit " .. write(dir .. "/a.txt", { "a" }))
    vim.cmd("edit " .. write(dir .. "/b.txt", { "b" }))
    local b = vim.api.nvim_get_current_buf()
    vim.cmd("vsplit")
    assert.are.equal(2, normal_wins())

    util.delete_buffer_keep_windows(b)

    assert.are.equal(2, normal_wins())
    assert.is_false(vim.api.nvim_buf_is_valid(b))
  end)

  it("bufferline close_command skips a MODIFIED buffer without touching its window", function()
    -- lazy.core.loader directly: require("lazy").load() pulls in the
    -- install/update task machinery, which fails under plenary busted.
    require("lazy.core.loader").load("bufferline.nvim", { cmd = "spec" })
    local dir = tmpdir()
    local path = write(dir .. "/dirty.txt", { "original" })
    vim.cmd("edit " .. write(dir .. "/other.txt", { "x" }))
    vim.cmd("vsplit " .. path)
    local dirty = vim.api.nvim_get_current_buf()
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_buf_set_lines(dirty, 0, 0, false, { "unsaved edit" })

    require("bufferline.config").options.close_command(dirty)

    assert.is_true(vim.api.nvim_buf_is_valid(dirty))
    assert.are.equal(dirty, vim.api.nvim_win_get_buf(win)) -- not repointed
    assert.are.same({ "original" }, vim.fn.readfile(path)) -- not written
  end)

  it("<leader>bP closes unpinned buffers but keeps a MODIFIED one", function()
    require("lazy.core.loader").load("bufferline.nvim", { cmd = "spec" })
    local dir = tmpdir()
    vim.cmd("edit " .. write(dir .. "/a.txt", { "a" }))
    local a = vim.api.nvim_get_current_buf()
    vim.cmd("vsplit " .. write(dir .. "/d.txt", { "d" }))
    local d = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(d, 0, 0, false, { "unsaved edit" })
    -- Headless Neovim never draws the tabline, and bufferline only learns
    -- its elements while rendering it.
    vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true })
    local rhs
    for _, k in pairs(require("lazy.core.config").plugins["bufferline.nvim"]._.handlers.keys or {}) do
      if k.lhs == "<leader>bP" then rhs = k.rhs end
    end
    local orig_notify = vim.notify
    vim.notify = function() end
    local ok, err = pcall(rhs)
    vim.notify = orig_notify
    assert.is_true(ok, err)

    assert.is_false(vim.api.nvim_buf_is_valid(a))
    assert.is_true(vim.api.nvim_buf_is_valid(d))
    assert.are.equal(2, normal_wins())
  end)
end)

describe("picker buffer delete (shared by telescope and fzf-lua)", function()
  local util = require("config.util")
  local notes, orig_notify
  before_each(function()
    reset()
    vim.o.confirm = false
    notes = {}
    orig_notify = vim.notify
    vim.notify = function(msg)
      notes[#notes + 1] = msg
    end
  end)
  after_each(function()
    vim.notify = orig_notify
  end)

  it("one target: skips a dirty buffer with the specific message", function()
    local dir = tmpdir()
    vim.cmd("edit " .. write(dir .. "/d.txt", { "x" }))
    local b = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(b, 0, 0, false, { "edit" })
    vim.cmd("enew")
    util.delete_buffers_from_picker({ b })
    assert.is_true(vim.api.nvim_buf_is_valid(b))
    assert.are.same({ "Skipped (unsaved changes): d.txt" }, notes)
  end)

  it("several targets: one batched summary, dirty ones kept", function()
    local dir = tmpdir()
    vim.cmd("edit " .. write(dir .. "/a.txt", { "a" }))
    local a = vim.api.nvim_get_current_buf()
    vim.cmd("edit " .. write(dir .. "/b.txt", { "b" }))
    local b = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(b, 0, 0, false, { "edit" })
    vim.cmd("enew")
    util.delete_buffers_from_picker({ a, b, nil })
    assert.is_false(vim.api.nvim_buf_is_valid(a))
    assert.is_true(vim.api.nvim_buf_is_valid(b))
    assert.are.equal(1, #notes)
    assert.is_truthy(notes[1]:find("Deleted 1 buffer", 1, true))
    assert.is_truthy(notes[1]:find("b.txt", 1, true))
  end)
end)

describe("neo-tree buffers view `d`", function()
  before_each(function()
    reset()
    vim.o.confirm = false
  end)

  it("keeps the split and skips a dirty buffer without an error", function()
    require("lazy.core.loader").load("neo-tree.nvim", { cmd = "spec" })
    local spec = require("lazy.core.config").plugins["neo-tree.nvim"]
    local opts = require("lazy.core.plugin").values(spec, "opts", false)
    local del = opts.buffers.window.mappings["d"]
    assert.are.equal("function", type(del))
    local function state_for(b)
      return {
        tree = {
          get_node = function()
            return { extra = { bufnr = b } }
          end,
        },
      }
    end
    local dir = tmpdir()
    vim.cmd("edit " .. write(dir .. "/a.txt", { "a" }))
    vim.cmd("vsplit " .. write(dir .. "/b.txt", { "b" }))
    local b = vim.api.nvim_get_current_buf()
    vim.cmd("edit " .. write(dir .. "/c.txt", { "c" }))
    local c = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(c, 0, 0, false, { "dirty" })
    vim.cmd("buffer " .. b)

    assert.has_no.errors(function()
      del(state_for(b))
    end)
    assert.are.equal(2, normal_wins())
    assert.is_false(vim.api.nvim_buf_is_valid(b))

    local orig_notify = vim.notify
    vim.notify = function() end
    assert.has_no.errors(function()
      del(state_for(c))
    end)
    vim.notify = orig_notify
    assert.is_true(vim.api.nvim_buf_is_valid(c))
  end)
end)

describe("debugger fallback configurations", function()
  local dap, saved_input
  before_each(function()
    reset()
    require("lazy.core.loader").load("nvim-dap", { cmd = "spec" })
    dap = require("dap")
    saved_input = vim.fn.input
  end)
  after_each(function()
    vim.fn.input = saved_input
  end)

  it("cancelling the executable prompt aborts instead of launching", function()
    for _, answer in ipairs({ "", vim.fn.getcwd() .. "/" }) do
      vim.fn.input = function()
        return answer
      end
      for _, cfg in ipairs(dap.configurations.cpp) do
        if type(cfg.program) == "function" then
          assert.are.equal(dap.ABORT, cfg.program(), cfg.name .. " with " .. vim.inspect(answer))
        end
      end
    end
  end)

  it("picks an un-activated project .venv for Python", function()
    local proj = tmpdir()
    local bin = proj
      .. (vim.fn.has("win32") == 1 and "/.venv/Scripts/python.exe" or "/.venv/bin/python")
    vim.fn.mkdir(vim.fs.dirname(bin), "p")
    vim.fn.writefile({ "#!/bin/sh" }, bin)
    vim.uv.fs_chmod(bin, 493)
    local prev, venv, conda = vim.fn.getcwd(), vim.env.VIRTUAL_ENV, vim.env.CONDA_PREFIX
    vim.env.VIRTUAL_ENV, vim.env.CONDA_PREFIX = nil, nil
    vim.fn.chdir(proj)
    local cfg = dap.configurations.python[#dap.configurations.python]
    local got = cfg.pythonPath()
    vim.fn.chdir(prev)
    vim.env.VIRTUAL_ENV, vim.env.CONDA_PREFIX = venv, conda
    assert.are.equal(vim.fs.normalize(bin), vim.fs.normalize(got))
  end)
end)

describe("keymap hygiene", function()
  before_each(reset)

  it("leaves no default gr<x> LSP map behind (would delay `gr` by timeoutlen)", function()
    require("lazy.core.loader").load("nvim-lspconfig", { cmd = "spec" })
    local left = {}
    for _, mode in ipairs({ "n", "x" }) do
      for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
        if m.lhs:match("^gr.") and (m.desc or ""):match("^vim%.lsp%.") then
          left[#left + 1] = mode .. " " .. m.lhs
        end
      end
    end
    assert.are.same({}, left)
  end)

  it("mini.surround stubs are visual only for the actions mini maps there", function()
    local spec = require("lazy.core.config").plugins["mini.surround"]
    for _, k in pairs(spec._.handlers.keys or {}) do
      if k.mode == "x" then
        assert.is_truthy(
          ({ gza = 1, gzf = 1, gzF = 1 })[k.lhs],
          k.lhs .. " registered in visual mode"
        )
      end
    end
  end)
end)

describe("snippets", function()
  it("friendly-snippets are loaded into LuaSnip (blink's snippet source)", function()
    reset()
    vim.cmd("enew")
    vim.bo.filetype = "lua"
    require("lazy.core.loader").load("LuaSnip", { cmd = "spec" })
    local ls = require("luasnip")
    vim.wait(2000, function()
      return #ls.get_snippets("lua") > 0
    end, 50)
    assert.is_true(#ls.get_snippets("lua") > 0, "LuaSnip has no lua snippets")
  end)
end)

describe("Windows tar shim (forced branch)", function()
  it("puts a copy of the system tar first on PATH, once, and only when needed", function()
    local root = tmpdir()
    vim.fn.mkdir(root .. "/System32", "p")
    local system_tar = write(root .. "/System32/tar.exe", { "bsdtar stand-in" })
    local dir = root .. "/shim"
    local saved = vim.env.PATH
    local util = require("config.util")

    local got = util.windows_tar_shim({ is_win = true, system_tar = system_tar, dir = dir })
    assert.are.equal(dir, got)
    assert.is_truthy(vim.uv.fs_stat(dir .. "/tar.exe"), "system tar not copied")
    assert.is_truthy(vim.startswith(vim.env.PATH, dir .. ";"))
    -- idempotent: a second call doesn't prepend again
    util.windows_tar_shim({ is_win = true, system_tar = system_tar, dir = dir })
    assert.are.equal(1, select(2, vim.env.PATH:gsub(vim.pesc(dir), "")))

    vim.env.PATH = saved
    assert.is_nil(util.windows_tar_shim({ is_win = false, system_tar = system_tar, dir = dir }))
    vim.g.windows_tar_shim = false
    assert.is_nil(util.windows_tar_shim({ is_win = true, system_tar = system_tar, dir = dir }))
    vim.g.windows_tar_shim = nil
    assert.are.equal(saved, vim.env.PATH)
  end)

  it("refreshes the copy when the system tar changes but keeps its size", function()
    local root = tmpdir()
    vim.fn.mkdir(root .. "/System32", "p")
    local system_tar = write(root .. "/System32/tar.exe", { "bsdtar version A" })
    local dir = root .. "/shim"
    local saved = vim.env.PATH
    local util = require("config.util")
    util.windows_tar_shim({ is_win = true, system_tar = system_tar, dir = dir })
    write(system_tar, { "bsdtar version B" })
    local later = os.time() + 60
    vim.uv.fs_utime(system_tar, later, later)
    util.windows_tar_shim({ is_win = true, system_tar = system_tar, dir = dir })
    vim.env.PATH = saved
    assert.are.same({ "bsdtar version B" }, vim.fn.readfile(dir .. "/tar.exe"))
    assert.is_nil(vim.uv.fs_stat(dir .. "/tar.exe.tmp"), "temp copy left behind")
  end)
end)

describe(":SwapClean", function()
  local saved

  before_each(function()
    saved = {
      directory = vim.o.directory,
      swapinfo = vim.fn.swapinfo,
      confirm = vim.fn.confirm,
      notify = vim.notify,
    }
  end)

  after_each(function()
    vim.o.directory = saved.directory
    vim.fn.swapinfo, vim.fn.confirm, vim.notify = saved.swapinfo, saved.confirm, saved.notify
  end)

  it("deletes only leftovers that can't hold unsaved work", function()
    local dir = vim.fs.normalize(tmpdir())
    vim.o.directory = dir .. "//"
    local old = os.time() - 3600
    local infos = {
      ["clean.swp"] = { fname = "/p/clean.c", pid = 0, dirty = 0 },
      ["dirty.swp"] = { fname = "/p/dirty.c", pid = 0, dirty = 1 },
      ["live.swp"] = { fname = "/p/live.c", pid = vim.uv.os_getppid(), dirty = 1 },
      ["own.swp"] = { fname = "/p/own.c", pid = vim.fn.getpid(), dirty = 0 },
      ["empty.swp"] = { error = "Cannot read file" },
      ["junk.swo"] = { error = "Not a swap file" },
    }
    for name in pairs(infos) do
      write(dir .. "/" .. name, name == "empty.swp" and {} or { "x" })
      vim.uv.fs_utime(dir .. "/" .. name, old, old)
    end
    assert.are.equal(0, vim.uv.fs_stat(dir .. "/empty.swp").size)
    vim.fn.swapinfo = function(path)
      local info = infos[vim.fs.basename(path)]
      if info and not info.error then info.host = vim.fn.hostname():sub(1, 39) end
      return info
    end
    local msg
    vim.fn.confirm = function(m)
      msg = m
      return 1
    end
    vim.notify = function() end

    vim.cmd("SwapClean")

    assert.is_truthy(msg:find("Delete (2)", 1, true), msg)
    assert.is_truthy(msg:find("Kept (3)", 1, true), msg)
    assert.is_nil(msg:find("own.c", 1, true), "own swap listed")
    for name in pairs(infos) do
      local gone = name == "clean.swp" or name == "empty.swp"
      assert.are.equal(not gone, vim.uv.fs_stat(dir .. "/" .. name) ~= nil, name)
    end
  end)

  it("deletes nothing when cancelled", function()
    local dir = vim.fs.normalize(tmpdir())
    vim.o.directory = dir .. "//"
    write(dir .. "/a.swp", { "x" })
    vim.fn.swapinfo = function()
      return { fname = "/p/a.c", pid = 0, dirty = 0, host = vim.fn.hostname():sub(1, 39) }
    end
    vim.fn.confirm = function()
      return 2
    end
    vim.notify = function() end
    vim.cmd("SwapClean")
    assert.is_truthy(vim.uv.fs_stat(dir .. "/a.swp"))
  end)
end)

describe("swap inventory", function()
  it("skips a swap dir that doesn't exist", function()
    local saved = vim.o.directory
    local dir = vim.fs.normalize(tmpdir())
    write(dir .. "/a.swp", { "x" })
    vim.o.directory = dir .. "/missing//," .. dir .. "//"
    local ok, list = pcall(require("config.autocmds.swap").inventory)
    vim.o.directory = saved
    assert.is_true(ok, tostring(list))
    assert.are.equal(1, #list)
  end)
end)

describe("big-file mode", function()
  it("gives swap protection back when a re-read file is under the limit", function()
    local saved = vim.g.big_file_size
    local file = write(tmpdir() .. "/f.txt", { string.rep("x", 200) })
    vim.g.big_file_size = 100
    vim.cmd("edit " .. vim.fn.fnameescape(file))
    assert.is_false(vim.bo.swapfile)
    vim.g.big_file_size = 10000
    vim.cmd("edit!")
    vim.g.big_file_size = saved
    assert.are.equal(vim.go.swapfile, vim.bo.swapfile)
    assert.is_nil(vim.b.big_file)
    vim.cmd("bwipe!")
  end)
end)

describe(":SwapDelete <path>", function()
  local saved, asked

  before_each(function()
    saved = { swapinfo = vim.fn.swapinfo, confirm = vim.fn.confirm, notify = vim.notify }
    asked = 0
    vim.fn.confirm = function()
      asked = asked + 1
      return 1 -- "Delete": only the checks may stop it
    end
    vim.notify = function() end
  end)

  after_each(function()
    vim.fn.swapinfo, vim.fn.confirm, vim.notify = saved.swapinfo, saved.confirm, saved.notify
  end)

  local function delete(path, bang)
    vim.cmd((bang and "SwapDelete! " or "SwapDelete ") .. path)
  end

  it("never deletes a file that isn't a swap", function()
    local dir = vim.fs.normalize(tmpdir())
    local file = write(dir .. "/important.txt", { "keep me" })
    vim.fn.mkdir(dir .. "/folder.swp", "p")
    local link = dir .. "/link.swp"
    local linked = vim.uv.fs_symlink(file, link)
    for _, path in ipairs({ file, dir .. "/folder.swp", dir .. "/missing.swp" }) do
      delete(path, true)
    end
    if linked then delete(link, true) end
    assert.are.equal(0, asked)
    assert.are.same({ "keep me" }, vim.fn.readfile(file))
    assert.is_truthy(vim.uv.fs_stat(dir .. "/folder.swp"))
    if linked then assert.is_truthy(vim.uv.fs_lstat(link)) end
  end)

  it("needs the bang for a .swp it can't read as a swap", function()
    local swap = write(vim.fs.normalize(tmpdir()) .. "/broken.swp", { "not a swap" })
    vim.fn.swapinfo = function()
      return { error = "Not a swap file" }
    end
    delete(swap)
    assert.are.equal(0, asked)
    assert.is_truthy(vim.uv.fs_stat(swap))
    delete(swap, true)
    assert.are.equal(1, asked)
    assert.is_nil(vim.uv.fs_stat(swap))
  end)

  it("deletes a readable swap after confirmation, and nothing when cancelled", function()
    local swap = write(vim.fs.normalize(tmpdir()) .. "/a.c.swp", { "x" })
    vim.fn.swapinfo = function()
      return { fname = "/p/a.c", pid = 0, dirty = 0, host = vim.fn.hostname():sub(1, 39) }
    end
    vim.fn.confirm = function()
      return 2
    end
    delete(swap)
    assert.is_truthy(vim.uv.fs_stat(swap))
    vim.fn.confirm = function()
      return 1
    end
    delete(swap)
    assert.is_nil(vim.uv.fs_stat(swap))
  end)
end)

describe(":DiagnosticDump", function()
  it("writes the settings, swap and scoper sections", function()
    local notify = vim.notify
    vim.notify = function() end
    local dest = require("config.diagnostics").dump()
    vim.notify = notify
    assert.is_string(dest)
    local text = table.concat(vim.fn.readfile(dest), "\n")
    vim.fn.delete(dest)
    for _, title in ipairs({ "Settings", "Swap files", "Scoper", "LSP log tail" }) do
      assert.is_truthy(text:find("===== " .. title, 1, true), title)
    end
    assert.is_truthy(text:find("swapfile = ", 1, true))
    assert.is_nil(text:find("(scan failed", 1, true), "swap scan failed")
    assert.is_nil(text:find("(failed:", 1, true), "scoper section failed")
  end)

  it("never overwrites a dump from the same second", function()
    local notify = vim.notify
    vim.notify = function() end
    local diag = require("config.diagnostics")
    local a, b = diag.dump(), diag.dump()
    vim.notify = notify
    vim.fn.delete(a)
    vim.fn.delete(b)
    assert.are_not.equal(a, b)
  end)

  it("redacts env values and secret-looking keys of the DAP config", function()
    local got = require("config.diagnostics").redact({
      type = "python",
      program = "/p/app.py",
      env = { HOME = "/home/me", API_TOKEN = "t0k" },
      headers = { Authorization = "Bearer abc", ["api-key"] = "k" },
      password = "hunter2",
      args = { "--verbose" },
    })
    assert.are.same({
      type = "python",
      program = "/p/app.py",
      env = { HOME = "<redacted>", API_TOKEN = "<redacted>" },
      headers = { Authorization = "<redacted>", ["api-key"] = "<redacted>" },
      password = "<redacted>",
      args = { "--verbose" },
    }, got)
  end)
end)

describe("startup without plugins", function()
  -- A first start with no git (or offline) must leave a usable editor:
  -- explain, skip the plugin layer, keep options/keymaps. Runs a child
  -- Neovim with a fresh data dir and a PATH that contains only nvim.
  it("survives a failed lazy.nvim bootstrap", function()
    if vim.fn.has("win32") == 1 then
      pending("POSIX-only harness (symlinked PATH)")
      return
    end
    local root = tmpdir()
    local bin = root .. "/bin"
    vim.fn.mkdir(bin, "p")
    vim.uv.fs_symlink(vim.v.progpath, bin .. "/nvim")
    local xdg = {}
    for _, k in ipairs({ "config", "data", "state", "cache" }) do
      xdg[k] = root .. "/" .. k
      vim.fn.mkdir(xdg[k], "p")
    end
    vim.uv.fs_symlink(vim.fn.getcwd(), xdg.config .. "/nvim")
    local res = vim
      .system({
        bin .. "/nvim",
        "--headless",
        "-c",
        "lua io.stdout:write('\\nALIVE leader=' .. vim.g.mapleader .. '\\n')",
        "-c",
        "qa",
      }, {
        text = true,
        env = {
          PATH = bin,
          XDG_CONFIG_HOME = xdg.config,
          XDG_DATA_HOME = xdg.data,
          XDG_STATE_HOME = xdg.state,
          XDG_CACHE_HOME = xdg.cache,
        },
        -- (no clear_env: on Neovim 0.11 clear_env = true also dropped the
        -- `env` table itself, so the child saw none of these variables)
      })
      :wait(20000)
    local output = (res.stdout or "") .. (res.stderr or "")
    assert.is_truthy(output:find("starting WITHOUT plugins", 1, true), output)
    assert.is_truthy(output:find("ALIVE leader= ", 1, true), output)
    assert.is_nil(output:find("E5113", 1, true), output)
  end)
end)

describe("fold persistence", function()
  local saved_viewdir
  before_each(function()
    reset()
    saved_viewdir = vim.o.viewdir
    vim.o.viewdir = tmpdir()
  end)
  after_each(function()
    vim.o.viewdir = saved_viewdir
  end)

  it("never writes a view for a URI buffer (diffview://, fugitive://, …)", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, "diffview:///tmp/x/.git/:0:/m.cpp")
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_exec_autocmds("BufWinLeave", { buffer = buf })
    assert.are.same({}, vim.fn.globpath(vim.o.viewdir, "*", false, true))
  end)

  it("saves the view of a buffer whose window is in ANOTHER tab (quit from tab 2)", function()
    local dir = tmpdir()
    vim.cmd("edit " .. write(dir .. "/f.txt", { "top", "  a", "  b", "end" }))
    local buf = vim.api.nvim_get_current_buf()
    vim.wo.foldmethod = "manual"
    vim.cmd("1,3fold")
    vim.cmd("1foldclose")
    vim.cmd("tabnew")
    -- What :qa does for every window: BufWinLeave with ANOTHER buffer current.
    vim.api.nvim_exec_autocmds("BufWinLeave", { buffer = buf })

    local views = vim.fn.globpath(vim.o.viewdir, "*", false, true)
    assert.are.equal(1, #views)
    local text = table.concat(vim.fn.readfile(views[1]), "\n")
    assert.is_truthy(text:find("zc", 1, true), "closed fold not recorded:\n" .. text)
  end)
end)

describe("formatting", function()
  before_each(reset)

  -- The tree is stylua-formatted with hand-aligned blocks fenced by
  -- `-- stylua: ignore start/end`; formatting must fix the rest and leave
  -- those blocks byte-for-byte alone.
  it("visual <leader>cf formats only the selected lines (stylua range end)", function()
    local stylua = vim.fn.executable("stylua") == 1 and "stylua"
      or vim.fn.stdpath("data") .. "/mason/bin/stylua"
    if vim.fn.executable(stylua) == 0 then
      pending("stylua not installed yet")
      return
    end
    vim.cmd("edit " .. write(tmpdir() .. "/r.lua", { "local   a  =  1", "local   b  =  2" }))
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    feed("V cf")
    vim.wait(5000, function()
      return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "local a = 1"
    end, 50)
    feed("<Esc>")
    assert.are.same(
      { "local a = 1", "local   b  =  2" },
      vim.api.nvim_buf_get_lines(0, 0, -1, false)
    )
  end)

  it("stylua (via <leader>cf) formats Lua but keeps ignore ranges intact", function()
    local stylua = vim.fn.executable("stylua") == 1 and "stylua"
      or vim.fn.stdpath("data") .. "/mason/bin/stylua"
    if vim.fn.executable(stylua) == 0 then
      pending("stylua not installed yet (Mason installs it on first start)")
      return
    end
    local path = write(tmpdir() .. "/f.lua", {
      "-- stylua: ignore start",
      "local a    = 1   -- aligned",
      "local bbbb = 2   -- aligned",
      "-- stylua: ignore end",
      "local    zz   =   {1,2}",
    })
    vim.cmd("edit " .. path)
    feed(" cf")
    vim.wait(5000, function()
      return vim.api.nvim_buf_get_lines(0, 4, 5, false)[1] ~= "local    zz   =   {1,2}"
    end, 50)
    assert.are.same({
      "-- stylua: ignore start",
      "local a    = 1   -- aligned",
      "local bbbb = 2   -- aligned",
      "-- stylua: ignore end",
      "local zz = { 1, 2 }",
    }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)
end)

describe("keymaps", function()
  before_each(reset)

  it("<Esc> closes LSP and gitsigns popups but spares UI floats", function()
    local b = vim.api.nvim_create_buf(false, true)
    local base = { relative = "editor", row = 1, col = 1, width = 3, height = 1, focusable = false }
    local hidden = vim.api.nvim_open_win(b, false, vim.tbl_extend("force", base, { hide = true }))
    local chrome = vim.api.nvim_open_win(b, false, base)
    local hover = vim.api.nvim_open_win(b, false, base)
    vim.w[hover].lsp_floating_bufnr = b
    local hunk = vim.api.nvim_open_win(b, false, base)
    vim.w[hunk].gitsigns_preview = "hunk"

    feed("<Esc>")

    assert.is_true(vim.api.nvim_win_is_valid(hidden))
    assert.is_true(vim.api.nvim_win_is_valid(chrome))
    assert.is_false(vim.api.nvim_win_is_valid(hover))
    assert.is_false(vim.api.nvim_win_is_valid(hunk))
    pcall(vim.api.nvim_win_close, hidden, true)
    pcall(vim.api.nvim_win_close, chrome, true)
  end)

  it("breaks undo at punctuation only in prose buffers", function()
    local function has_break_map(ft)
      vim.cmd("enew!")
      vim.bo.filetype = ft
      return vim.fn.maparg(",", "i", false, true).buffer == 1
    end
    assert.is_true(has_break_map("markdown"))
    assert.is_true(has_break_map("text"))
    assert.is_false(has_break_map("lua"))
    assert.are.equal("", vim.fn.maparg(",", "i"))
  end)

  it("ZR restarts without Neovim's own session (auto-session restores)", function()
    local rhs
    for _, k in pairs(require("lazy.core.config").plugins["auto-session"]._.handlers.keys or {}) do
      if k.lhs == "ZR" then rhs = k.rhs end
    end
    assert.are.equal("function", type(rhs))
    local ran, orig = {}, vim.cmd
    vim.cmd = function(c)
      ran[#ran + 1] = c
    end
    local ok, err = pcall(rhs)
    vim.cmd = orig
    assert.is_true(ok, err)
    assert.are.same({ "restart!" }, ran)
  end)

  it("K with no fold and no hover client runs 'keywordprg' (:help in Vim script)", function()
    vim.cmd("enew!")
    vim.bo.filetype = "vim"
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "echo 'x'" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    feed("K")
    vim.wait(2000, function()
      return vim.bo.buftype == "help"
    end, 50)
    assert.are.equal("help", vim.bo.buftype)
  end)

  it("<A-j>/<A-k> take a count and clamp at the file edges", function()
    vim.cmd("enew!")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a", "b", "c", "d", "e" })
    feed("gg3<A-j>")
    assert.are.same({ "b", "c", "d", "a", "e" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    feed("9<A-j>") -- only one line left below: moves to the end
    assert.are.same({ "b", "c", "d", "e", "a" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    feed("ggVj2<A-j><Esc>") -- selection b,c down two
    assert.are.same({ "d", "e", "b", "c", "a" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    feed("GVk9<A-k><Esc>") -- c,a up to the top
    assert.are.same({ "c", "a", "d", "e", "b" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it("<leader>wc in the last window explains instead of raising E444", function()
    local notes, orig = {}, vim.notify
    vim.notify = function(m)
      notes[#notes + 1] = m
    end
    vim.v.errmsg = ""
    feed(" wc")
    vim.notify = orig
    assert.are.equal("", vim.v.errmsg)
    assert.is_truthy((notes[1] or ""):find("Last window", 1, true))
  end)

  it("visual <A-j> moves the selection down and is a silent no-op at the last line", function()
    vim.cmd("enew!")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a", "b", "c", "d" })
    feed("ggVj<A-j><Esc>")
    assert.are.same({ "c", "a", "b", "d" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))

    vim.v.errmsg = ""
    feed("GVk<A-j><Esc>")
    assert.are.same({ "c", "a", "b", "d" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
    assert.are.equal("", vim.v.errmsg)
  end)
end)
