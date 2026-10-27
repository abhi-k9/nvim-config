describe("terminal policy", function()
  local Settings = require("config.settings")
  local spec, previous_shell, old_terminal, old_executable, terms, current_root, old_root

  before_each(function()
    Settings.reset()
    previous_shell = vim.o.shell
    old_terminal, old_executable = package.loaded["toggleterm.terminal"], vim.fn.executable
    old_root, current_root = Settings.project_root, "/project-a"
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
end)
