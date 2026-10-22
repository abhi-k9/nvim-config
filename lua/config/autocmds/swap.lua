-- lua/config/autocmds/swap.lua
--
-- Swap-file handling: the SwapExists guard (:SwapGuardToggle), :SwapDelete
-- and :SwapClean.

local augroup = require("config.util").augroup

local M = {}

-- A confirmation can stay open while another editor creates, replaces or
-- updates a swap. Compare both identity and contents' metadata afterward;
-- checking only the inode misses an in-place update of recovery data.
local function same_swap_file(before, after)
  return before
    and after
    and before.type == "file"
    and after.type == "file"
    and before.dev == after.dev
    and before.ino == after.ino
    and before.size == after.size
    and before.mtime.sec == after.mtime.sec
    and before.mtime.nsec == after.mtime.nsec
end

-- Neovim stores at most 39 hostname bytes in the swap header and compares
-- them case-insensitively. A PID is meaningful only on that same host;
-- a shared state directory may contain a swap from a running remote editor.
local function local_swap_host(info)
  return type(info.host) == "string"
    and info.host ~= ""
    and info.host:lower() == vim.fn.hostname():sub(1, 39):lower()
end

local function swap_host(info)
  return type(info.host) == "string" and info.host ~= "" and info.host or "unknown host"
end

local function live_owner(info)
  if not local_swap_host(info) then return nil end
  local pid = type(info.pid) == "number" and info.pid or 0
  return pid > 0 and vim.uv.kill(pid, 0) == 0 and pid or nil
end

-- ---------------------------------------------------------------------------
-- SwapExists: make swap collisions livable now that 'swapfile' is on.
--
--   * Owner process still RUNNING (probed with uv.kill(pid, 0), which works
--     on Windows too): the file is open in another live Neovim. Open it
--     read-only ("o") and say how to take over (:e!).
--   * Owner DEAD: a crash leftover — recover vs delete is the user's call,
--     so show a concise one-line confirm() instead of the ~17-line E325
--     wall.
--   * Swap UNREADABLE (empty, cut short, from an incompatible Vim): an
--     empty one older than a minute holds nothing and is deleted; any other
--     is left alone and the file opens read-only, with a notice naming the
--     swap. Never the stock prompt: inside a session restore its E325 is an
--     error that aborts the restore.
--   * A different USER's swap always gets the stock prompt.
--
-- This REPLACES core's handler (augroup "nvim.swapfile"), which answers a
-- live same-user owner with "e" (edit anyway) — i.e. no protection against
-- two instances clobbering each other, the reason swap is on at all.
--
-- `vim.g.swap_guard = false` / :SwapGuardToggle (read at event time)
-- restores exactly what Neovim would do: "e" + W325 warning for a live
-- owner, the stock prompt for leftovers and unreadable swaps. Notifications
-- are scheduled because the buffer isn't usable yet when SwapExists fires.
-- ---------------------------------------------------------------------------
-- Default ON; `== nil` so an explicit false set earlier is respected.
if vim.g.swap_guard == nil then vim.g.swap_guard = true end

pcall(vim.api.nvim_del_augroup_by_name, "nvim.swapfile")
vim.api.nvim_create_autocmd("SwapExists", {
  group = augroup("swap_collision"),
  callback = function(args)
    local info = vim.fn.swapinfo(vim.v.swapname)
    local user = vim.uv.os_get_passwd().username
    local iswin = vim.fn.has("win32") == 1

    -- A DIFFERENT user's swap on a shared file: we shouldn't presume. Fall
    -- back to Vim's stock prompt untouched, in BOTH guard modes. (Same-user
    -- check mirrors core's; Windows swaps don't record a comparable user,
    -- hence the has("win32") exemption, as core also does it.)
    if not info.error and not iswin and info.user and info.user ~= user then return end

    -- Unreadable swap: swapinfo() knows no owner, state or file name. Guard
    -- OFF → stock prompt. Guard ON → never the stock prompt, which a
    -- session restore can't survive. An empty swap more than a minute old
    -- holds nothing, and no Nvim is still creating it: delete it. Anything
    -- else might hold something, so keep it and open read-only; remember
    -- it for :SwapDelete, whose scan can't match a swap it can't read.
    if info.error then
      if vim.g.swap_guard == false then return end
      local swap, buf = vim.v.swapname, args.buf
      local file = vim.fn.fnamemodify(args.file, ":t")
      local st = vim.uv.fs_stat(swap)
      if st and st.size == 0 and os.time() - st.mtime.sec > 60 then
        vim.v.swapchoice = "d"
        vim.schedule(function()
          vim.notify(("Deleted an empty swap file for %s."):format(file), vim.log.levels.INFO)
        end)
        return
      end
      vim.v.swapchoice = "o"
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then vim.b[buf].swap_unreadable = swap end
        vim.notify(
          ("%s: its swap file can't be read (%s) — opened READ-ONLY.\n:SwapDelete removes the swap, then :e! to edit.\n  %s"):format(
            file,
            info.error,
            swap
          ),
          vim.log.levels.WARN
        )
      end)
      return
    end

    if not local_swap_host(info) then
      if vim.g.swap_guard == false then return end
      vim.v.swapchoice = "o"
      local host = swap_host(info)
      vim.schedule(function()
        vim.notify(
          ("Swap owner is on %s; its process cannot be checked here — opened READ-ONLY.\nVerify that editor is closed before taking over or deleting its swap."):format(
            host
          ),
          vim.log.levels.WARN
        )
      end)
      return
    end

    -- Is a LIVE process holding this swap right now? A pid must be a real
    -- positive number before probing: Lua treats 0 as truthy and
    -- uv.kill(0, 0) signals the caller's OWN process group (always
    -- "succeeds"), so a swap recording pid 0 — exactly what a crash
    -- leftover reports, since swapinfo only records a pid for a still-
    -- running owner — would masquerade as live. Signal 0 checks existence
    -- without signaling, and libuv implements it on Windows too.
    local live = type(info.pid) == "number" and info.pid > 0 and vim.uv.kill(info.pid, 0) == 0

    if live then
      -- Another live Nvim owns the swap (two instances on one file).
      if vim.g.swap_guard == false then
        -- Guard OFF → faithful replica of core's deleted default:
        -- edit anyway, one-line warning.
        vim.v.swapchoice = "e"
        vim.schedule(function()
          vim.notify(
            ("W325: Ignoring swapfile from Nvim process %d"):format(info.pid),
            vim.log.levels.WARN
          )
        end)
        return
      end
      -- Guard ON (default) → protect: open read-only, explain, and say
      -- how to take over.
      vim.v.swapchoice = "o"
      local pid, file = info.pid, vim.fn.fnamemodify(args.file, ":t")
      vim.schedule(function()
        vim.notify(
          ("%s is open in another Neovim (pid %d) — opened READ-ONLY here.\nClose it there, then :e! to take over."):format(
            file,
            pid
          ),
          vim.log.levels.WARN
        )
      end)
      return
    end

    -- No live owner → crash leftover. Recover-vs-delete is a real decision
    -- about possibly-unsaved work, so we never decide it silently. Guard
    -- OFF reproduces stock Nvim exactly (empty swapchoice → the full E325
    -- recovery prompt). Guard ON offers the SAME choices as a single-line
    -- confirm() instead of the ~17-line ATTENTION block — which is the
    -- "tons of messages" pile-up when several crash-leftover files open at
    -- once. confirm() is synchronous, exactly what SwapExists needs (the
    -- choice must be made before the open proceeds), and it renders fine
    -- this early, unlike nvim-notify.
    if vim.g.swap_guard == false then return end
    local file = vim.fn.fnamemodify(args.file, ":t")
    -- The default button follows the swap's state: Delete when it holds no
    -- unsaved changes; Open read-only when the file on disk was written
    -- after the swap (recovering would replay older text over newer
    -- edits); otherwise Recover. Esc/0 → "q" (quit): never edit or delete
    -- on an accidental dismiss.
    local newer = vim.fn.getftime(args.match) > vim.fn.getftime(vim.v.swapname)
    local detail, default
    if info.dirty ~= 1 then
      detail, default = "The swap has no unsaved changes; it is safe to Delete.", 4
    elseif newer then
      detail, default =
        "The swap HAS unsaved changes, but the file on disk is NEWER than the swap.\n"
          .. "Open read-only and compare before you Recover.",
        2
    else
      detail, default = "The swap HAS unsaved changes; Recover to restore them.", 1
    end
    local choice = vim.fn.confirm(
      ("Swap file found for '%s' — a previous edit session may have crashed.\n%s"):format(
        file,
        detail
      ),
      "&Recover\n&Open read-only\n&Edit anyway\n&Delete swap\n&Quit",
      default,
      "Question"
    )
    vim.v.swapchoice = ({ [1] = "r", [2] = "o", [3] = "e", [4] = "d", [5] = "q" })[choice] or "q"
  end,
})

-- Runtime toggle. Affects the NEXT file open that hits a collision;
-- already-open read-only buffers stay read-only until you :e! them
-- (flipping a flag should not silently promote existing buffers to
-- writable — take-over stays an explicit act).
vim.api.nvim_create_user_command("SwapGuardToggle", function()
  vim.g.swap_guard = not vim.g.swap_guard
  vim.notify(
    "Swap collision guard: "
      .. (
        vim.g.swap_guard and "ON — files open in another Neovim load read-only"
        or "OFF — stock Neovim behavior (edit anyway + W325 warning)"
      ),
    vim.log.levels.INFO
  )
end, { desc = "Toggle read-only guard for files open in another Neovim" })

-- ---------------------------------------------------------------------------
-- :SwapDelete — remove a swap file without hunting down its on-disk path.
--
-- No argument → the swap(s) belonging to the CURRENT buffer. With an
-- argument → that explicit swap-file path, so a leftover can be cleared
-- without opening the file it belongs to. (The path is taken literally;
-- see the note on completion at the command definition below.)
--
-- Resolving the current buffer's swap is trickier than it looks:
-- vim.fn.swapname() returns "" for a buffer that was opened OVER an
-- existing swap (Edit-anyway / Open-read-only / Recover all leave
-- swapname empty), which is exactly the crash-leftover case this command
-- is for. So we don't trust swapname alone — we scan the 'directory'
-- swap dirs and match each swap's RECORDED file name (swapinfo().fname)
-- against the buffer's path. That's naming-scheme agnostic (handles the
-- dir// mangling and .swo/.swn collision generations) and cross-platform.
--
-- Deleting a swap is destructive, so we ALWAYS: (1) show the exact
-- path(s) and what we know about each, (2) require a confirm() that
-- defaults to Cancel, and (3) flatly refuse any swap a DIFFERENT live
-- Nvim is actively using — that instance needs it, and removing it
-- invites the very clobbering the guard exists to prevent. Deleting THIS
-- session's own swap, or a genuine crash leftover, is allowed.
-- ---------------------------------------------------------------------------
do
  -- Decode the stored 'directory' option like Neovim's copy_option_part().
  -- Only a backslash immediately before a comma is removed; other
  -- backslashes (including Windows/UNC separators) are literal. Even two
  -- backslashes before a comma still quote that comma, retaining one slash.
  -- :set's own escaping has already happened before we read vim.o.directory.
  local function directory_entries()
    local value, entries, pos = vim.o.directory, {}, 1
    while pos <= #value do
      local chars = {}
      while pos <= #value and value:sub(pos, pos) ~= "," do
        if value:sub(pos, pos + 1) == "\\," then pos = pos + 1 end
        chars[#chars + 1] = value:sub(pos, pos)
        pos = pos + 1
      end
      entries[#entries + 1] = table.concat(chars)
      pos = pos + 1 -- separating comma, if any
      while value:sub(pos, pos) == " " do
        pos = pos + 1
      end
    end
    return entries
  end

  -- Swap files record a path under your home folder as `~user/…`
  -- (:h usr_11.txt), and vim.fs.normalize expands only a bare leading `~`,
  -- so the `~user` prefix is expanded first. $HOME, not uv.os_homedir():
  -- Neovim abbreviates with $HOME, while libuv prefers USERPROFILE on
  -- Windows.
  local function expand_home(p)
    local user = vim.pesc(vim.uv.os_get_passwd().username)
    local rest = p:match("^~" .. user .. "([/\\].*)$") or p:match("^~([/\\].*)$")
    return rest and ((vim.env.HOME or vim.uv.os_homedir()) .. rest) or p
  end

  local function norm(p)
    p = vim.fs.normalize(expand_home(p or ""))
    if vim.fn.has("win32") == 1 then p = p:lower() end
    return p
  end

  -- Every swap in the 'directory' dirs whose recorded fname is this path.
  local function swaps_for(path)
    local want, found = norm(path), {}
    for _, dir in ipairs(directory_entries()) do
      -- 'directory' semantics: "." (or "./sub") is relative to the EDITED
      -- FILE's directory, not the cwd; "~" and $VARs are expanded.
      if dir == "." or dir:match("^%.[/\\]") then dir = vim.fs.dirname(path) .. dir:sub(2) end
      if dir == "" then dir = vim.fn.getcwd() end
      dir = vim.fs.normalize(dir, { expand_env = true })
      dir = dir:gsub("[/\\]+$", "") -- drop the dir// trailing slashes
      local h = vim.uv.fs_scandir(dir)
      while h do
        local name, t = vim.uv.fs_scandir_next(h)
        if not name then break end
        if t ~= "directory" and name:match("%.sw[a-z]$") then
          local full = dir .. "/" .. name
          local ok, info = pcall(vim.fn.swapinfo, full)
          if
            ok
            and type(info) == "table"
            and not info.error
            and info.fname
            and norm(info.fname) == want
          then
            found[#found + 1] = full
          end
        end
      end
    end
    return found
  end

  vim.api.nvim_create_user_command("SwapDelete", function(cmd)
    local targets
    if cmd.args ~= "" then
      -- NOTE: not vim.fn.expand() — a swap path is full of '%' from the
      -- dir// mangling, and expand() would treat each '%' as "current
      -- file name". vim.fs.normalize handles '~'; ':p' makes it absolute.
      targets = { vim.fn.fnamemodify(vim.fs.normalize(cmd.args), ":p") }
    else
      local path = vim.api.nvim_buf_get_name(0)
      if path == "" then
        vim.notify("SwapDelete: this buffer has no file name.", vim.log.levels.INFO)
        return
      end
      targets = swaps_for(path)
      -- swapname() can still name one the scan missed (e.g. a swap dir not
      -- in 'directory'), and the scan skips the unreadable swap the guard
      -- opened this buffer over; fold them in.
      -- ("%": like bufname(), swapname(0) means the alternate buffer.)
      for _, sn in ipairs({ vim.fn.swapname("%"), vim.b.swap_unreadable or "" }) do
        if sn ~= "" and vim.uv.fs_stat(sn) and not vim.tbl_contains(targets, sn) then
          targets[#targets + 1] = sn
        end
      end
    end

    -- Classify each existing swap. Foreign-live → refuse. This session's
    -- OWN active swap is not a leftover, so no-arg mode leaves it in place
    -- (it is cleaned on exit anyway, and it is the buffer's live crash
    -- protection); an explicit path still deletes it if that is what the
    -- user pointed at.
    --
    -- An explicit path is only taken if it IS a swap: a regular file (not
    -- a link or folder) named *.sw? with a header swapinfo() can read. An
    -- unreadable one needs the bang, so a mistyped path can't delete an
    -- ordinary file. No-arg targets come from the scan, swapname() or the
    -- guard, which already know them to be swaps.
    local explicit = cmd.args ~= ""
    local mypid, deletable, lines, own_skipped = vim.fn.getpid(), {}, {}, {}
    local stats = {}
    for _, swap in ipairs(targets) do
      local st = vim.uv.fs_lstat(swap)
      local info = st and st.type == "file" and vim.fn.swapinfo(swap) or {}
      local refuse
      if not st then
        refuse = explicit and "no such file"
      elseif st.type ~= "file" then
        refuse = ("not a regular file (%s)"):format(st.type)
      elseif not vim.fs.basename(swap):match("%.sw[a-z]$") then
        refuse = "not a swap file name (*.swp, *.swo, …)"
      elseif info.error and explicit and not cmd.bang then
        refuse = ("unreadable as a swap file (%s); :SwapDelete! %s deletes it anyway"):format(
          info.error,
          swap
        )
      elseif not info.error and not local_swap_host(info) and not (explicit and cmd.bang) then
        refuse = ("owner on %s cannot be checked here; verify that editor is closed, then use :SwapDelete! %s"):format(
          swap_host(info),
          swap
        )
      end
      if refuse then
        vim.notify(("SwapDelete: refusing\n  %s\n%s"):format(swap, refuse), vim.log.levels.WARN)
      elseif st then
        stats[swap] = st
        local pid = (type(info.pid) == "number") and info.pid or 0
        local local_host = local_swap_host(info)
        local own = local_host and pid > 0 and pid == mypid
        local live_other = local_host and pid > 0 and not own and vim.uv.kill(pid, 0) == 0
        if live_other then
          vim.notify(
            ("SwapDelete: skipping — in use by another running Neovim (pid %d):\n  %s\nClose that instance first."):format(
              pid,
              swap
            ),
            vim.log.levels.WARN
          )
        elseif own and not explicit then
          own_skipped[#own_skipped + 1] = swap
        else
          deletable[#deletable + 1] = swap
          lines[#lines + 1] = info.error and ("  %s\n    (unreadable: %s)"):format(swap, info.error)
            or ("  %s\n    (%s; %s)"):format(
              swap,
              not local_host and ("owner on " .. swap_host(info) .. "; liveness UNKNOWN")
                or (own and "owned by THIS Neovim session" or "crash leftover / no live owner"),
              info.dirty == 1 and "HAS unsaved changes (will be lost)" or "no unsaved changes"
            )
        end
      end
    end

    if #deletable == 0 then
      if #own_skipped > 0 then
        vim.notify(
          ("SwapDelete: no leftover swap for this buffer — only this session's own active swap, left in place (auto-removed on exit):\n  %s"):format(
            table.concat(own_skipped, "\n  ")
          ),
          vim.log.levels.INFO
        )
      else
        vim.notify("SwapDelete: no swap file to delete for this buffer.", vim.log.levels.INFO)
      end
      return
    end

    local choice = vim.fn.confirm(
      ("Delete %d swap file%s?\n%s"):format(
        #deletable,
        #deletable == 1 and "" or "s",
        table.concat(lines, "\n")
      ),
      "&Delete\n&Cancel",
      2,
      "Question"
    )
    if choice ~= 1 then
      vim.notify("SwapDelete: cancelled.", vim.log.levels.INFO)
      return
    end

    local removed = 0
    for _, swap in ipairs(deletable) do
      -- Re-check right before deleting: the confirm() may have sat open
      -- while the path was replaced.
      local st, before = vim.uv.fs_lstat(swap), stats[swap]
      local ok, err = false, "changed since it was checked; not deleted"
      if same_swap_file(before, st) then
        local info = vim.fn.swapinfo(swap)
        local owner = live_owner(info)
        -- vim.uv.fs_unlink reports failure by RETURNING nil, err (it does
        -- not throw), so the return value is checked — a pcall would see
        -- every failure as success.
        if not info.error and not local_swap_host(info) and not (explicit and cmd.bang) then
          err = "owner is on another or unknown host; not deleted"
        elseif owner and owner ~= mypid then
          err = "now in use by another running Neovim; not deleted"
        else
          ok, err = vim.uv.fs_unlink(swap)
        end
      end
      if ok then
        removed = removed + 1
      else
        vim.notify(
          ("SwapDelete: failed to remove\n  %s\n%s"):format(swap, tostring(err)),
          vim.log.levels.ERROR
        )
      end
    end
    if removed > 0 then
      vim.notify(
        ("SwapDelete: removed %d swap file%s."):format(removed, removed == 1 and "" or "s"),
        vim.log.levels.INFO
      )
    end
  end, {
    nargs = "?",
    bang = true,
    -- No complete="file": file completion makes Nvim expand '%' (and '#')
    -- in the argument to the current file name BEFORE the callback runs,
    -- which shreds swap paths — they are ALL '%' from the dir// mangling.
    desc = "Delete the swap file(s) for the current buffer (or a given swap path; ! for an unreadable one), with confirmation",
  })

  -- -------------------------------------------------------------------------
  -- :SwapClean — review every swap in the 'directory' dirs and delete the
  -- leftovers that can't hold lost work: no live owner and no unsaved
  -- changes, or empty and over a minute old (the guard's rule). Kept and
  -- listed: swaps of running Neovims, swaps WITH unsaved changes (recover
  -- them first) and non-empty unreadable ones. "."-relative entries in
  -- 'directory' are per edited file and can't be scanned here.
  -- -------------------------------------------------------------------------
  local function swap_dirs()
    local dirs = {}
    for _, dir in ipairs(directory_entries()) do
      if dir == "" then dir = vim.fn.getcwd() end
      if dir ~= "." and not dir:match("^%.[/\\]") then
        dir = vim.fs.normalize(dir, { expand_env = true }):gsub("[/\\]+$", "")
        dirs[#dirs + 1] = dir
      end
    end
    return dirs
  end

  -- Every swap in the scannable 'directory' dirs, classified:
  --   { swap, fname, pid, kind, error }, kind one of
  --   own · live (another running local Nvim) · remote (unknown host owner)
  --   · empty (unreadable, 0 bytes, over a
  --   minute old) · unreadable · dirty (unsaved changes) · clean.
  -- Returns the list and the dirs scanned. Also used by :DiagnosticDump.
  function M.inventory()
    local dirs = swap_dirs()
    local mypid, now, list = vim.fn.getpid(), os.time(), {}
    -- A missing or unreadable dir is skipped: there is nothing to list.
    for _, dir in ipairs(dirs) do
      local ok_dir, iter = pcall(vim.fs.dir, dir)
      if not (ok_dir and vim.uv.fs_scandir(dir)) then iter = function() end end
      for name, t in iter do
        if t ~= "directory" and name:match("%.sw[a-z]$") then
          local swap = dir .. "/" .. name
          local ok, info = pcall(vim.fn.swapinfo, swap)
          info = ok and type(info) == "table" and info or { error = "unreadable" }
          local pid = type(info.pid) == "number" and info.pid or 0
          local st = vim.uv.fs_stat(swap)
          local kind
          if not info.error and not local_swap_host(info) then
            kind = "remote"
          elseif pid > 0 and pid == mypid then
            kind = "own"
          elseif pid > 0 and vim.uv.kill(pid, 0) == 0 then
            kind = "live"
          elseif info.error then
            kind = (st and st.size == 0 and now - st.mtime.sec > 60) and "empty" or "unreadable"
          else
            kind = info.dirty == 1 and "dirty" or "clean"
          end
          list[#list + 1] = {
            swap = swap,
            fname = info.fname,
            pid = pid,
            host = info.host,
            kind = kind,
            error = info.error,
          }
        end
      end
    end
    return list, dirs
  end

  vim.api.nvim_create_user_command("SwapClean", function()
    local list, dirs = M.inventory()
    local delete, keep = {}, {}
    local stats = {}
    for _, s in ipairs(list) do
      if s.kind == "remote" then
        keep[#keep + 1] = ("  %s\n    owner on %s; liveness unknown here"):format(
          s.fname or s.swap,
          swap_host(s)
        )
      elseif s.kind == "live" then
        keep[#keep + 1] = ("  %s\n    in use by a running Neovim (pid %d)"):format(
          s.fname or s.swap,
          s.pid
        )
      elseif s.kind == "empty" then
        delete[#delete + 1] = { s.swap, ("  %s\n    empty"):format(s.swap) }
      elseif s.kind == "unreadable" then
        keep[#keep + 1] = ("  %s\n    unreadable (%s): check it, then :SwapDelete! <path>"):format(
          s.swap,
          s.error
        )
      elseif s.kind == "dirty" then
        keep[#keep + 1] = ("  %s\n    HAS unsaved changes: open the file and Recover\n    swap: %s"):format(
          s.fname or "?",
          s.swap
        )
      elseif s.kind == "clean" then
        delete[#delete + 1] = { s.swap, ("  %s\n    no unsaved changes"):format(s.fname or s.swap) }
      end
    end
    for _, d in ipairs(delete) do
      stats[d[1]] = vim.uv.fs_lstat(d[1])
    end

    local function block(title, lines)
      if #lines == 0 then return "" end
      local shown = vim.list_slice(lines, 1, 8)
      if #lines > 8 then shown[#shown + 1] = ("  … and %d more"):format(#lines - 8) end
      return ("%s (%d):\n%s\n"):format(title, #lines, table.concat(shown, "\n"))
    end
    local kept = block("Kept", keep)

    if #delete == 0 then
      local where = table.concat(dirs, ", ")
      vim.notify(
        #keep == 0 and ("SwapClean: no leftover swap files in " .. where .. ".")
          or ("SwapClean: nothing safe to delete in " .. where .. ".\n" .. kept),
        vim.log.levels.INFO
      )
      return
    end

    local choice = vim.fn.confirm(block(
      "Delete",
      vim.tbl_map(function(d)
        return d[2]
      end, delete)
    ) .. kept, ("&Delete %d\n&Cancel"):format(#delete), 2, "Question")
    if choice ~= 1 then
      vim.notify("SwapClean: cancelled.", vim.log.levels.INFO)
      return
    end
    local removed, failed = 0, {}
    for _, d in ipairs(delete) do
      local path = d[1]
      local st = vim.uv.fs_lstat(path)
      local ok, err = false, "changed since it was checked; not deleted"
      if same_swap_file(stats[path], st) then
        local info = vim.fn.swapinfo(path)
        -- A path may have become active or dirty without being replaced.
        -- Unknown/corrupt headers are safe to remove only for the original
        -- empty-and-old case, never after a formerly clean swap changed.
        local empty = info.error and st.size == 0 and os.time() - st.mtime.sec > 60
        if
          not live_owner(info)
          and (empty or (not info.error and local_swap_host(info) and info.dirty == 0))
        then
          ok, err = vim.uv.fs_unlink(path)
        else
          err = "now active, dirty or unreadable; not deleted"
        end
      end
      if ok then
        removed = removed + 1
      else
        failed[#failed + 1] = ("  %s: %s"):format(d[1], tostring(err))
      end
    end
    vim.notify(
      ("SwapClean: removed %d swap file%s.%s"):format(
        removed,
        removed == 1 and "" or "s",
        #failed > 0 and ("\nFailed:\n" .. table.concat(failed, "\n")) or ""
      ),
      #failed > 0 and vim.log.levels.WARN or vim.log.levels.INFO
    )
  end, { desc = "Review all swap files and delete the leftovers that hold no unsaved work" })
end

return M
