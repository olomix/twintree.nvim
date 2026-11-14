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
end)
