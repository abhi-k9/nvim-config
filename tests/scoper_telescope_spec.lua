-- Actual pinned Telescope entry parsing and ripgrep jobs, in the host suite.
local State = require("scoper.state")
local Pickers = require("scoper.pickers")

describe("Scoper with real Telescope and ripgrep", function()
  local base, previous, old_data, old_picker, config, saved, prompt, notify, variable

  before_each(function()
    require("lazy.core.loader").load("telescope.nvim", { cmd = "spec" })
    assert.equals(1, vim.fn.executable("rg"), "ripgrep is required")
    base, previous, old_data = vim.fn.tempname(), vim.fn.getcwd(), vim.env.XDG_DATA_HOME
    old_picker, vim.g.scoper_picker = vim.g.scoper_picker, "telescope"
    notify, variable = vim.notify, vim.env.NVIM_SCOPER_LITERAL
    vim.env.XDG_DATA_HOME = base .. "/data"
    vim.fn.mkdir(base .. "/project/src/gen", "p")
    vim.fn.mkdir(base .. "/project/src/tmp", "p")
    for _, file in ipairs({ "src/a.c", "src/b.c", "src/gen/a.c", "src/tmp/a.c" }) do
      vim.fn.writefile({ "NEEDLE" }, base .. "/project/" .. file)
    end
    vim.api.nvim_set_current_dir(base .. "/project")
    State.load({ quiet = true })
    State.add_paths("src")
    State.add_excludes({ "src/{gen,tmp}/**", "src/[!a]*.c" })
    State.set_enabled(true)
    config = require("telescope.config")
    saved = { config.pickers.find_files, config.pickers.live_grep }
    config.pickers.find_files = { find_command = { "rg", "--files" }, previewer = false }
    config.pickers.live_grep = { previewer = false }
  end)

  after_each(function()
    if prompt and vim.api.nvim_buf_is_valid(prompt) then
      require("telescope.actions").close(prompt)
    end
    prompt = nil
    vim.notify, vim.env.NVIM_SCOPER_LITERAL = notify, variable
    config.pickers.find_files, config.pickers.live_grep = saved[1], saved[2]
    vim.api.nvim_set_current_dir(previous)
    vim.env.XDG_DATA_HOME, vim.g.scoper_picker = old_data, old_picker
    State.load({ quiet = true })
    vim.fn.delete(base, "rf")
  end)

  local function results(open)
    local finished = false
    open()
    prompt = vim.api.nvim_get_current_buf()
    local picker = require("telescope.actions.state").get_current_picker(prompt)
    assert.is_not_nil(picker, "Telescope did not open")
    picker:register_completion_callback(function()
      finished = true
    end)
    assert.is_true(
      vim.wait(5000, function()
        return finished
      end, 10),
      "rg job did not complete"
    )
    local files = {}
    for entry in picker.manager:iter() do
      files[#files + 1] = entry.filename or entry.value
    end
    table.sort(files)
    return files
  end

  it("filters file jobs using brace and negated-class excludes", function()
    assert.same({ "src/a.c" }, results(Pickers.find))
  end)

  it("filters live-grep coordinates with the same scope matcher", function()
    assert.same(
      { "src/a.c" },
      results(function()
        Pickers.grep("NEEDLE")
      end)
    )
  end)

  it("refuses a directory the real backend would expand to another location", function()
    local notices = {}
    vim.notify = function(message)
      notices[#notices + 1] = message
    end
    vim.env.NVIM_SCOPER_LITERAL = "different"
    local literal = base .. "/$NVIM_SCOPER_LITERAL"
    vim.fn.mkdir(literal, "p")
    assert(vim.uv.chdir(literal))
    vim.api.nvim_set_current_dir(".")
    State.load({ quiet = true })
    Pickers.find()
    assert.equals(1, #notices)
    assert.matches("cannot preserve the literal directory", notices[1])
    assert.is_not.equal("TelescopePrompt", vim.bo.filetype)
  end)

  it("honors filename-only grep mode after additional arguments resolve", function()
    config.pickers.live_grep.additional_args = function()
      return { "--files-with-matches" }
    end
    assert.same(
      { "src/a.c" },
      results(function()
        Pickers.grep("NEEDLE")
      end)
    )
  end)
end)
