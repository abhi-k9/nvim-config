-- Hermetic index-content checks: fake linters reject a marker, so these
-- exercise Git/path handling rather than needing luacheck or StyLua.
local hook = vim.fn.getcwd() .. "/.githooks/pre-commit"
local git = vim.fn.exepath("git")
local dirs = {}

local function run(args, opts)
  return vim.system(args, vim.tbl_extend("force", { text = true }, opts or {})):wait()
end

local function check(path, staged, working, broken_show)
  local dir = vim.fn.tempname()
  dirs[#dirs + 1] = dir
  vim.fn.mkdir(dir .. "/bin", "p")
  assert.equals(0, run({ git, "init", "-q", dir }).code)
  local function write(relative, content)
    vim.fn.mkdir(vim.fn.fnamemodify(dir .. "/" .. relative, ":h"), "p")
    vim.fn.writefile(vim.split(content, "\n", { plain = true }), dir .. "/" .. relative)
  end
  write(path, staged)
  assert.equals(0, run({ git, "-C", dir, "add", "--", path }).code)
  if working then write(path, working) end
  for _, tool in ipairs({ "luacheck", "stylua" }) do
    write("bin/" .. tool, "#!/usr/bin/env bash\ninput=$(cat)\n[[ $input != *INVALID_LUA* ]]\n")
    vim.fn.setfperm(dir .. "/bin/" .. tool, "rwxr-xr-x")
  end
  if broken_show then
    write(
      "bin/git",
      "#!/usr/bin/env bash\nif [[ $1 == show ]]; then exit 1; fi\nexec "
        .. vim.fn.shellescape(git)
        .. ' "$@"\n'
    )
    vim.fn.setfperm(dir .. "/bin/git", "rwxr-xr-x")
  end
  local sep = vim.fn.has("win32") == 1 and ";" or ":"
  return run({ "bash", hook }, { cwd = dir, env = { PATH = dir .. "/bin" .. sep .. vim.env.PATH } })
end

describe("pre-commit staged file handling", function()
  after_each(function()
    for _, dir in ipairs(dirs) do
      vim.fn.delete(dir, "rf")
    end
    dirs = {}
  end)

  it("rejects invalid staged content with a Unicode filename", function()
    assert.equals(1, check("café.lua", "INVALID_LUA").code)
  end)

  it("rejects invalid staged content with a newline filename", function()
    if vim.fn.has("win32") == 1 then
      pending("Windows does not permit newlines in filenames")
      return
    end
    assert.equals(1, check("line\nbreak.lua", "INVALID_LUA").code)
  end)

  it("rejects invalid staged content with quotes in the filename", function()
    if vim.fn.has("win32") == 1 then
      pending("Windows does not permit double quotes in filenames")
      return
    end
    assert.equals(1, check('a"b.lua', "INVALID_LUA").code)
  end)

  it("checks the index when the working copy was already corrected", function()
    assert.equals(1, check("staged.lua", "INVALID_LUA", "local valid = true").code)
  end)

  it("accepts valid staged content with spaces in the filename", function()
    assert.equals(0, check("has spaces.lua", "local valid = true").code)
  end)

  it("rejects a failed Git blob read even when linters accept empty input", function()
    assert.equals(1, check("valid.lua", "local valid = true", nil, true).code)
  end)
end)
