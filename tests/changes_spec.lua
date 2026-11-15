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

describe("changes.parse_numstat", function()
  it("parses added and deleted counts by path", function()
    assert.same({
      ["a.lua"] = { added = 5, deleted = 3 },
      ["src/b c.lua"] = { added = 0, deleted = 12 },
      ["ї/файл.txt"] = { added = 40, deleted = 0 },
    }, changes.parse_numstat(z("5\t3\ta.lua", "0\t12\tsrc/b c.lua", "40\t0\tї/файл.txt")))
  end)

  it("keys a rename by its new path", function()
    assert.same({
      ["new/a.lua"] = { added = 2, deleted = 1 },
      ["z.lua"] = { added = 1, deleted = 1 },
    }, changes.parse_numstat(z("2\t1\t", "old/a.lua", "new/a.lua", "1\t1\tz.lua")))
  end)

  it("has no entry for a binary file", function()
    assert.same(
      { ["a.lua"] = { added = 1, deleted = 0 } },
      changes.parse_numstat(z("-\t-\tlogo.png", "1\t0\ta.lua"))
    )
  end)

  it("keeps a tab inside a file name", function()
    assert.same(
      { ["tab\there.txt"] = { added = 1, deleted = 2 } },
      changes.parse_numstat(z("1\t2\ttab\there.txt"))
    )
  end)

  it("returns nothing for empty output", function()
    assert.same({}, changes.parse_numstat(""))
  end)
end)

describe("changes.with_counts", function()
  it("puts counts onto the entries that have them", function()
    local entries = {
      { status = "M", path = "a.lua" },
      { status = "A", path = "logo.png" },
    }
    assert.same({
      { status = "M", path = "a.lua", added = 5, deleted = 3 },
      { status = "A", path = "logo.png" },
    }, changes.with_counts(entries, { ["a.lua"] = { added = 5, deleted = 3 } }))
  end)
end)

describe("changes.parse_paths", function()
  it("splits NUL-separated paths", function()
    assert.same({ "a b.txt", "ї/c.txt" }, changes.parse_paths(z("a b.txt", "ї/c.txt")))
    assert.same({}, changes.parse_paths(""))
  end)

  it("drops directory entries", function()
    assert.same({ "a.txt" }, changes.parse_paths(z("inner/", "a.txt", "deep/repo/")))
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

  it("counts the lines of untracked files", function()
    local counts = { ["a.txt"] = 7 }
    assert.same({
      { status = "A", path = "a.txt", added = 7, deleted = 0 },
      { status = "A", path = "b.bin" },
    }, changes.merge_untracked({}, { "a.txt", "b.bin" }, function(path)
      return counts[path]
    end))
  end)

  it("gives no counts to a file removed from the index but still on disk", function()
    local entries = { { status = "D", path = "a.txt", added = 0, deleted = 4 } }
    local counted = {}
    assert.same(
      {
        { status = "M", path = "a.txt" },
        { status = "A", path = "b.txt", added = 6, deleted = 0 },
      },
      changes.merge_untracked(entries, { "a.txt", "b.txt" }, function(path)
        table.insert(counted, path)
        return 6
      end)
    )
    -- Its lines are not needed, so the file is not read.
    assert.same({ "b.txt" }, counted)
  end)

  it("treats an unstaged-removed file that is still on disk as modified", function()
    local entries = { { status = "D", path = "a.txt" } }
    assert.same(
      { { status = "M", path = "a.txt" } },
      changes.merge_untracked(entries, { "a.txt" })
    )
  end)
end)
