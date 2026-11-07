-- Explicit local-image previews. Optional renderers never own file reads,
-- document events, cwd, or the source buffer; OS viewers receive literal argv.
local M = {}
local Settings = require("config.settings")
local active
local formats = { "png", "jpg", "jpeg", "gif", "webp", "bmp", "tif", "tiff", "avif", "heic", "ico" }

local function notify(message)
  vim.notify(message .. " See :ConfigHelp images or :checkhealth config.", vim.log.levels.WARN)
end

local function cancel_pending()
  if active then active.cancel() end
end

local function opener()
  if vim.fn.has("win32") == 1 then
    -- vim.ui.open uses cmd.exe /c start on 0.12. Avoid shell interpretation
    -- of &, %, | and parentheses in Windows file names.
    if vim.fn.executable("rundll32.exe") == 1 then
      return { "rundll32.exe", "url.dll,FileProtocolHandler" }
    end
  elseif vim.fn.has("mac") == 1 then
    if vim.fn.executable("open") == 1 then return { "open" } end
  else
    for _, command in ipairs({ "xdg-open", "wslview" }) do
      if vim.fn.executable(command) == 1 then return { command } end
    end
  end
end

function M.status()
  local lazy = package.loaded["lazy.core.config"]
  local plugin = type(lazy) == "table"
    and type(lazy.plugins) == "table"
    and lazy.plugins["snacks.nvim"]
  local renderer = type(package.loaded.snacks) == "table"
    or type(plugin) == "table"
      and type(plugin.dir) == "string"
      and vim.fn.filereadable(plugin.dir .. "/lua/snacks/init.lua") == 1
  local converter = vim.fn.executable("magick") == 1 and "magick" or nil
  -- Windows' convert.exe is a disk utility, not ImageMagick.
  if
    not converter
    and vim.fn.has("win32") == 0
    and vim.fn.executable("convert") == 1
    and vim.fn.executable("identify") == 1
  then
    converter = "convert + identify"
  end
  return {
    enabled = Settings.get("images.enabled", false) == true,
    renderer = not not renderer,
    converter = converter,
    ui = #vim.api.nvim_list_uis() > 0 and vim.fn.has("gui_running") == 0,
    opener = opener(),
  }
end

local function external(path)
  local argv = opener()
  if not argv then
    notify("No system image opener is available; configure a desktop file association/opener.")
    return
  end
  argv[#argv + 1] = path
  local ok, err = pcall(
    vim.system,
    argv,
    { text = true, detach = true, stdout = false },
    function(result)
      if result.code ~= 0 then
        vim.schedule(function()
          notify(
            "System image viewer failed (exit "
              .. result.code
              .. "): "
              .. vim.trim(result.stderr or ""):sub(1, 400)
          )
        end)
      end
    end
  )
  if not ok then notify("System image viewer could not start: " .. tostring(err)) end
end

local function path_for(path)
  path = path and path ~= "" and path or vim.api.nvim_buf_get_name(0)
  if path == "" then return nil, "Choose a local image: :ImageOpen path/to/image.png." end
  if path:find("%c") or path:match("^[%a][%w+.-]*://") then
    return nil, "ImageOpen accepts local file paths, without control characters or URI schemes."
  end
  if vim.fn.has("win32") == 1 and path:match("^%a:") and not path:match("^%a:[/\\]") then
    return nil, "Use a fully qualified Windows image path; drive-relative paths are ambiguous."
  end
  if path:match("^~[/\\]") then path = (vim.uv.os_homedir() or "~") .. path:sub(2) end
  path = vim.fs.normalize(vim.fs.abspath(path), { expand_env = false })
  if not vim.tbl_contains(formats, vim.fn.fnamemodify(path, ":e"):lower()) then
    return nil, "Choose a raster image (PNG, JPEG, GIF, WebP, BMP, TIFF, AVIF, HEIC or ICO)."
  end
  local stat = vim.uv.fs_stat(path)
  if not stat or stat.type ~= "file" or vim.fn.filereadable(path) ~= 1 then
    return nil, "Image is not a readable local file: " .. path
  end
  return path
end

local function fallback(path, reason)
  if Settings.get("images.fallback", "external") == "external" then
    vim.notify(
      "Image preview: " .. reason .. "; requesting the system viewer.",
      vim.log.levels.INFO
    )
    external(path)
  else
    notify(
      "Image preview unavailable: " .. reason .. ". Use :ImageOpen! to request the system viewer."
    )
  end
end

local function show(api, path, snapshot)
  local height = math.max(1, math.floor((vim.o.lines - vim.o.cmdheight) * 0.8))
  local lines = {}
  for _ = 1, height do
    lines[#lines + 1] = ""
  end
  local view = require("config.readonly").open(lines, {
    title = "Image: " .. vim.fs.basename(path),
    filetype = "config-image",
    footer = " q / Esc: close | e: system viewer ",
    actions = {
      e = {
        desc = "Open image in system viewer",
        run = function()
          external(path)
        end,
      },
    },
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = view.buf,
    once = true,
    callback = function()
      vim.uv.fs_unlink(snapshot)
    end,
  })
  local ok, err = pcall(function()
    return api.placement.new(view.buf, snapshot, {
      inline = false,
      auto_resize = true,
      max_width = vim.api.nvim_win_get_width(view.win),
      max_height = vim.api.nvim_win_get_height(view.win),
    })
  end)
  if not ok then
    view.close()
    error(err, 0)
  end
end

function M.open(path, force_external)
  cancel_pending()
  local file, err = path_for(path)
  if not file then
    notify(err)
    return
  end
  if force_external then return external(file) end
  local status = M.status()
  if not status.enabled then return fallback(file, "terminal rendering is disabled") end
  if not status.ui then return fallback(file, "no supported terminal UI is attached") end
  if not status.converter then return fallback(file, "ImageMagick is missing") end
  local timeout = Settings.get("images.timeout_ms", 15000)
  if type(timeout) ~= "number" or timeout < 1 or timeout > 3600000 or timeout % 1 ~= 0 then
    notify("images.timeout_ms must be an integer between 1 and 3600000.")
    return
  end
  local win, buf, cwd =
    vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf(), vim.fn.getcwd(0, 0)
  local mode = vim.api.nvim_get_mode().mode
  local ok, api = pcall(require, "snacks.image")
  if not ok or type(api) ~= "table" then
    return fallback(file, "snacks.nvim is unavailable; inspect :Lazy")
  end
  if type(api.config) == "table" and api.config.enabled == false then
    return fallback(file, "renderer is disabled by plugin options")
  end
  -- Each operation owns its job, deadline and snapshot. Old callbacks can
  -- clean up their own files without cancelling a newer preview.
  local state = {}
  local done, copying, keep_snapshot = false, false, false
  local timer, job, snapshot
  local function cleanup()
    -- A queued copy may create the file after cancellation (notably Windows).
    -- Its completion callback retries cleanup after the I/O has finished.
    if snapshot and not copying and not keep_snapshot then vim.uv.fs_unlink(snapshot) end
  end
  local function current()
    return not done
      and active == state
      and vim.api.nvim_win_is_valid(win)
      and vim.api.nvim_get_current_win() == win
      and vim.api.nvim_win_get_buf(win) == buf
      and vim.fn.getcwd(0, 0) == cwd
      and vim.api.nvim_get_mode().mode == mode
  end
  local function finish()
    done = true
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
    timer = nil
    if active == state then active = nil end
  end
  function state.cancel()
    if not done then
      finish()
      local child = job
      job = nil
      if child then pcall(function()
        child:abort()
      end) end
    end
    cleanup()
  end
  local function fail(reason)
    if done then
      cleanup()
      return
    end
    local visible = current()
    state.cancel()
    if visible then fallback(file, reason) end
  end
  local function guarded(label, callback)
    return function(...)
      local args, count = { ... }, select("#", ...)
      local function invoke()
        if done then
          cleanup()
          return
        end
        local good, failure = pcall(function()
          if not current() then
            state.cancel()
            return
          end
          callback(unpack(args, 1, count))
        end)
        if not good then fail(label .. ": " .. tostring(failure)) end
      end
      if vim.in_fast_event() then
        vim.schedule(invoke)
      else
        invoke()
      end
    end
  end
  active = state
  -- Bound all asynchronous preparation, including detection and snapshot I/O.
  timer = vim.defer_fn(function()
    fail("image preparation timed out")
  end, timeout)
  local converted = guarded("image preparation failed", function(result)
    job = nil -- completion must not abort an already completed converter
    local conversion_error = result:error()
    if conversion_error then
      return fail("image decoding failed: " .. tostring(conversion_error))
    end
    show(api, file, snapshot)
    keep_snapshot = true -- the preview's BufWipeout handler now owns cleanup
    finish()
  end)
  local copied = guarded("image preparation failed", function(copy_error)
    if copy_error then return fail("image snapshot failed: " .. tostring(copy_error)) end
    job = api.convert.convert({
      src = snapshot,
      on_done = function(result)
        vim.schedule(function()
          converted(result)
        end)
      end,
    })
    job:run()
  end)
  local detected = guarded("terminal detection failed", function()
    if not api.supports_terminal() then return fail("terminal does not support Kitty graphics") end
    -- Private, fresh names preserve literal paths and invalidate renderer caches.
    snapshot = vim.fn.tempname() .. "." .. vim.fn.fnamemodify(file, ":e"):lower()
    if vim.fs.normalize(snapshot) ~= snapshot then
      return fail("the renderer cannot preserve this temporary directory name")
    end
    copying = true
    local submitted, queued, copy_error = pcall(
      vim.uv.fs_copyfile,
      file,
      snapshot,
      function(io_error)
        vim.schedule(function()
          copying = false
          copied(io_error)
        end)
      end
    )
    if not submitted then
      copying = false
      return fail("image snapshot failed: " .. tostring(queued))
    end
    if not queued then
      copying = false
      fail("image snapshot failed: " .. tostring(copy_error))
    end
  end)
  local started, detection_error = pcall(function()
    api.terminal.detect(detected)
  end)
  if not started then fail("terminal detection failed: " .. tostring(detection_error)) end
end

function M.health()
  local h, status = vim.health, M.status()
  if not status.enabled then
    h.info(
      "Terminal image previews are disabled (images.enabled=false); :ImageOpen uses the configured fallback."
    )
    return
  end
  if status.converter then
    h.ok("ImageMagick command found: " .. status.converter)
  else
    h.warn("ImageMagick is missing; install it to enable terminal image previews.")
  end
  if not status.renderer then
    h.warn("snacks.nvim is unavailable or disabled; inspect :Lazy before retrying.")
  end
  h.info(
    "Snacks loads on demand; terminal graphics support is checked asynchronously by :ImageOpen."
  )
  if not status.ui then
    h.info("No terminal UI attached; terminal rendering will use the configured fallback.")
  end
  if status.opener then
    h.ok("System image opener found: " .. status.opener[1])
  else
    h.info(
      "No system image opener found; an external fallback needs a desktop opener/file association."
    )
  end
end

return M
