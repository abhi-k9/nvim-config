describe("optional local-image previews", function()
  local module = require("config.images")
  local settings = require("config.settings")
  local saved, notes, launches, api, source, win, root, file, platform, tools, jobs
  before_each(function()
    settings.reset()
    saved = {
      notify = vim.notify,
      system = vim.system,
      executable = vim.fn.executable,
      has = vim.fn.has,
      uis = vim.api.nvim_list_uis,
      image = package.loaded["snacks.image"],
    }
    win = vim.api.nvim_get_current_win()
    source = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(source)
    vim.api.nvim_buf_set_lines(source, 0, -1, false, { "unsaved code" })
    root = vim.fs.normalize(vim.fn.tempname())
    vim.fn.mkdir(root, "p")
    file = root .. "/image & (sample) %.png"
    vim.fn.writefile({ "image fixture" }, file)
    notes, launches, jobs = {}, {}, {}
    platform, tools = "linux", { magick = true, ["xdg-open"] = true }
    vim.notify = function(message)
      notes[#notes + 1] = message
    end
    vim.fn.has = function(name)
      if name == "win32" then return platform == "windows" and 1 or 0 end
      if name == "mac" then return platform == "mac" and 1 or 0 end
      if name == "gui_running" then return 0 end
      return saved.has(name)
    end
    vim.fn.executable = function(name)
      return tools[name] and 1 or 0
    end
    vim.api.nvim_list_uis = function()
      return { { chan = 1 } }
    end
    vim.system = function(argv, _, callback)
      launches[#launches + 1] = { argv = argv, callback = callback }
      return {}
    end
    api = {
      terminal = {
        detect = function(callback)
          callback()
        end,
      },
      supports_terminal = function()
        return true
      end,
      convert = {
        convert = function(opts)
          local job = {
            opts = opts,
            run = function() end,
            abort = function(self)
              self.aborted = true
            end,
          }
          jobs[#jobs + 1] = job
          return job
        end,
      },
      placement = {
        new = function(buf, path, opts)
          api.placed = { buf = buf, path = path, opts = opts }
        end,
      },
    }
    package.loaded["snacks.image"] = api
  end)
  after_each(function()
    settings.reset()
    vim.notify, vim.system, vim.fn.executable = saved.notify, saved.system, saved.executable
    vim.fn.has, vim.api.nvim_list_uis = saved.has, saved.uis
    package.loaded["snacks.image"] = saved.image
    for _, other in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(other).relative ~= "" then
        vim.api.nvim_win_close(other, true)
      end
    end
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_set_current_win(win) end
    if vim.api.nvim_buf_is_valid(source) then vim.api.nvim_buf_delete(source, { force = true }) end
    vim.fn.delete(root, "rf")
  end)
  local function finish(job, err)
    job.opts.on_done({
      error = function()
        return err
      end,
    })
    local drained = false
    vim.schedule(function()
      drained = true
    end)
    assert.is_true(vim.wait(100, function()
      return drained
    end, 1))
  end
  local function start(path)
    local count = #jobs
    module.open(path or file)
    assert.is_true(
      vim.wait(1000, function()
        return #jobs > count
      end, 1),
      table.concat(notes, "\n")
    )
    return jobs[#jobs]
  end
  it("keeps the default renderer unloaded and passes a literal path to the Unix viewer", function()
    package.loaded["snacks.image"] = nil
    module.open(file)
    assert.is_nil(package.loaded["snacks.image"])
    assert.same({ "xdg-open", file }, launches[1].argv)
    assert.same({ "unsaved code" }, vim.api.nvim_buf_get_lines(source, 0, -1, false))
  end)
  it("uses native Windows and macOS openers without a command shell", function()
    for _, item in ipairs({
      { "windows", "rundll32.exe", { "rundll32.exe", "url.dll,FileProtocolHandler", file } },
      { "mac", "open", { "open", file } },
      { "linux", "wslview", { "wslview", file } },
    }) do
      platform, tools = item[1], { [item[2]] = true }
      module.open(file, true)
      assert.same(item[3], launches[#launches].argv)
    end
  end)
  it("supports legacy Unix ImageMagick without confusing Windows convert.exe for it", function()
    tools = { convert = true, identify = true }
    assert.equals("convert + identify", module.status().converter)
    platform = "windows"
    assert.is_nil(module.status().converter)
    tools.magick = true
    assert.equals("magick", module.status().converter)
  end)
  it("rejects URLs, executables, directories and missing files before any launch", function()
    for _, path in ipairs({
      "https://example.com/image.png",
      "file:///tmp/image.png",
      root,
      root .. "/missing.png",
      root .. "/program.exe",
    }) do
      module.open(path, true)
    end
    assert.equals(5, #notes)
    assert.equals(0, #launches)
    assert.equals(0, #jobs)
  end)
  it(
    "keeps headless, missing-tool and unsupported-terminal fallbacks quiet until requested",
    function()
      settings.configure({ images = { enabled = true, fallback = "notify" } })
      vim.api.nvim_list_uis = function()
        return {}
      end
      module.open(file)
      assert.is_truthy(notes[#notes]:find("no supported terminal UI", 1, true))
      vim.api.nvim_list_uis = function()
        return { {} }
      end
      tools.magick = nil
      module.open(file)
      assert.is_truthy(notes[#notes]:find("ImageMagick is missing", 1, true))
      tools.magick = true
      api.supports_terminal = function()
        return false
      end
      module.open(file)
      assert.is_truthy(notes[#notes]:find("terminal does not support", 1, true))
      assert.equals(0, #launches)
      module.open(file, true)
      assert.equals(1, #launches)
    end
  )
  it("handles incomplete APIs and conversion errors without losing their cause", function()
    settings.configure({ images = { enabled = true, fallback = "notify" } })
    package.loaded["snacks.image"] = true
    module.open(file)
    assert.is_truthy(notes[#notes]:find("snacks.nvim is unavailable", 1, true))
    package.loaded["snacks.image"] = {}
    module.open(file)
    assert.is_truthy(notes[#notes]:find("terminal detection failed", 1, true))
    package.loaded["snacks.image"] = api
    finish(start(), "bad image data")
    assert.is_truthy(notes[#notes]:find("bad image data", 1, true))
    assert.is_nil(api.placed)
    assert.equals(0, #launches)
  end)
  it("uses fresh private snapshots for literal selectors and changed file contents", function()
    settings.configure({ images = { enabled = true } })
    local special = root .. "/literal#page=2.png"
    vim.fn.writefile({ "fixture" }, special)
    local first = start(special)
    assert.is_nil(first.opts.src:find("#page=", 1, true))
    assert.same({ "fixture" }, vim.fn.readfile(first.opts.src))
    vim.fn.writefile({ "changed" }, special)
    local second = start(special)
    assert.is_not.equals(first.opts.src, second.opts.src)
    assert.same({ "changed" }, vim.fn.readfile(second.opts.src))
    finish(first, "cancelled")
    assert.equals(0, vim.fn.filereadable(first.opts.src))
    finish(second)
    assert.equals(0, #launches)
  end)
  it("opens a read-only scoped float only after conversion and preserves the source", function()
    settings.configure({ images = { enabled = true } })
    local job = start()
    assert.is_nil(api.placed)
    finish(job)
    assert.equals(job.opts.src, api.placed.path)
    assert.is_false(vim.bo[api.placed.buf].modifiable)
    assert.is_false(api.placed.opts.inline)
    local preview = vim.api.nvim_get_current_win()
    local close = vim.fn.maparg("<Esc>", "n", false, true).callback
    close()
    assert.is_false(vim.api.nvim_win_is_valid(preview))
    assert.equals(0, vim.fn.filereadable(job.opts.src))
    assert.is_true(vim.api.nvim_win_is_valid(win))
    assert.same({ "unsaved code" }, vim.api.nvim_buf_get_lines(source, 0, -1, false))
  end)
  it(
    "cancels stale detection and aborts superseded conversion without external side effects",
    function()
      settings.configure({ images = { enabled = true } })
      local callback
      api.terminal.detect = function(cb)
        callback = cb
      end
      module.open(file)
      local other = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(other)
      callback()
      assert.equals(0, #jobs)
      vim.api.nvim_set_current_buf(source)
      vim.api.nvim_buf_delete(other, { force = true })
      api.terminal.detect = function(cb)
        cb()
      end
      local stale = start()
      start()
      assert.is_true(stale.aborted)
      finish(stale, "cancelled")
      assert.equals(0, #notes)
      assert.equals(0, #launches)
      assert.is_nil(api.placed)
      finish(jobs[#jobs])
      assert.is_not_nil(api.placed)
    end
  )
  it("makes system-opener failures actionable instead of raising errors", function()
    tools = {}
    module.open(file, true)
    assert.is_truthy(notes[#notes]:find("No system image opener", 1, true))
    tools["xdg-open"] = true
    module.open(file, true)
    launches[1].callback({ code = 3, stderr = "No image association" })
    assert.is_true(vim.wait(100, function()
      return #notes == 2
    end, 1))
    assert.is_truthy(notes[2]:find("No image association", 1, true))
    vim.system = function()
      error("could not spawn")
    end
    module.open(file, true)
    assert.is_truthy(notes[#notes]:find("could not spawn", 1, true))
  end)
  it("bounds conversion time and ignores completion from the cancelled job", function()
    settings.configure({ images = { enabled = true, timeout_ms = 10, fallback = "notify" } })
    local job = start()
    assert.is_true(vim.wait(200, function()
      return job.aborted
    end, 1))
    assert.is_truthy(notes[1]:find("timed out", 1, true))
    finish(job, "cancelled")
    assert.equals(1, #notes)
    assert.is_nil(api.placed)
    assert.equals(0, #launches)
  end)
  it("ignores a late detection callback after the detector raises an error", function()
    settings.configure({ images = { enabled = true, fallback = "notify" } })
    local callback
    api.terminal.detect = function(cb)
      callback = cb
      error("detector failed")
    end
    module.open(file)
    assert.is_truthy(notes[1]:find("detector failed", 1, true))
    callback()
    local drained = false
    vim.defer_fn(function()
      drained = true
    end, 20)
    assert.is_true(vim.wait(100, function()
      return drained
    end, 1))
    assert.equals(1, #notes)
    assert.equals(0, #jobs)
  end)
  it("keeps the optional renderer's automatic document and file hooks disabled", function()
    local spec = dofile("lua/plugins/images.lua")
    assert.is_true(spec.lazy)
    local opts = spec.opts()
    assert.is_false(opts.image.enabled)
    assert.same({}, opts.image.formats)
    assert.is_false(opts.image.doc.enabled)
    assert.is_false(opts.image.math.enabled)
  end)
  it("reports disabled previews as information and opted-in missing tools as warnings", function()
    local records, handlers = {}, {}
    for _, level in ipairs({ "info", "ok", "warn" }) do
      handlers[level] = vim.health[level]
      vim.health[level] = function(message)
        records[#records + 1] = { level, message }
      end
    end
    local ok, err = pcall(function()
      module.health()
      assert.equals(1, #records)
      assert.equals("info", records[1][1])
      settings.configure({ images = { enabled = true } })
      tools = {}
      module.health()
      assert.equals("warn", records[2][1])
      assert.is_truthy(records[2][2]:find("ImageMagick is missing", 1, true))
    end)
    for level, handler in pairs(handlers) do
      vim.health[level] = handler
    end
    assert.is_true(ok, err)
  end)
  it("accepts file-completed paths with spaces through the plugin-independent command", function()
    vim.cmd("ImageOpen! " .. vim.fn.fnameescape(file))
    assert.same({ "xdg-open", file }, launches[1].argv)
  end)
  it("runs the portable command fixture in a bare editor without plugins", function()
    local result = saved
      .system({
        vim.v.progpath,
        "--headless",
        "--noplugin",
        "-u",
        "NONE",
        "-l",
        "tests/fixtures/image_open.lua",
      }, { text = true })
      :wait(5000)
    assert.equals(0, result.code, result.stderr)
  end)
  it(
    "decodes and emits image protocol using the locked renderer, then handles a corrupt file",
    function()
      if
        saved.executable("magick") ~= 1
        and (saved.executable("convert") ~= 1 or saved.executable("identify") ~= 1)
      then
        pending("requires ImageMagick for the native decoder fixture")
        return
      end
      local plugin = assert(require("lazy.core.config").plugins["snacks.nvim"]).dir
      local script = ([=[
vim.opt.rtp:prepend(%q)
vim.opt.rtp:append(%q)
local root = %q
local good, bad = root .. '/native.png', root .. '/corrupt.png'
local tool = vim.fn.executable('magick') == 1 and 'magick' or 'convert'
local generated = vim.system({ tool, '-size', '8x8', 'xc:blue', good }, { text = true }):wait(5000)
assert(generated.code == 0, generated.stderr)
vim.fn.writefile({ 'not an image' }, bad)
require('config.settings').configure({ images = { enabled = true, fallback = 'notify' } })
local opts = dofile('lua/plugins/images.lua').opts()
opts.image.cache = root .. '/renderer-cache'
require('snacks').setup(opts)
local api = require('snacks.image')
local bytes = 0
api.terminal._env = { name = 'fixture', supported = true, placeholders = true, remote = true }
api.terminal.detect = function(callback) callback() end
api.terminal.write = function(data) bytes = bytes + #data end
vim.api.nvim_list_uis = function() return { { chan = 1 } } end
local notes = {}
vim.notify = function(message) notes[#notes + 1] = message end
local source = vim.api.nvim_get_current_win()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'unsaved source' })
require('config.images').open(good)
assert(vim.wait(10000, function() return bytes > 0 and vim.api.nvim_get_current_win() ~= source end, 10), table.concat(notes, '\n'))
assert(#notes == 0, table.concat(notes, '\n'))
assert(vim.bo.filetype == 'config-image' and not vim.bo.modifiable)
local view = vim.api.nvim_get_current_win()
vim.fn.maparg('<Esc>', 'n', false, true).callback()
assert(not vim.api.nvim_win_is_valid(view))
assert(vim.api.nvim_get_current_line() == 'unsaved source')
require('config.images').open(bad)
assert(vim.wait(10000, function() return #notes > 0 end, 10))
assert(notes[1]:find('image decoding failed', 1, true), notes[1])
assert(vim.api.nvim_get_current_win() == source)
assert(not api.config.doc.enabled and not api.config.math.enabled and #api.config.formats == 0)
io.stdout:write('Native image decoder and protocol fixture passed\n')
]=]):format(vim.fn.getcwd(), plugin, root)
      local script_path = root .. "/renderer.lua"
      vim.fn.writefile(vim.split(script, "\n", { plain = true }), script_path)
      local result = saved
        .system(
          { vim.v.progpath, "--headless", "--noplugin", "-u", "NONE", "-l", script_path },
          { text = true }
        )
        :wait(25000)
      assert.equals(0, result.code, result.stderr)
      assert.is_truthy(
        result.stdout:find("Native image decoder and protocol fixture passed", 1, true)
      )
    end
  )
end)
