describe("UI selection ownership", function()
  local select, loaded, preload, executable, notify, module
  local Selector, calls, registered, available, behavior, menu, fallback

  before_each(function()
    select, loaded = vim.ui.select, package.loaded["fzf-lua"]
    preload = package.preload["fzf-lua"]
    executable, notify = vim.fn.executable, vim.notify
    module = package.loaded["config.selector"]
    calls, registered, available = 0, 0, true
    fallback = function(_items, _opts, callback)
      calls = calls + 1
      return callback(nil, nil)
    end
    vim.ui.select = fallback
    vim.notify = function() end
    vim.fn.executable = function(bin)
      if bin == "fzf" then return available and 1 or 0 end
      return executable(bin)
    end
    package.loaded["fzf-lua"] = nil
    package.preload["fzf-lua"] = function()
      return {
        register_ui_select = function(options)
          registered, menu = registered + 1, options
          assert.equals(fallback, vim.ui.select)
          vim.ui.select = function(items, opts, callback)
            return behavior(items, opts, callback)
          end
        end,
      }
    end
    behavior = function(items, _, callback)
      callback(items[1], 1)
    end
    package.loaded["config.selector"] = nil
    Selector = require("config.selector")
  end)

  after_each(function()
    vim.ui.select, vim.fn.executable, vim.notify = select, executable, notify
    package.loaded["fzf-lua"], package.preload["fzf-lua"] = loaded, preload
    package.loaded["config.selector"] = module
  end)

  it("loads only on selection and registers once across repeated setup", function()
    Selector.setup()
    assert.is_nil(package.loaded["fzf-lua"])
    Selector.setup()
    vim.ui.select({ "one" }, {}, function() end)
    vim.ui.select({ "two" }, {}, function() end)
    assert.equals(1, registered)
    assert.equals(0, calls)
  end)

  it("preserves formatted items and original indexes with one delivery", function()
    local items = { { label = "same" }, { label = "same" } }
    local opts = {
      format_item = function(item)
        return item.label
      end,
    }
    local deliveries = 0
    behavior = function(received, options, cb)
      assert.equals(items, received)
      assert.equals(opts, options)
      assert.equals("same", options.format_item(received[2]))
      cb(received[2], 2)
      cb(nil, nil)
    end
    Selector.setup("fzf")
    vim.ui.select(items, opts, function(item, index)
      deliveries = deliveries + 1
      assert.equals(items[2], item)
      assert.equals(2, index)
    end)
    assert.equals(1, deliveries)
  end)

  it("preserves false list items returned with a valid index", function()
    behavior = function(_, _, cb)
      cb(nil, 1)
    end
    Selector.setup()
    vim.ui.select({ false }, {}, function(item, index)
      assert.is_false(item)
      assert.equals(1, index)
    end)
  end)

  it("delivers cancellation once and handles empty lists without loading", function()
    Selector.setup()
    local deliveries = 0
    local function cancelled(item, index)
      deliveries = deliveries + 1
      assert.is_nil(item)
      assert.is_nil(index)
    end
    vim.ui.select({}, {}, cancelled)
    assert.is_nil(package.loaded["fzf-lua"])
    behavior = function(_, _, cb)
      cb(nil, nil)
      cb(nil, nil)
    end
    vim.ui.select({ "one" }, {}, cancelled)
    assert.equals(2, deliveries)
  end)

  it("falls back before and after registration and retries when fzf returns", function()
    Selector.setup()
    available = false
    vim.ui.select({ "one" }, {}, function() end)
    assert.equals(0, registered)
    available = true
    vim.ui.select({ "one" }, {}, function() end)
    assert.equals(1, registered)
    available = false
    vim.ui.select({ "one" }, {}, function() end)
    assert.equals(2, calls)
    available = true
    vim.ui.select({ "one" }, {}, function() end)
    assert.equals(1, registered)
  end)

  it("keeps native, disabled and unsupported preferences on the prior UI", function()
    for _, provider in ipairs({ "native", false, "unsupported" }) do
      Selector.setup(provider)
      assert.equals(fallback, vim.ui.select)
    end
    assert.is_nil(package.loaded["fzf-lua"])
  end)

  it("accepts the Telescope legacy setting without loading Telescope", function()
    Selector.setup("telescope")
    vim.ui.select({ "one" }, {}, function() end)
    assert.equals(1, registered)
  end)

  it("preserves a later provider on repeated setup", function()
    Selector.setup()
    local other = function() end
    vim.ui.select = other
    Selector.setup()
    assert.equals(other, vim.ui.select)
  end)

  it("falls back safely when loading or registration throws", function()
    package.preload["fzf-lua"] = function()
      error("plugin disabled")
    end
    Selector.setup()
    assert.has_no.errors(function()
      vim.ui.select({ "one" }, {}, function() end)
    end)
    assert.equals(1, calls)
  end)

  it("does not replay choices when the callback throws", function()
    Selector.setup()
    local ok = pcall(vim.ui.select, { "one" }, {}, function()
      error("callback failed")
    end)
    assert.is_false(ok)
    assert.equals(0, calls)
  end)

  it("falls back once on picker errors and ignores a delayed second delivery", function()
    local delayed, deliveries
    behavior = function(_, _, cb)
      delayed = cb
      error("picker failed")
    end
    Selector.setup()
    deliveries = 0
    vim.ui.select({ "one" }, {}, function()
      deliveries = deliveries + 1
    end)
    delayed("one", 1)
    assert.equals(1, calls)
    assert.equals(1, deliveries)
  end)

  it("sizes short menus separately from code actions and prevents resume", function()
    Selector.setup()
    vim.ui.select({ "one" }, {}, function() end)
    local short = menu({}, { "one", "two" })
    local actions = menu({ kind = "codeaction" }, { "fix A", "fix B" })
    assert.is_true(short.no_resume)
    assert.is_true(actions.no_resume)
    assert.is_true(short.winopts.width < actions.winopts.width)
    assert.is_true(short.winopts.height <= 0.5)
  end)
end)
