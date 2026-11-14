local tree = require("twintree.tree")

local function texts(lines)
  return vim.tbl_map(function(line)
    return line.text
  end, lines)
end

describe("tree.lines", function()
  it("nests files under directories, directories first, sorted", function()
    local entries = {
      { status = "M", path = "z.lua" },
      { status = "A", path = "src/b.lua" },
      { status = "M", path = "src/a.lua" },
      { status = "D", path = "a.lua" },
    }
    assert.same({
      "▾ src/",
      "  M a.lua",
      "  A b.lua",
      "D a.lua",
      "M z.lua",
    }, texts(tree.lines(entries)))
  end)

  it("shows a chain of single directories on one line", function()
    local entries = { { status = "M", path = "a/b/c/file.go" } }
    local lines = tree.lines(entries)
    assert.same({ "▾ a/b/c/", "  M file.go" }, texts(lines))
    assert.equals("a/b/c", lines[1].path)
  end)

  it("stops collapsing where a directory has several children", function()
    local entries = {
      { status = "M", path = "a/b/c/one.go" },
      { status = "M", path = "a/b/d/e/two.go" },
      { status = "M", path = "a/b/top.go" },
    }
    assert.same({
      "▾ a/b/",
      "  ▾ c/",
      "    M one.go",
      "  ▾ d/e/",
      "    M two.go",
      "  M top.go",
    }, texts(tree.lines(entries)))
  end)

  it("hides the content of collapsed directories", function()
    local entries = {
      { status = "M", path = "src/a.lua" },
      { status = "M", path = "z.lua" },
    }
    assert.same(
      { "▸ src/", "M z.lua" },
      texts(tree.lines(entries, { src = true }))
    )
  end)

  it("shows where a renamed file came from", function()
    local entries = { { status = "R", old_path = "old/a.lua", path = "new/a.lua" } }
    local lines = tree.lines(entries)
    assert.same({ "▾ new/", "  R a.lua ← old/a.lua" }, texts(lines))
    assert.same(entries[1], lines[2].entry)
  end)

  it("marks the selected file", function()
    local entries = {
      { status = "M", path = "a.lua" },
      { status = "M", path = "b.lua" },
    }
    local lines = tree.lines(entries, {}, "b.lua")
    assert.is_nil(lines[1].selected)
    assert.is_true(lines[2].selected)
  end)

  it("highlights the status letter and the directory name by byte range", function()
    local lines = tree.lines({ { status = "A", path = "src/a.lua" } })
    assert.same({ { 0, #"▾ src/", "TwintreeDirectory" } }, lines[1].highlights)
    assert.same({ { 2, 3, "TwintreeAdded" } }, lines[2].highlights)
  end)

  it("marks directories that exist on one side only", function()
    local entries = {
      { status = "A", path = "added/x.lua" },
      { status = "M", path = "both/y.lua" },
      { status = "D", path = "removed/z.lua" },
    }
    local lines = tree.lines(entries, { removed = true }, nil, function(path)
      return ({ added = "A", removed = "D" })[path]
    end)
    assert.same({
      "▾ added/ A",
      "  A x.lua",
      "▾ both/",
      "  M y.lua",
      "▸ removed/ D",
    }, texts(lines))
    assert.same({
      { 0, #"▾ added/", "TwintreeDirectory" },
      { #"▾ added/ ", #"▾ added/ A", "TwintreeAdded" },
    }, lines[1].highlights)
    assert.same({ { 0, #"▾ both/", "TwintreeDirectory" } }, lines[3].highlights)
    assert.same({
      { 0, #"▸ removed/", "TwintreeDirectory" },
      { #"▸ removed/ ", #"▸ removed/ D", "TwintreeDeleted" },
    }, lines[5].highlights)
    assert.is_nil(lines[3].status)
  end)

  it("shows a message when nothing changed", function()
    local lines = tree.lines({})
    assert.same({ "No changes" }, texts(lines))
    assert.equals("message", lines[1].type)
  end)
end)
