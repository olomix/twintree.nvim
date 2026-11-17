local config = require("twintree.config")
local twintree = require("twintree")

describe("config", function()
  it("has defaults without setup", function()
    package.loaded["twintree.config"] = nil
    local fresh = require("twintree.config")
    assert.equals(35, fresh.options.tree_width)
    assert.equals(
      vim.fs.normalize(vim.fn.stdpath("cache") .. "/twintree"),
      fresh.cache_dir()
    )
    package.loaded["twintree.config"] = config
  end)

  it("merges options over defaults on every call", function()
    twintree.setup({ tree_width = 50 })
    assert.equals(50, config.options.tree_width)

    twintree.setup({ cache_dir = "/tmp/twintree-test" })
    assert.equals(35, config.options.tree_width)
    assert.equals("/tmp/twintree-test", config.cache_dir())

    twintree.setup()
    assert.equals(35, config.options.tree_width)
    assert.is_nil(config.options.cache_dir)
  end)

  describe("keys", function()
    local messages, notify

    before_each(function()
      twintree.setup()
      messages = {}
      notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(messages, { msg = msg, level = level })
      end
    end)

    after_each(function()
      vim.notify = notify
      twintree.setup()
    end)

    it("default to bracket and control-f", function()
      assert.same({ next_file = "]<C-f>", prev_file = "[<C-f>" }, config.options.keys)
    end)

    it("can be other keys, each on its own", function()
      twintree.setup({ keys = { next_file = "<F7>" } })
      assert.same({ next_file = "<F7>", prev_file = "[<C-f>" }, config.options.keys)
      twintree.setup({ keys = { next_file = "<F7>", prev_file = "<F8>" } })
      assert.same({ next_file = "<F7>", prev_file = "<F8>" }, config.options.keys)
      assert.same({}, messages)
    end)

    it("can be turned off with false", function()
      twintree.setup({ keys = { prev_file = false } })
      assert.same({ next_file = "]<C-f>", prev_file = false }, config.options.keys)
      twintree.setup({ keys = { next_file = false, prev_file = false } })
      assert.same({ next_file = false, prev_file = false }, config.options.keys)
      assert.same({}, messages)
    end)

    local unusable = {
      ["one key for two actions"] = { next_file = "<F7>", prev_file = "<F7>" },
      ["one key written in two ways"] = { next_file = "]<C-f>", prev_file = "]<c-f>" },
      ["a key that is the default of the other action"] = { next_file = "[<C-f>" },
      ["a value that is not a table"] = "<F7>",
      ["false for all keys"] = false,
      ["an empty key"] = { next_file = "" },
      ["a key that is a number"] = { next_file = 7 },
      ["a key that is true"] = { prev_file = true },
      ["an action the plugin does not have"] = { nxt_file = "<F7>" },
      ["a list of keys"] = { "<F7>", "<F8>" },
      ["a key longer than Neovim maps"] = { prev_file = ("x"):rep(51) },
    }
    for label, keys in pairs(unusable) do
      it("reject " .. label .. " and take nothing from that call", function()
        twintree.setup({ tree_width = 50, keys = { next_file = "<F7>" } })
        local before = vim.deepcopy(config.options)

        local ok, err = pcall(twintree.setup, { tree_width = 20, keys = keys })
        assert.is_true(ok, tostring(err))
        assert.equals(1, #messages)
        assert.equals(vim.log.levels.ERROR, messages[1].level)
        assert.truthy(messages[1].msg:find("^twintree: keys"))
        assert.is_nil(messages[1].msg:find("\n", 1, true))
        assert.same(before, config.options)

        -- The keys are bound on tab changes; none of that may fail now.
        vim.v.errmsg = ""
        vim.cmd.tabnew()
        vim.cmd.tabclose()
        assert.equals("", vim.v.errmsg)
        assert.equals(1, #messages)
      end)
    end
  end)
end)
