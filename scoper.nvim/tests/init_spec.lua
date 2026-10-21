-- tests/init_spec.lua
--
-- setup(): option merging, default_excludes, and which directory changes
-- switch the project.

local Scoper = require("scoper")
local State = require("scoper.state")

describe("scoper.setup", function()
  local defaults = vim.deepcopy(Scoper.config)
  local a, b, data, prev, env

  before_each(function()
    a, b, data, prev, env =
      vim.fn.tempname(),
      vim.fn.tempname(),
      vim.fn.tempname(),
      vim.fn.getcwd(),
      vim.env.XDG_DATA_HOME
    vim.fn.mkdir(a .. "/src", "p")
    vim.fn.mkdir(b, "p")
    vim.env.XDG_DATA_HOME = data
    vim.fn.chdir(a)
  end)

  after_each(function()
    vim.cmd("silent! lcd " .. vim.fn.fnameescape(prev))
    vim.cmd("silent! tcd " .. vim.fn.fnameescape(prev))
    vim.cmd("cd " .. vim.fn.fnameescape(prev))
    pcall(vim.api.nvim_del_augroup_by_name, "scoper_dir")
    Scoper.config = vim.deepcopy(defaults)
    State.default_excludes = {}
    vim.env.XDG_DATA_HOME = env
    for _, d in ipairs({ a, b, data }) do
      vim.fn.delete(d, "rf")
    end
  end)

  it("seeds the default scope with default_excludes", function()
    Scoper.setup({ default_excludes = { "**/node_modules/**" } })
    assert.are.same({ "**/node_modules/**" }, State.active_scope().exclude)
  end)

  it("replaces list options instead of merging them", function()
    Scoper.setup({ lsp = { clangd_args = { "--x" } } })
    assert.are.same({ "--x" }, Scoper.config.lsp.clangd_args)
    assert.is_false(Scoper.config.lsp.clangd)
  end)

  it("follows :cd, but not :lcd or :tcd", function()
    Scoper.setup({})
    State.add_paths("src")
    vim.cmd("lcd " .. vim.fn.fnameescape(b))
    assert.are.same({ "src" }, State.active_scope().include)
    vim.cmd("lcd " .. vim.fn.fnameescape(a))
    vim.cmd("tcd " .. vim.fn.fnameescape(b))
    assert.are.same({ "src" }, State.active_scope().include)
    -- Back in `a` first: :cd fires no DirChanged into the directory the
    -- process is already in.
    vim.cmd("tcd " .. vim.fn.fnameescape(a))
    vim.cmd("cd " .. vim.fn.fnameescape(b))
    assert.are.same({}, State.active_scope().include)
    vim.cmd("cd " .. vim.fn.fnameescape(a))
    assert.are.same({ "src" }, State.active_scope().include)
  end)
end)
