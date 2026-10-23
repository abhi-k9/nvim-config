describe("literal terminal working directories", function()
  local spec, old_toggle, calls

  before_each(function()
    spec = dofile(vim.fn.getcwd() .. "/lua/plugins/terminal.lua")[1]
    local tt = require("toggleterm")
    old_toggle, calls = tt.toggle, {}
    tt.toggle = function(count, size, dir, direction)
      calls[#calls + 1] = { count = count, size = size, dir = dir, direction = direction }
    end
  end)

  after_each(function()
    require("toggleterm").toggle = old_toggle
  end)

  it("passes relative cwd through every configured shell mapping", function()
    for _, key in ipairs(spec.keys) do
      if key[1] ~= "<leader>tg" then key[2]() end
    end
    assert.equals(4, #calls)
    assert.same(
      { "float", "float", "horizontal", "vertical" },
      vim.tbl_map(function(call)
        assert.equals(".", call.dir)
        return call.direction
      end, calls)
    )
    assert.is_false(spec.opts.autochdir)
  end)
end)

describe("real shell literal cwd", function()
  local base, literal, previous, previous_env, previous_shell, original_count
  local terminals

  before_each(function()
    require("lazy.core.loader").load("toggleterm.nvim", { cmd = "spec" })
    terminals = require("toggleterm.terminal")
    previous, previous_env, previous_shell = vim.fn.getcwd(), vim.env.NVIM_TERM_LITERAL, vim.o.shell
    original_count = #terminals.get_all(true)
    base = vim.fn.tempname()
    literal = base .. "/$NVIM_TERM_LITERAL"
    vim.fn.mkdir(literal, "p")
    vim.fn.mkdir(base .. "/expanded", "p")
    vim.env.NVIM_TERM_LITERAL = "expanded"
    vim.o.shell = "/bin/sh"
  end)

  after_each(function()
    local all = terminals.get_all(true)
    for i = #all, original_count + 1, -1 do
      all[i]:shutdown()
    end
    vim.o.shell, vim.env.NVIM_TERM_LITERAL = previous_shell, previous_env
    assert(vim.uv.chdir(previous))
    vim.api.nvim_set_current_dir(".")
    vim.fn.delete(base, "rf")
  end)

  local function capture(local_dir)
    -- Passing the absolute path to :cd expands $NAME before Toggleterm even
    -- sees it. Establish a real literal cwd, then set the public '.' scope.
    assert(vim.uv.chdir(literal))
    if local_dir then
      vim.cmd.lcd(".")
    else
      vim.api.nvim_set_current_dir(".")
    end
    assert.equals(literal, vim.fn.getcwd())
    local output, done = base .. "/cwd.txt", false
    local term = terminals.Terminal:new({
      cmd = "pwd > " .. vim.fn.shellescape(output),
      dir = ".",
      direction = "horizontal",
      close_on_exit = false,
      on_exit = function()
        done = true
      end,
    })
    term:open()
    assert.is_true(
      vim.wait(3000, function()
        return done
      end),
      "shell did not exit"
    )
    local actual = vim.fn.readfile(output)[1]
    term:shutdown()
    assert.equals(vim.uv.fs_realpath(literal), vim.uv.fs_realpath(actual))
  end

  it("spawns in a literal global cwd rather than its environment expansion", function()
    if vim.fn.has("win32") == 1 then
      pending("uses a POSIX shell")
      return
    end
    capture(false)
  end)

  it("spawns in a literal window-local cwd", function()
    if vim.fn.has("win32") == 1 then
      pending("uses a POSIX shell")
      return
    end
    capture(true)
  end)

  it("keeps a running terminal's directory when reopened from another project", function()
    if vim.fn.has("win32") == 1 then
      pending("uses a POSIX shell")
      return
    end
    assert(vim.uv.chdir(literal))
    vim.api.nvim_set_current_dir(".")
    local term = terminals.Terminal:new({ dir = ".", direction = "horizontal" })
    term:open()
    local job, buffer = term.job_id, term.bufnr
    term:close()
    vim.api.nvim_set_current_dir(base .. "/expanded")
    term:open()
    assert.equals(job, term.job_id)
    assert.equals(buffer, term.bufnr)
    local output = base .. "/persisted.txt"
    term:send("pwd > " .. vim.fn.shellescape(output))
    assert.is_true(vim.wait(3000, function()
      return vim.fn.filereadable(output) == 1
    end))
    assert.equals(vim.uv.fs_realpath(literal), vim.uv.fs_realpath(vim.fn.readfile(output)[1]))
    term:shutdown()
  end)
end)
