-- Explicit local-image previews. Optional renderers never own file reads,
-- document events, cwd, or the source buffer; OS viewers receive literal argv.
local M = {}
local Settings = require("config.settings")
local request = 0
local pending
local pending_timer
local formats = { "png", "jpg", "jpeg", "gif", "webp", "bmp", "tif", "tiff", "avif", "heic", "ico" }

local function notify(message)
  vim.notify(message .. " See :ConfigHelp images or :checkhealth config.", vim.log.levels.WARN)
end

local function cancel_pending()
  if pending_timer and not pending_timer:is_closing() then
    pending_timer:stop()
    pending_timer:close()
  end
  pending_timer = nil
  local job = pending
  pending = nil
  if job then pcall(function()
    job:abort()
  end) end
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
  if path:find("%c") or path:match("^[%a][%w+.-]*:") and not path:match("^%a:[/\\]") then
    return nil, "ImageOpen accepts local file paths, without control characters or URI schemes."
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
  request = request + 1
  local id = request
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
  local ok, api = pcall(require, "snacks.image")
  if not ok or type(api) ~= "table" then
    return fallback(file, "snacks.nvim is unavailable; inspect :Lazy")
  end
  if type(api.config) == "table" and api.config.enabled == false then
    return fallback(file, "renderer is disabled by plugin options")
  end
  local win, buf, cwd =
    vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf(), vim.fn.getcwd()
  local mode = vim.api.nvim_get_mode().mode
  local finished = false
  local function current()
    return not finished
      and id == request
      and vim.api.nvim_win_is_valid(win)
      and vim.api.nvim_get_current_win() == win
      and vim.api.nvim_win_get_buf(win) == buf
      and vim.fn.getcwd() == cwd
      and vim.api.nvim_get_mode().mode == mode
  end
  local function fail(reason)
    if not current() then return end
    finished = true
    cancel_pending()
    fallback(file, reason)
  end
  -- Detection and conversion are asynchronous. A stale callback must not
  -- steal focus or launch an external application in a new editing context.
  local detected, detection_error = pcall(function()
    api.terminal.detect(function()
      if not current() then return end
      local supported, support_error = pcall(api.supports_terminal)
      if not supported then
        return fail("terminal detection failed: " .. tostring(support_error))
      end
      if not support_error then return fail("terminal does not support Kitty graphics") end
      -- A fresh, private snapshot preserves literal names (#page=, $NAME) and
      -- avoids the renderer reusing stale path-based caches after a file edit.
      local snapshot = vim.fn.tempname() .. "." .. vim.fn.fnamemodify(file, ":e"):lower()
      local function cleanup()
        vim.uv.fs_unlink(snapshot)
      end
      if vim.fs.normalize(snapshot) ~= snapshot then
        return fail("the renderer cannot preserve this temporary directory name")
      end
      vim.uv.fs_copyfile(file, snapshot, function(copy_error)
        vim.schedule(function()
          if not current() then
            cleanup()
            return
          end
          if copy_error then
            cleanup()
            return fail("image snapshot failed: " .. tostring(copy_error))
          end
          local prepared, preparation_error = pcall(function()
            pending = api.convert.convert({
              src = snapshot,
              on_done = function(result)
                vim.schedule(function()
                  if finished then return end
                  if id ~= request then
                    cleanup()
                    return
                  end
                  pending = nil
                  cancel_pending()
                  if not current() then
                    cleanup()
                    return
                  end
                  local shown, show_error = pcall(function()
                    if result:error() then
                      cleanup()
                      return fail("image decoding failed: " .. tostring(result:error()))
                    end
                    show(api, file, snapshot)
                    finished = true
                  end)
                  if not shown then
                    cleanup()
                    fail("renderer failed: " .. tostring(show_error))
                  end
                end)
              end,
            })
            pending_timer = vim.defer_fn(function()
              if id ~= request then return end
              local visible = current()
              request = request + 1
              cancel_pending()
              cleanup()
              if visible then fallback(file, "image conversion timed out") end
            end, timeout)
            pending:run()
          end)
          if not prepared then
            cancel_pending()
            cleanup()
            fail("image preparation failed: " .. tostring(preparation_error))
          end
        end)
      end)
    end)
  end)
  if not detected then fail("terminal detection failed: " .. tostring(detection_error)) end
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
