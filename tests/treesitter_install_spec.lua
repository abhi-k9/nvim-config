describe("on-demand parser installation", function()
  local original_ts, original_add, original_executable, original_notify, original_auto_install
  local attempts, notes, installed, result, task_error, fake_time, original_time
  local buf

  before_each(function()
    original_auto_install, vim.g.treesitter_auto_install = vim.g.treesitter_auto_install, true
    original_ts = package.loaded["nvim-treesitter"]
    original_add = vim.treesitter.language.add
    original_executable = vim.fn.executable
    original_notify = vim.notify
    original_time = os.time
    attempts, notes, installed, result, task_error, fake_time = 0, {}, false, false, nil, 1000
    os.time = function()
      return fake_time
    end
    vim.notify = function(msg)
      notes[#notes + 1] = msg
    end
    vim.fn.executable = function(name)
      return name == "tree-sitter" and 1 or original_executable(name)
    end
    vim.treesitter.language.add = function(lang, opts)
      if lang == "audit_parser" then return installed end
      return original_add(lang, opts)
    end
    package.loaded["nvim-treesitter"] = {
      setup = function() end,
      get_available = function()
        return { "audit_parser" }
      end,
      install = function(languages)
        -- The real init's deferred eager install can run while this stub
        -- is active; count only the parser exercised by this test.
        if vim.tbl_contains(languages, "audit_parser") then attempts = attempts + 1 end
        return {
          await = function(_, callback)
            callback(task_error, result)
          end,
        }
      end,
    }
    local spec = dofile(vim.fn.getcwd() .. "/lua/plugins/treesitter.lua")[1]
    spec.config(nil, { parsers = {} })
    -- Drain the deferred eager install before counting on-demand attempts.
    vim.wait(20, function()
      return false
    end)
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("noautocmd setlocal filetype=audit_parser")
    end)
  end)

  after_each(function()
    vim.g.treesitter_auto_install = original_auto_install
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    package.loaded["nvim-treesitter"] = original_ts
    vim.treesitter.language.add = original_add
    vim.fn.executable = original_executable
    vim.notify = original_notify
    os.time = original_time
  end)

  local function filetype()
    vim.api.nvim_exec_autocmds("FileType", { buffer = buf, group = "user_treesitter" })
    vim.wait(20, function()
      return false
    end)
  end

  it("backs off when the installer returns false without throwing", function()
    filetype()
    assert.are.equal(1, attempts)
    filetype()
    assert.are.equal(1, attempts)
    assert.is_truthy(table.concat(notes, "\n"):find("install failed", 1, true))

    fake_time = fake_time + 300
    filetype()
    assert.are.equal(2, attempts)
  end)

  it("honors the opt-out for both startup and first-use installation", function()
    vim.g.treesitter_auto_install = false
    dofile(vim.fn.getcwd() .. "/lua/plugins/treesitter.lua")[1].config(nil, {
      parsers = { "audit_parser" },
    })
    filetype()
    assert.equals(0, attempts)
  end)

  it("skips both startup and first-use builds without a compiler", function()
    local tooling = require("config.tooling")
    local msvc = tooling.msvc_install_path
    tooling.msvc_install_path = function()
      return nil
    end
    vim.fn.executable = function(name)
      return (name == "tree-sitter" or name == "curl" or name == "tar") and 1 or 0
    end
    local ok, err = pcall(function()
      dofile(vim.fn.getcwd() .. "/lua/plugins/treesitter.lua")[1].config(
        nil,
        { parsers = { "audit_parser" } }
      )
      filetype()
      assert.equals(0, attempts)
      assert.same({}, notes)
    end)
    tooling.msvc_install_path = msvc
    assert.is_true(ok, tostring(err))
  end)

  it("also backs off when the async task raises an error", function()
    task_error = "test download failure"
    filetype()
    filetype()
    assert.are.equal(1, attempts)
    assert.is_truthy(table.concat(notes, "\n"):find(task_error, 1, true))
  end)
end)
