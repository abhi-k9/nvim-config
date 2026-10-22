-- lua/scoper/path.lua
--
-- Cross-platform path utilities.
--
-- Path quirks this module handles:
--   * Windows backslashes  ─ "C:\foo\bar"            → "c:/foo/bar"
--   * Windows drive case   ─ "C:/foo" vs "c:/foo"    → both compare equal
--   * Device prefixes      ─ "\\?\C:\foo"            → "c:/foo"
--                            "\\?\UNC\srv\share\x"   → "//srv/share/x"
--   * Root-relative        ─ "\src" (Windows)        → "<drive of base>/src"
--   * Drive-relative       ─ "C:foo" (Windows)       → "<base>/foo" on the base's drive
--   * Tilde expansion      ─ "~/foo"                 → "/home/me/foo"
--   * Trailing slashes     ─ "/foo/"                 → "/foo" (but "/" kept)
--   * Symlinks             ─ NOT resolved by default (matches logical paths;
--                            avoids exploding on node_modules symlink farms)
--   * UNC paths            ─ "\\server\share\foo"    → "//server/share/foo"
--
-- All public functions return forward-slash paths regardless of OS, which is
-- what Neovim's own APIs use internally and what plugins like Telescope expect.

local M = {}

-- ---------------------------------------------------------------------------
-- OS detection. Cached once because uname() is a syscall. Specs flip it to
-- run the Windows rules on every OS, so everything below reads this flag
-- (and passes it to vim.fs.normalize) instead of asking the OS again.
-- ---------------------------------------------------------------------------
M.is_windows = vim.uv.os_uname().sysname:match("Windows") ~= nil

-- ---------------------------------------------------------------------------
-- The global working directory (`:cd`), not the window or tab one (`:lcd`,
-- `:tcd`) the process happens to be in: scoper keeps one state per project
-- and follows `:cd` only.
-- ---------------------------------------------------------------------------
function M.cwd()
  return vim.fn.getcwd(-1, -1)
end

-- ---------------------------------------------------------------------------
-- Normalize a single path to canonical form. vim.fs.normalize does the
-- work (~ expansion, backslash → slash, "." / ".." collapse, redundant
-- slashes, device and UNC prefix parsing); on top of it:
--   * Windows device prefixes are dropped: //?/C:/x → c:/x, //?/UNC/s/x → //s/x
--   * the drive letter is lower-cased on Windows
--   * a trailing separator is stripped (except for a root)
--
-- Environment variables are expanded only with `opts.expand_env` (user
-- input). Compile-database and picker paths are taken literally, so a real
-- folder named `$FOO` stays itself.
--
-- Does NOT touch the filesystem (no stat, no realpath). Pure string work.
-- ---------------------------------------------------------------------------
function M.normalize(path, opts)
  if not path or path == "" then return "" end

  path = vim.fs.normalize(path, {
    expand_env = (opts and opts.expand_env) == true,
    win = M.is_windows,
  })

  if M.is_windows then
    path = path:gsub("^//[?.]/[Uu][Nn][Cc]/", "//"):gsub("^//[?.]/(%a:)", "%1")
    -- vim.fs.normalize upper-cases the drive letter. Keep it lower-case:
    -- state files of existing projects are found by a hash of this form
    -- (state.legacy_store_path), and stored absolute includes use it.
    path = path:gsub("^%a:", string.lower)
  end

  -- Strip trailing slash, but preserve roots:
  --   "/"      → "/"
  --   "c:/"    → "c:/"
  --   "/foo/"  → "/foo"
  if #path > 1 and path:sub(-1) == "/" then
    local is_drive_root = M.is_windows and path:match("^%a:/$") ~= nil
    if not is_drive_root then path = path:sub(1, -2) end
  end

  return path
end

-- ---------------------------------------------------------------------------
-- Is this (normalized) path absolute? Unix: "/x". Windows: "c:/x" or a UNC
-- "//server/x"; a lone "/x" there is relative to the current drive and
-- "c:x" to that drive's current directory, so neither counts.
-- ---------------------------------------------------------------------------
function M.is_absolute(path)
  if not path or path == "" then return false end
  if M.is_windows then return path:match("^%a:/") ~= nil or path:sub(1, 2) == "//" end
  return path:sub(1, 1) == "/"
end

-- ---------------------------------------------------------------------------
-- Comparison form. Windows filesystems are case-insensitive (on NTFS by
-- default) but case-PRESERVING — so we keep the original case in storage
-- and compare lower-cased. On Unix we compare as-is.
-- ---------------------------------------------------------------------------
local function cmp_key(s)
  if M.is_windows then
    return s:lower()
  else
    return s
  end
end

-- Identity of a path for equality / dedupe / hashing: normalized, and
-- lower-cased on Windows (NTFS is case-insensitive), so "Src" and "src",
-- or "C:/Proj" and "c:/proj", are the same entry there.
function M.key(path)
  return cmp_key(M.normalize(path))
end

-- Comparison form of a path that is already normalized (cheaper than key()
-- in loops that normalized once).
M.fold = cmp_key

-- Drive ("c:") or UNC share ("//srv/share") a normalized Windows path is
-- rooted in, or "" for none.
local function win_root(path)
  return path:match("^%a:") or path:match("^//[^/]+/[^/]+") or ""
end

-- Current directory of `drive` ("d:"), for drive-relative "d:foo". Only
-- Windows keeps one per drive; with the Windows rules forced on another OS
-- (specs) the drive root stands in.
function M._drive_cwd(drive)
  if vim.fn.has("win32") == 1 then
    local ok, dir = pcall(vim.fs.abspath, drive .. ".")
    if ok then return M.normalize(dir) end
  end
  return drive .. "/"
end

-- ---------------------------------------------------------------------------
-- Make `path` absolute. If it's relative, resolve against `base` (the
-- global cwd by default). Returns a normalized path. `opts` goes to
-- normalize() for `path` (expand_env for user input).
--
-- vim.fs.abspath can't do this alone: it only resolves against the process
-- cwd, and leaves a root-relative "/src" without a drive.
-- ---------------------------------------------------------------------------
function M.absolute(path, base, opts)
  if not path or path == "" then return "" end
  local norm = M.normalize(path, opts)
  if M.is_absolute(norm) then return norm end
  base = M.normalize(base or M.cwd())
  if M.is_windows then
    if norm:sub(1, 1) == "/" then return win_root(base) .. norm end
    local drive, rest = norm:match("^(%a:)(.*)$")
    if drive then
      if drive ~= win_root(base) then return M.normalize(M._drive_cwd(drive) .. "/" .. rest) end
      if rest == "" then return base end
      norm = rest
    end
  end
  return M.normalize(base .. "/" .. norm)
end

-- ---------------------------------------------------------------------------
-- True iff `child` is `parent` or a descendant of `parent`. Both paths are
-- normalized inside; callers don't need to pre-normalize.
--
-- On Windows the comparison is case-insensitive (the filesystem is too).
-- The "+ '/'" check is important: without it, "/foo" would match "/foobar"
-- as a child of "/foo", which is wrong.
-- ---------------------------------------------------------------------------

-- Membership test is "child starts with parent + separator". A normal
-- parent has its trailing slash stripped by normalize(), so we add one
-- back to form the boundary. But a filesystem root ("/" on Unix, "c:/"
-- on Windows) KEEPS its trailing slash — appending another would make
-- the boundary "//" (or "c://") and no real child would ever match it.
-- Reuse the existing slash in that case.
local function boundary(p)
  return (p:sub(-1) == "/") and p or (p .. "/")
end

-- is_under() for two paths already in key form (see M.key / M.fold).
function M.key_under(c, p)
  if p == "" then return false end
  if c == p then return true end
  local b = boundary(p)
  return c:sub(1, #b) == b
end

function M.is_under(child, parent)
  return M.key_under(M.key(child), M.key(parent))
end

-- ---------------------------------------------------------------------------
-- Convert an absolute path to one relative to `base`. If `path` is not under
-- `base`, returns the original (normalized) absolute path.
-- ---------------------------------------------------------------------------
function M.relative(path, base)
  path = M.normalize(path)
  base = M.normalize(base or M.cwd())
  local c, p = cmp_key(path), cmp_key(base)
  if not M.key_under(c, p) then return path end
  if c == p then return "." end
  return path:sub(#boundary(p) + 1)
end

-- True if `s` uses glob syntax (an include that is a pattern, not a dir).
function M.is_glob(s)
  return s:find("[%*%?%[{]") ~= nil
end

-- ---------------------------------------------------------------------------
-- Glob matching via vim.glob (lpeg-based, supports **, *, ?, [...], {a,b}).
-- Patterns are compiled once and cached because lpeg compilation isn't free.
--
-- Cache semantics:
--   not present in cache → never tried
--   value == false       → failed to compile (warned once); never matches
--   value is a matcher   → use it
--
-- (The lookup gates on `nil`, not falsiness, so a failed compile isn't
-- retried on every call.)
--
-- On Windows both sides are lower-cased: the filesystem is
-- case-insensitive, so `**/Build/**` must exclude `build/`. (Lower-casing
-- the pattern is safe — glob syntax has no letters with meaning.)
-- ---------------------------------------------------------------------------
local glob_cache = {}
-- vim.glob rejects the empty segment at the start of a UNC path. Compile
-- that one separator away, then require and remove the same UNC prefix from
-- the subject. This keeps UNC patterns distinct from ordinary /root globs.
local function glob_source(pattern)
  return pattern:sub(1, 2) == "//" and pattern:sub(2) or pattern
end

local function compiled(pattern)
  local matcher = glob_cache[pattern]
  if matcher == nil then
    local ok, m = pcall(vim.glob.to_lpeg, glob_source(pattern))
    matcher = ok and m or false
    if ok and pattern:sub(1, 2) == "//" then
      matcher = {
        match = function(_, path)
          if path:sub(1, 2) == "//" then return m:match(path:sub(2)) end
        end,
      }
    end
    glob_cache[pattern] = matcher
    if not ok then
      vim.notify(("Scoper: invalid glob %q is ignored"):format(pattern), vim.log.levels.WARN)
    end
  end
  return matcher
end

-- True if `pattern` is an exclude the matchers below can use: vim.glob
-- parses it, and the forms exclude_matcher derives from it (trailing or
-- leading slashes removed).
function M.valid_glob(pattern)
  if not pattern:find("[^/]") then return false end
  for _, p in ipairs({ pattern, (pattern:gsub("/+$", "")), (pattern:gsub("^/+", "")) }) do
    if not pcall(vim.glob.to_lpeg, glob_source(p)) then return false end
  end
  return true
end

-- Include globs: tested against the absolute path and the cwd-relative
-- form, so "**/*.proto" and "src/**/*.proto" both work.
function M.match_glob(path, pattern, cwd)
  local matcher = compiled(cmp_key(pattern))
  if matcher == false then return false end
  path = cmp_key(path)
  if matcher:match(path) ~= nil then return true end
  local rel = M.relative(path, cwd)
  if rel ~= path and matcher:match(cmp_key(rel)) ~= nil then return true end
  return false
end

-- ---------------------------------------------------------------------------
-- Exclude matching with the SAME semantics ripgrep (`--glob=!pat`) and fd
-- (`--exclude pat`) apply in the pickers — gitignore-style, relative to
-- the directory being searched:
--   * a pattern without "/" (`build`, `*.o`, `node_modules`) matches any
--     single path component at any depth, so it excludes a directory of
--     that name together with everything below it;
--   * a pattern with "/" (`src/gen`, `**/gen/**`) matches the relative
--     path or one of its leading directories;
--   * a trailing "/" (`build/`) is accepted and means the same as `build`;
--   * a leading "/" (`/build`) anchors the pattern at the search root, as
--     in gitignore; on Unix it may also be an absolute path;
--   * a drive or UNC pattern (`c:/proj/vendor/**`) matches the absolute
--     path or one of its ancestors.
--
-- Relative patterns never see the part of the path above the search root:
-- with the project in `d:/build/proj`, `**/build/**` must not exclude it.
--
-- exclude_matcher compiles a pattern once and returns
-- fn(abs_key, rel_key) → bool (both in M.fold form, rel relative to the
-- search root), or nil for a pattern that can never match.
-- ---------------------------------------------------------------------------

-- The relative path itself, then each leading directory of it — or, for a
-- slashless unanchored pattern, each single component.
local function rel_matcher(pat, anchored)
  local trimmed = pat:gsub("/+$", "")
  if trimmed == "" then return nil end
  local full, part = compiled(pat), compiled(trimmed)
  if full == false or part == false then return nil end
  local slashless = not anchored and not trimmed:find("/", 1, true)
  return function(rel)
    if full:match(rel) ~= nil then return true end
    local prefix
    for seg in rel:gmatch("[^/]+") do
      prefix = prefix and (prefix .. "/" .. seg) or seg
      if part:match(slashless and seg or prefix) ~= nil then return true end
    end
    return false
  end
end

-- The absolute path itself, or one of its ancestors.
local function abs_matcher(pat)
  local trimmed = pat:gsub("/+$", "")
  if trimmed == "" then return nil end
  local full, part = compiled(pat), compiled(trimmed)
  if full == false or part == false then return nil end
  return function(abs)
    if full:match(abs) ~= nil or part:match(abs) ~= nil then return true end
    local i = 1
    while true do
      i = abs:find("/", i + 1, true)
      if not i then return false end
      if part:match(abs:sub(1, i - 1)) ~= nil then return true end
    end
  end
end

function M.exclude_matcher(pattern)
  local pat = cmp_key(pattern)
  if pat:match("^%a:") or pat:sub(1, 2) == "//" then
    local abs = abs_matcher(pat)
    return abs and function(a)
      return abs(a)
    end
  end
  if pat:sub(1, 1) == "/" then
    local abs, rel = abs_matcher(pat), rel_matcher((pat:gsub("^/+", "")), true)
    if not (abs or rel) then return nil end
    return function(a, r)
      return (abs ~= nil and abs(a)) or (rel ~= nil and rel(r))
    end
  end
  local rel = rel_matcher(pat, false)
  return rel and function(_, r)
    return rel(r)
  end
end

-- One-off form of exclude_matcher: does `path` match exclude `pattern`
-- when searching from `base` (cwd by default)?
function M.match_exclude(path, pattern, base)
  local matcher = M.exclude_matcher(pattern)
  if not matcher then return false end
  return matcher(cmp_key(M.normalize(path)), cmp_key(M.relative(path, base)))
end

-- ---------------------------------------------------------------------------
-- Check whether a path resolves to a directory. Used by :ScoperAdd to warn
-- on typos and by active_dirs() to filter include entries.
--
-- Uses vim.uv.fs_stat which DOES follow symlinks: if a scope includes
-- `vendored -> ../shared`, that's a directory as far as Scoper is
-- concerned. (Logical-not-resolved matching applies to glob exclusion
-- against scope members — not to existence checks.)
-- ---------------------------------------------------------------------------
function M.is_dir(path)
  local stat = vim.uv.fs_stat(path)
  return stat ~= nil and stat.type == "directory"
end

return M
