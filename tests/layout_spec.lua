local layout = require("twintree.layout")

---Build an input for `decide`: widths are tree, before, after.
local function input(tree, before, after, overrides)
  local base = {
    columns = 160,
    layout = {
      ratio = 0.5,
      tree_width = 35,
      columns = 160,
      tree_shown = tree ~= nil,
      zoomed = false,
    },
    tree = tree,
    before = before,
    after = after,
    tree_fixed = true,
    min = 1,
  }
  for key, value in pairs(overrides or {}) do
    if key == "layout" then
      base.layout = vim.tbl_extend("force", base.layout, value)
    else
      base[key] = value
    end
  end
  return base
end

local function kind(...)
  return layout.decide(input(...)).kind
end

describe("layout.decide", function()
  describe("after a terminal resize", function()
    it("applies the stored layout", function()
      assert.equals("apply", kind(35, 62, 101, { columns = 200 }))
      assert.equals("apply", kind(35, 62, 21, { columns = 120 }))
    end)

    it("applies it with a hidden tree", function()
      assert.equals("apply", kind(nil, 80, 119, { columns = 200 }))
    end)

    it("leaves a layout alone that was zoomed before the resize", function()
      local zoomed = { columns = 200, layout = { zoomed = true } }
      assert.equals("none", kind(1, 1, 196, zoomed))
      assert.equals("none", kind(196, 1, 1, zoomed))
      assert.equals("none", kind(nil, 1, 198, zoomed))
      assert.is_true(layout.decide(input(1, 1, 196, zoomed)).zoomed)
    end)

    it("applies the stored layout when the resize itself squeezed a pane", function()
      assert.equals("apply", kind(35, 62, 1, { columns = 100 }))
      assert.equals("apply", kind(35, 1, 1, { columns = 40 }))
      assert.equals("apply", kind(nil, 80, 1, { columns = 82 }))
      assert.is_false(layout.decide(input(35, 62, 1, { columns = 100 })).zoomed)
    end)
  end)

  it("applies the stored layout when the tree was hidden or shown", function()
    assert.equals("apply", kind(nil, 79, 80, { layout = { tree_shown = true } }))
    assert.equals("apply", kind(35, 62, 61, { layout = { tree_shown = false } }))
  end)

  it("restores the tree left squeezed by equalizing after a pane zoom", function()
    assert.equals("restore", kind(1, 78, 79))
  end)

  it("unfixes a maximized tree so that equalizing changes something", function()
    assert.equals("unfix", kind(156, 1, 1))
    assert.equals("unfix", kind(156, 1, 1, { tree_fixed = false }))
  end)

  it("reports whether the layout is zoomed after the action", function()
    assert.is_true(layout.decide(input(1, 1, 156)).zoomed)
    assert.is_true(layout.decide(input(156, 1, 1)).zoomed)
    assert.is_false(layout.decide(input(1, 78, 79)).zoomed)
    assert.is_false(layout.decide(input(35, 62, 61)).zoomed)
    assert.is_false(layout.decide(input(nil, 79, 80, { layout = { tree_shown = true } })).zoomed)
  end)

  it("does nothing while a pane is maximized", function()
    assert.equals("none", kind(1, 1, 156))
    assert.equals("none", kind(1, 156, 1))
    assert.equals("none", kind(35, 1, 122))
    assert.equals("none", kind(nil, 1, 158))
  end)

  it("restores after equalizing with an unfixed tree", function()
    assert.equals("restore", kind(52, 52, 52, { tree_fixed = false }))
  end)

  it("uses 'winminwidth' as the squeezed width", function()
    assert.equals("restore", kind(10, 70, 76, { min = 10 }))
    assert.equals("none", kind(10, 10, 136, { min = 10 }))
    assert.equals("unfix", kind(136, 10, 10, { min = 10 }))
    assert.equals("learn", kind(11, 70, 75, { min = 10 }))
  end)

  describe("learning from a normal layout", function()
    it("remembers the tree width", function()
      local action = layout.decide(input(50, 55, 55))
      assert.equals("learn", action.kind)
      assert.equals(50, action.tree_width)
      assert.equals(0.5, action.ratio)
    end)

    it("remembers a hand-set pane ratio", function()
      local action = layout.decide(input(35, 40, 83))
      assert.equals("learn", action.kind)
      assert.equals(40 / 123, action.ratio)
    end)

    it("learns one half after equalizing", function()
      local action = layout.decide(input(35, 62, 61, { layout = { ratio = 0.3 } }))
      assert.equals(0.5, action.ratio)
      action = layout.decide(input(35, 61, 62, { layout = { ratio = 0.3 } }))
      assert.equals(0.5, action.ratio)
    end)

    it("keeps the remembered tree width while the tree is hidden", function()
      local action = layout.decide(input(nil, 60, 100, { layout = { tree_width = 44 } }))
      assert.equals("learn", action.kind)
      assert.equals(44, action.tree_width)
      assert.equals(60 / 160, action.ratio)
    end)

    it("does not drift the ratio through its own rounding", function()
      local ratio = 1 / 3
      for avail = 60, 150, 10 do
        local before = layout.before_width(avail, ratio)
        local action = layout.decide(input(35, before, avail - before, {
          layout = { ratio = ratio },
        }))
        assert.equals("learn", action.kind)
        assert.equals(ratio, action.ratio)
      end
    end)
  end)
end)

describe("layout.before_width", function()
  it("rounds and keeps one column for each pane", function()
    assert.equals(62, layout.before_width(123, 0.5))
    assert.equals(41, layout.before_width(123, 1 / 3))
    assert.equals(1, layout.before_width(10, 0))
    assert.equals(9, layout.before_width(10, 1))
  end)
end)
