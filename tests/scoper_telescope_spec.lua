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

  it("uses the shared exact predicate for individual-file includes", function()
    State.clear_active()
    State.add_paths("src/a.c")
    assert.same({ "src/a.c" }, results(Pickers.find))
  end)

  it("uses bounded glob roots without including neighboring files", function()
    State.clear_active()
    State.remove_excludes(vim.deepcopy(State.active_scope().exclude))
    State.add_paths("src/**/a.c")
    assert.same({ "src/a.c", "src/gen/a.c", "src/tmp/a.c" }, results(Pickers.find))
  end)

  it("filters real fzf filename and grep parsers before formatting rows", function()
    -- fzf-lua uses the builtin assert's return values while initializing
    -- Unicode separators. Plenary's global luassert replacement adds nils
    -- there, so exercise this real backend in a clean child editor. Reuse
    -- the locked plugin sources explicitly: XDG_DATA_HOME is the isolated
    -- state fixture here, not an installed plugin tree to bootstrap again.
    local fzf_dir = require("lazy.core.config").plugins["fzf-lua"].dir
    local script = base .. "/fzf-probe.lua"
    vim.fn.writefile(
      vim.split(
        ([[
vim.opt.rtp:prepend(%q)
vim.opt.rtp:append(%q)
vim.opt.rtp:append(%q)
vim.api.nvim_set_current_dir(%q)
local state, pickers = require("scoper.state"), require("scoper.pickers")
state.load({ quiet = true })
state.clear_active()
state.remove_excludes(vim.deepcopy(state.active_scope().exclude))
state.add_paths("src/**/a.c")
state.set_enabled(true)
local ctx = pickers._context()
local opts = { cwd = state.root(), file_icons = false, git_icons = false }
local files, grep = pickers._fzf_transform(ctx, false), pickers._fzf_transform(ctx, true)
assert(files("src/a.c", opts) == "src/a.c")
assert(files("src/b.c", opts) == nil)
assert(grep("src/gen/a.c:1:1:NEEDLE", opts) == "src/gen/a.c:1:1:NEEDLE")
assert(grep("src/b.c:1:1:src/a.c", opts) == nil)
print("FZF_SCOPE_OK")
]]):format(previous, previous .. "/scoper.nvim", fzf_dir, base .. "/project"),
        "\n"
      ),
      script
    )
    local result = vim
      .system({ vim.v.progpath, "--headless", "--noplugin", "-u", "NONE", "-l", script }, {
        cwd = previous,
        text = true,
      })
      :wait(10000)
    assert.equals(0, result.code, result.stderr)
    assert.matches("FZF_SCOPE_OK", (result.stdout or "") .. (result.stderr or ""))
    assert.equals(
      0,
      vim.fn.isdirectory(base .. "/data/nvim/lazy"),
      "Parser probe provisioned plugins"
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
