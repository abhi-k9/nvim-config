describe("terminal policy", function()
  local Settings = require("config.settings")
  local spec, previous_shell, old_terminal, old_executable, terms, current_root, old_root
  local old_has, old_notify, buffers

  before_each(function()
    Settings.reset()
    previous_shell = vim.o.shell
    old_terminal, old_executable = package.loaded["toggleterm.terminal"], vim.fn.executable
    old_root, current_root = Settings.project_root, "/project-a"
    old_has, old_notify = vim.fn.has, vim.notify
    buffers = {}
    Settings.project_root = function()
      return current_root
    end
    vim.fn.executable = function(bin)
      return bin == "lazygit" and 1 or old_executable(bin)
    end
    terms = {}
    package.loaded["toggleterm.terminal"] = {
      Terminal = {
        new = function(_, opts)
          opts.toggles = 0
          opts.toggle = function(term)
            term.toggles = term.toggles + 1
          end
          terms[#terms + 1] = opts
          return opts
        end,
      },
    }
    spec = dofile(vim.fn.getcwd() .. "/lua/plugins/terminal.lua")[1]
  end)

  after_each(function()
    Settings.reset()
    Settings.project_root = old_root
    vim.o.shell = previous_shell
    package.loaded["toggleterm.terminal"], vim.fn.executable = old_terminal, old_executable
    vim.fn.has, vim.notify = old_has, old_notify
    for _, buffer in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(buffer) then
        vim.api.nvim_buf_delete(buffer, { force = true })
      end
    end
  end)

  local function lazygit()
    for _, key in ipairs(spec.keys) do
      if key[1] == "<leader>tg" then return key[2]() end
    end
    error("lazygit mapping missing")
  end

  it("inherits the configured shell and accepts an invocation-time resolver", function()
    vim.o.shell = "custom-shell"
    assert.equals("custom-shell", spec.opts.shell())
    Settings.configure({
      terminal = {
        shell = function()
          return "other-shell --flag"
        end,
      },
    })
    assert.equals("other-shell --flag", spec.opts.shell())
    Settings.configure({ terminal = {
      shell = function()
        return nil
      end,
    } })
    assert.equals("custom-shell", spec.opts.shell())
  end)

  it("limits the legacy PowerShell preference to Windows with pwsh available", function()
    local windows, pwsh = true, true
    vim.fn.has = function(feature)
      if feature == "win32" then return windows and 1 or 0 end
      return old_has(feature)
    end
    vim.fn.executable = function(bin)
      if bin == "pwsh" then return pwsh and 1 or 0 end
      return old_executable(bin)
    end
    vim.o.shell = "cmd.exe"
    -- Merely having PowerShell installed does not override the default shell.
    assert.equals("cmd.exe", spec.opts.shell())
    Settings.configure({ terminal = { shell = "legacy" } })
    assert.equals("pwsh -NoLogo", spec.opts.shell())
    pwsh = false
    assert.equals("cmd.exe", spec.opts.shell())
    windows, pwsh = false, true
    vim.o.shell = "/usr/bin/fish"
    assert.equals("/usr/bin/fish", spec.opts.shell())
  end)

  it("rejects invalid shell resolver results before spawning", function()
    for _, value in ipairs({ "", false, 42, { "shell" } }) do
      Settings.configure({
        terminal = {
          shell = function()
            return value
          end,
        },
      })
      assert.has_error(spec.opts.shell, "terminal.shell must be a nonempty string")
    end
  end)

  it("retains one lazygit process by default across projects", function()
    lazygit()
    current_root = "/project-b"
    lazygit()
    assert.equals(1, #terms)
    assert.equals(2, terms[1].toggles)
    assert.equals(".", terms[1].dir)
  end)

  it("can retain a lazygit process per project without terminating earlier jobs", function()
    Settings.configure({ terminal = { lazygit_per_project = true } })
    lazygit()
    current_root = "/project-b"
    lazygit()
    current_root = "/project-a"
    lazygit()
    assert.equals(2, #terms)
    assert.equals(2, terms[1].toggles)
    assert.equals(1, terms[2].toggles)
    terms[1].on_exit()
    lazygit()
    assert.equals(3, #terms)
  end)

  it("does not let a stale exit callback evict a replacement LazyGit process", function()
    lazygit()
    local old_exit = terms[1].on_exit
    old_exit()
    lazygit()
    old_exit()
    lazygit()
    assert.equals(2, #terms)
    assert.equals(2, terms[2].toggles)
  end)

  it("reports a missing LazyGit executable without creating a terminal", function()
    local notices = {}
    vim.fn.executable = function(bin)
      return bin == "lazygit" and 0 or old_executable(bin)
    end
    vim.notify = function(message, level)
      notices[#notices + 1] = { message, level }
    end
    lazygit()
    assert.equals(0, #terms)
    assert.same({ { "lazygit is not on PATH", vim.log.levels.WARN } }, notices)
  end)

  it("keeps shell navigation separate from LazyGit's immediate Escape and native keys", function()
    local function create_maps(callback)
      local buffer = vim.api.nvim_create_buf(false, true)
      buffers[#buffers + 1] = buffer
      callback({ bufnr = buffer })
      local maps = {}
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(buffer, "t")) do
        maps[map.lhs] = map
      end
      return maps
    end
    local shell_maps = create_maps(spec.opts.on_create)
    for _, direction in ipairs({ "h", "j", "k", "l" }) do
      assert.equals(
        "<Cmd>wincmd " .. direction .. "<CR>",
        shell_maps["<C-" .. direction:upper() .. ">"].rhs
      )
    end
    assert.is_nil(shell_maps["<C-\\>"])
    lazygit()
    local git_maps = create_maps(terms[1].on_create)
    assert.equals(1, vim.tbl_count(git_maps))
    assert.equals("<Esc>", git_maps["<Esc>"].rhs)
    assert.equals(1, git_maps["<Esc>"].nowait)
  end)
end)
