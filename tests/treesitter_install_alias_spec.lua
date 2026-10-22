describe("parser installation completion", function()
  local original_ts, original_add, original_start, original_query, original_executable, original_notify
  local buffers, attached, installed, completion, attempts

  before_each(function()
    original_ts = package.loaded["nvim-treesitter"]
    original_add, original_start = vim.treesitter.language.add, vim.treesitter.start
    original_query, original_executable, original_notify =
      vim.treesitter.query.get, vim.fn.executable, vim.notify
    buffers, attached, installed, completion, attempts = {}, {}, false, nil, 0
    vim.notify = function() end
    vim.fn.executable = function(name)
      return name == "tree-sitter" and 1 or original_executable(name)
    end
    vim.treesitter.language.add = function(lang, opts)
      if lang == "javascript" then return installed end
      return original_add(lang, opts)
    end
    vim.treesitter.start = function(buf)
      if installed then attached[buf] = true end
    end
    vim.treesitter.query.get = function()
      return nil
    end
    package.loaded["nvim-treesitter"] = {
      setup = function() end,
      get_available = function()
        return { "javascript" }
      end,
      install = function(languages)
        if vim.tbl_contains(languages, "javascript") then attempts = attempts + 1 end
        return {
          await = function(_, callback)
            completion = callback
          end,
        }
      end,
    }
    local spec = dofile(vim.fn.getcwd() .. "/lua/plugins/treesitter.lua")[1]
    spec.config(nil, { parsers = {} })
    vim.wait(20, function()
      return false
    end)
    attempts = 0
  end)

  after_each(function()
    for _, buf in ipairs(buffers) do
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    package.loaded["nvim-treesitter"] = original_ts
    vim.treesitter.language.add, vim.treesitter.start = original_add, original_start
    vim.treesitter.query.get, vim.fn.executable, vim.notify =
      original_query, original_executable, original_notify
  end)

  local function buffer(ft)
    local buf = vim.api.nvim_create_buf(true, false)
    buffers[#buffers + 1] = buf
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("noautocmd setlocal filetype=" .. ft)
    end)
    vim.api.nvim_exec_autocmds("FileType", { buffer = buf, group = "user_treesitter" })
    return buf
  end

  it("attaches all pending filetype aliases after their shared parser finishes", function()
    assert.equals("javascript", vim.treesitter.language.get_lang("javascriptreact"))
    local js, jsx = buffer("javascript"), buffer("javascriptreact")
    assert.equals(1, attempts)
    assert.is_nil(attached[js])
    assert.is_nil(attached[jsx])
    installed = true
    completion(nil, true)
    vim.wait(100, function()
      return attached[js] and attached[jsx]
    end)
    assert.is_true(attached[js])
    assert.is_true(attached[jsx])
  end)

  it("does not start highlighting a large buffer when the shared parser finishes", function()
    buffer("javascript")
    local big = buffer("javascriptreact")
    vim.b[big].big_file = true
    installed = true
    completion(nil, true)
    vim.wait(20, function()
      return false
    end)
    assert.is_nil(attached[big])
  end)
end)
