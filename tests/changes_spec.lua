local changes = require("twintree.changes")

local function z(...)
  return table.concat({ ... }, "\0") .. "\0"
end

describe("changes.parse_name_status", function()
  it("parses added, modified and deleted files", function()
    local out = z("A", "new.lua", "M", "src/mod.lua", "D", "gone.lua")
    assert.same({
      { status = "A", path = "new.lua" },
      { status = "M", path = "src/mod.lua" },
      { status = "D", path = "gone.lua" },
    }, changes.parse_name_status(out))
  end)

  it("parses renames with both paths", function()
    assert.same(
      { { status = "R", old_path = "old/a.lua", path = "new/a.lua" } },
      changes.parse_name_status(z("R087", "old/a.lua", "new/a.lua"))
    )
  end)

  it("reports a copy as an added file", function()
    assert.same(
      { { status = "A", path = "copy.lua" } },
      changes.parse_name_status(z("C100", "orig.lua", "copy.lua"))
    )
  end)

  it("reports type changes as modified", function()
    assert.same(
      { { status = "M", path = "link" } },
      changes.parse_name_status(z("T", "link"))
    )
  end)

  it("keeps spaces and non-ASCII characters in names", function()
    assert.same({
      { status = "M", path = "dir with space/файл.txt" },
      { status = "A", path = "tab\there.txt" },
    }, changes.parse_name_status(z("M", "dir with space/файл.txt", "A", "tab\there.txt")))
  end)

  it("returns nothing for empty output", function()
    assert.same({}, changes.parse_name_status(""))
  end)
end)

describe("changes.parse_paths", function()
  it("splits NUL-separated paths", function()
    assert.same({ "a b.txt", "ї/c.txt" }, changes.parse_paths(z("a b.txt", "ї/c.txt")))
    assert.same({}, changes.parse_paths(""))
  end)
end)

describe("changes.merge_untracked", function()
  it("adds untracked files as added and sorts by path", function()
    local entries = { { status = "M", path = "b.txt" } }
    assert.same({
      { status = "A", path = "a.txt" },
      { status = "M", path = "b.txt" },
    }, changes.merge_untracked(entries, { "a.txt" }))
  end)

  it("treats an unstaged-removed file that is still on disk as modified", function()
    local entries = { { status = "D", path = "a.txt" } }
    assert.same(
      { { status = "M", path = "a.txt" } },
      changes.merge_untracked(entries, { "a.txt" })
    )
  end)
end)
