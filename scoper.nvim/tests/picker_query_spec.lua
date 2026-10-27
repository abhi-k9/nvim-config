local State = require("scoper.state")
local Pickers = require("scoper.pickers")
local Path = require("scoper.path")

describe("shared scope queries in pickers", function()
  local root, previous, data, saved

  before_each(function()
    root, previous, data = vim.fn.tempname(), vim.fn.getcwd(), vim.env.XDG_DATA_HOME
    vim.fn.mkdir(root .. "/project/src/inc", "p")
    vim.fn.mkdir(root .. "/data", "p")
    vim.fn.writefile({ "needle" }, root .. "/project/src/one.c")
    vim.fn.writefile({ "needle" }, root .. "/project/src/two.c")
    vim.fn.writefile({ "needle" }, root .. "/project/src/inc/one.h")
    vim.env.XDG_DATA_HOME = root .. "/data"
    vim.cmd.cd(vim.fn.fnameescape(root .. "/project"))
    State.load({ quiet = true })
    State.clear_active()
    State.set_enabled(true)
    saved = {}
    for _, mod in ipairs({ "fzf-lua", "fzf-lua.make_entry", "fzf-lua.path", "telescope.builtin" }) do
      saved[mod] = package.loaded[mod]
      package.loaded[mod] = nil
    end
  end)

  after_each(function()
    for mod, value in pairs(saved) do
      package.loaded[mod] = value
    end
    for _, mod in ipairs({ "fzf-lua", "fzf-lua.make_entry", "fzf-lua.path", "telescope.builtin" }) do
      package.loaded[mod] = saved[mod]
    end
    vim.cmd("silent! cclose")
    vim.fn.setqflist({}, "r")
    vim.cmd("silent! %bwipeout!")
    vim.cmd.cd(vim.fn.fnameescape(previous))
    vim.env.XDG_DATA_HOME = data
    State.load({ quiet = true })
    vim.fn.delete(root, "rf")
  end)

  it("accepts a single file include and keeps exact native find/grep results", function()
    State.add_paths("src/one.c")
    local ctx = Pickers._context()
    assert.same({ Path.normalize(root .. "/project/src/one.c") }, ctx.dirs)
    local file = Pickers._find_in_scope(ctx, "one.c")
    assert.equals(Path.key(root .. "/project/src/one.c"), Path.key(file))
    assert.is_nil((Pickers._find_in_scope(ctx, "two.c")))
    Pickers.grep("needle")
    local hits = vim.fn.getqflist()
    assert.equals(1, #hits)
    -- Native Windows buffers expand 8.3 temp-directory aliases. Compare the
    -- same logical filename without resolving symlinks in scope membership.
    assert.equals(
      Path.key(Path.expand_short(file, {})),
      Path.key(Path.expand_short(vim.api.nvim_buf_get_name(hits[1].bufnr), {}))
    )
  end)

  it("bounds a glob by its literal ancestor and filters native matches exactly", function()
    State.add_paths("src/**/*.h")
    local ctx = Pickers._context()
    assert.same({ Path.normalize(root .. "/project/src") }, ctx.dirs)
    assert.is_true(ctx.in_scope("src/inc/one.h"))
    assert.is_false(ctx.in_scope("src/one.c"))
    assert.is_nil((Pickers._find_in_scope(ctx, "one.c")))
    assert.is_not_nil((Pickers._find_in_scope(ctx, "one.h")))
    Pickers.grep("needle")
    local hits = vim.fn.getqflist()
    assert.equals(1, #hits)
    assert.equals("one.h", vim.fs.basename(vim.api.nvim_buf_get_name(hits[1].bufnr)))
  end)

  it("filters fzf file rows with a captured predicate before decoration", function()
    State.add_paths("src/**/*.h")
    local ctx = Pickers._context()
    local transformed = {}
    package.loaded["fzf-lua.make_entry"] = {
      file = function(line)
        transformed[#transformed + 1] = line
        return "decorated:" .. line
      end,
    }
    local opts = Pickers._fzf_files_opts(ctx, vim.fn.shellescape)
    assert.is_false(opts.multiprocess)
    assert.is_nil(opts.fn_transform("src/one.c", {}))
    assert.equals("decorated:src/inc/one.h", opts.fn_transform("src/inc/one.h", {}))
    State.clear_active()
    State.add_paths("src/*.c")
    assert.is_nil(opts.fn_transform("src/one.c", {}))
    assert.same({ "src/inc/one.h" }, transformed)
  end)

  it("filters parsed fzf grep filenames without interpreting text as a path", function()
    State.add_paths("src/**/*.h")
    local seen
    package.loaded["fzf-lua.path"] = {
      entry_to_file = function(line, opts)
        assert.equals(State.root(), opts.cwd)
        return { path = line:match("^(.-):%d+:%d+:") }
      end,
    }
    package.loaded["fzf-lua.make_entry"] = {
      file = function(line)
        seen = line
        return line
      end,
    }
    local opts = Pickers._fzf_grep_opts(Pickers._context(), "needle", vim.fn.shellescape)
    assert.is_nil(opts.fn_transform("src/one.c:1:1:src/inc/one.h", {}))
    assert.equals("src/inc/one.h:1:1:needle", opts.fn_transform("src/inc/one.h:1:1:needle", {}))
    assert.equals("src/inc/one.h:1:1:needle", seen)
  end)
end)
