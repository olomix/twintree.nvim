local tree = require("twintree.tree")

local function cells(text)
  return vim.fn.strdisplaywidth(text)
end

local function texts(lines)
  return vim.tbl_map(function(line)
    return line.text
  end, lines)
end

---A line with `left` at the start and `right` at the right edge.
local function row(left, right, width)
  return left .. (" "):rep(width - cells(left) - cells(right)) .. right
end

---The text a highlight group covers in a line.
local function highlighted(line, group)
  local found = {}
  for _, hl in ipairs(line.highlights) do
    if hl[3] == group then
      table.insert(found, line.text:sub(hl[1] + 1, hl[2]))
    end
  end
  return found
end

local function fake_icon(name, kind)
  if kind == "dir_open" then
    return "O", "FolderHl"
  elseif kind == "dir_closed" then
    return "C", "FolderHl"
  elseif name:match("%.lua$") then
    return "L", "LuaHl"
  end
  return nil
end

local LONG = "kz_028_promotion_events.sql"

describe("tree.lines", function()
  describe("structure", function()
    it("nests files under directories, directories first, sorted", function()
      local entries = {
        { status = "M", path = "z.lua" },
        { status = "A", path = "src/b.lua" },
        { status = "M", path = "src/a.lua" },
        { status = "D", path = "a.lua" },
      }
      assert.same({
        "▾ src/",
        row("│ a.lua", " M", 20),
        row("│ b.lua", " A", 20),
        row("a.lua", " D", 20),
        row("z.lua", " M", 20),
      }, texts(tree.lines(entries, { width = 20 })))
    end)

    it("shows a chain of single directories on one line", function()
      local lines = tree.lines({ { status = "M", path = "a/b/c/file.go" } }, { width = 20 })
      assert.same({ "▾ a/b/c/", row("│ file.go", " M", 20) }, texts(lines))
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
        "│ ▾ c/",
        row("│ │ one.go", " M", 20),
        "│ ▾ d/e/",
        row("│ │ two.go", " M", 20),
        row("│ top.go", " M", 20),
      }, texts(tree.lines(entries, { width = 20 })))
    end)

    it("hides the content of collapsed directories", function()
      local entries = {
        { status = "M", path = "src/a.lua" },
        { status = "M", path = "z.lua" },
      }
      assert.same(
        { "▸ src/", row("z.lua", " M", 20) },
        texts(tree.lines(entries, { width = 20, collapsed = { src = true } }))
      )
    end)

    it("marks the selected file and keeps its entry", function()
      local entries = {
        { status = "M", path = "a.lua" },
        { status = "M", path = "b.lua" },
      }
      local lines = tree.lines(entries, { selected = "b.lua" })
      assert.is_nil(lines[1].selected)
      assert.is_true(lines[2].selected)
      assert.same(entries[2], lines[2].entry)
      assert.equals("file", lines[2].type)
    end)

    it("shows a message when nothing changed", function()
      local lines = tree.lines({}, { width = 20 })
      assert.same({ "No changes" }, texts(lines))
      assert.equals("message", lines[1].type)
    end)

    it("uses a default width when none is given", function()
      local lines = tree.lines({ { status = "M", path = "a.lua" } })
      assert.equals(tree.DEFAULT_WIDTH, cells(lines[1].text))
    end)
  end)

  describe("right-hand block", function()
    it("puts counts and the status letter at the right edge", function()
      local entries = {
        { status = "M", path = "a.lua", added = 5, deleted = 3 },
        { status = "A", path = "longer_name.lua", added = 40, deleted = 0 },
        { status = "D", path = "x", added = 0, deleted = 53 },
      }
      local lines = tree.lines(entries, { width = 30 })
      assert.same({
        row("a.lua", " +5 -3 M", 30),
        row("longer_name.lua", " +40 -0 A", 30),
        row("x", " +0 -53 D", 30),
      }, texts(lines))
      for _, line in ipairs(lines) do
        assert.equals(30, cells(line.text))
      end
    end)

    it("shows no counts when they are not known", function()
      local lines = tree.lines({ { status = "M", path = "logo.png" } }, { width = 20 })
      assert.same({ row("logo.png", " M", 20) }, texts(lines))
    end)

    it("puts the marker of a one-sided directory in the same column", function()
      local entries = {
        { status = "A", path = "added/x.lua" },
        { status = "M", path = "both/y.lua" },
        { status = "D", path = "removed/z.lua" },
      }
      local lines = tree.lines(entries, {
        width = 20,
        collapsed = { removed = true },
        dir_status = function(path)
          return ({ added = "A", removed = "D" })[path]
        end,
      })
      assert.same({
        row("▾ added/", " A", 20),
        row("│ x.lua", " A", 20),
        "▾ both/",
        row("│ y.lua", " M", 20),
        row("▸ removed/", " D", 20),
      }, texts(lines))
      assert.equals("A", lines[1].status)
      assert.is_nil(lines[3].status)
    end)
  end)

  describe("icons", function()
    it("shows the icon before a file name and folder glyphs for directories", function()
      local entries = {
        { status = "M", path = "open/a.lua" },
        { status = "M", path = "shut/b.lua" },
        { status = "M", path = "c.txt" },
      }
      local lines = tree.lines(entries, {
        width = 20,
        icon = fake_icon,
        collapsed = { shut = true },
      })
      assert.same({
        "O open/",
        row("│ L a.lua", " M", 20),
        "C shut/",
        row("c.txt", " M", 20),
      }, texts(lines))
      assert.same({ "O" }, highlighted(lines[1], "FolderHl"))
      assert.same({ "L" }, highlighted(lines[2], "LuaHl"))
    end)

    it("uses arrows and no file icon without an icon source", function()
      local lines = tree.lines({ { status = "M", path = "d/a.lua" } }, { width = 20 })
      assert.same({ "▾ d/", row("│ a.lua", " M", 20) }, texts(lines))
    end)
  end)

  describe("giving way", function()
    local function line(width, entry)
      return tree.lines({ entry }, { width = width })[1].text
    end
    local long = { status = "A", path = LONG, added = 40, deleted = 0 }

    it("shows everything when it fits", function()
      assert.equals(row(LONG, " +40 -0 A", 36), line(36, long))
    end)

    it("cuts the name and keeps the counts", function()
      local text = line(30, long)
      assert.equals(tree.cut(LONG, 21) .. " +40 -0 A", text)
      assert.equals(30, cells(text))
      assert.truthy(vim.startswith(text, "kz_028"))
      assert.truthy(text:find(".sql +40 -0 A", 1, true))
    end)

    it("keeps the counts down to the minimum name length", function()
      assert.equals(tree.cut(LONG, 10) .. " +40 -0 A", line(19, long))
    end)

    it("drops the counts when the minimum name does not fit with them", function()
      local text = line(18, long)
      assert.equals(tree.cut(LONG, 16) .. " A", text)
      assert.equals(18, cells(text))
    end)

    it("does not cut a short name to make room for nothing", function()
      local short = { status = "M", path = "a.lua", added = 1234, deleted = 5678 }
      assert.equals(row("a.lua", " +1234 -5678 M", 19), line(19, short))
      assert.equals(row("a.lua", " M", 18), line(18, short))
    end)

    it("always ends with the status letter, however narrow", function()
      local entries = {
        { status = "M", path = "deep/er/" .. LONG, added = 1, deleted = 2 },
        { status = "R", path = "b.lua", old_path = "a.lua", added = 0, deleted = 0 },
      }
      for width = 1, 40 do
        local lines = tree.lines(entries, {
          width = width,
          dir_status = function()
            return "A"
          end,
        })
        for _, l in ipairs(lines) do
          assert.is_true(cells(l.text) <= width, ("%q at width %d"):format(l.text, width))
          assert.truthy(l.text:match("[AMDR]$"), ("%q at width %d"):format(l.text, width))
        end
      end
    end)

    it("keeps the highlights of what is left in a squeezed line", function()
      local lines = tree.lines({ { status = "M", path = "a/b/c/d/file.lua" } }, {
        width = 5,
        icon = fake_icon,
      })
      assert.equals("O a…/", lines[1].text)
      local file = lines[2]
      assert.equals("│ L M", file.text)
      assert.same({ "│ " }, highlighted(file, "TwintreeGuide"))
      assert.same({ "L" }, highlighted(file, "LuaHl"))
      assert.same({ "M" }, highlighted(file, "TwintreeModified"))

      local dir = tree.lines({ { status = "M", path = "a/b" } }, {
        width = 3,
        icon = fake_icon,
        dir_status = function()
          return "A"
        end,
      })[1]
      assert.equals("O A", dir.text)
      assert.same({ "O" }, highlighted(dir, "FolderHl"))
    end)

    it("treats a width below one as one", function()
      assert.equals("M", line(0, { status = "M", path = "a.lua" }))
    end)
  end)

  describe("rename origin", function()
    local same_dir = {
      status = "R",
      path = "pkg/client.go",
      old_path = "pkg/api.go",
      added = 2,
      deleted = 1,
    }

    it("is the old file name for a rename within a directory", function()
      local lines = tree.lines({ same_dir }, { width = 28 })
      assert.equals(row("│ client.go ← api.go", " +2 -1 R", 28), lines[2].text)
      assert.same({ " ← api.go" }, highlighted(lines[2], "TwintreeOrigin"))
    end)

    it("is the old path for a rename into another directory", function()
      local moved = { status = "R", path = "new/api.go", old_path = "old/api.go" }
      local lines = tree.lines({ moved }, { width = 30 })
      assert.equals(row("│ api.go ← old/api.go", " R", 30), lines[2].text)
    end)

    it("is the old file name for a rename at the top level", function()
      local top = { status = "R", path = "b.lua", old_path = "a.lua" }
      assert.equals(row("b.lua ← a.lua", " R", 20), tree.lines({ top }, { width = 20 })[1].text)
    end)

    it("is left out when one cell is missing", function()
      local lines = tree.lines({ same_dir }, { width = 27 })
      assert.equals(row("│ client.go", " +2 -1 R", 27), lines[2].text)
    end)
  end)

  describe("names", function()
    it("shows control characters as escapes on one line", function()
      local entries = {
        { status = "A", path = "dir\nx/a\nb.txt" },
        { status = "R", old_path = "old\tname", path = "new" },
      }
      local lines = tree.lines(entries, { width = 30 })
      assert.same({
        "▾ dir\\nx/",
        row("│ a\\nb.txt", " A", 30),
        row("new ← old\\x09name", " R", 30),
      }, texts(lines))
      assert.equals("dir\nx/a\nb.txt", lines[2].path)
    end)

    it("aligns names with wide and non-ASCII characters", function()
      local entries = {
        { status = "M", path = "файл.txt", added = 1, deleted = 1 },
        { status = "M", path = "日本語のとても長いファイル名前です.txt", added = 1, deleted = 1 },
      }
      for _, l in ipairs(tree.lines(entries, { width = 24 })) do
        assert.equals(24, cells(l.text))
        assert.truthy(l.text:find(".txt", 1, true))
        assert.truthy(l.text:match(" %+1 %-1 M$"))
      end
    end)

    it("cuts a long directory chain in the middle", function()
      local lines = tree.lines({ { status = "M", path = "a/very/long/chain/of/dirs/f.go" } }, {
        width = 16,
        dir_status = function()
          return "A"
        end,
      })
      assert.equals(16, cells(lines[1].text))
      assert.truthy(lines[1].text:match("^▾ a/.*….*dirs/ A$"))
    end)
  end)

  describe("indent guides", function()
    it("draws one per level of nesting", function()
      local lines = tree.lines({
        { status = "M", path = "a/b.lua" },
        { status = "M", path = "a/c/d/e.lua" },
        { status = "M", path = "top.lua" },
      }, { width = 20 })
      assert.same({
        "▾ a/",
        "│ ▾ c/d/",
        row("│ │ e.lua", " M", 20),
        row("│ b.lua", " M", 20),
        row("top.lua", " M", 20),
      }, texts(lines))
      assert.same({ "│ │ " }, highlighted(lines[3], "TwintreeGuide"))
      assert.same({}, highlighted(lines[5], "TwintreeGuide"))
    end)
  end)

  describe("highlights", function()
    it("cover each piece by byte range, also after non-ASCII text", function()
      local lines = tree.lines({
        { status = "M", path = "каталог/файл.lua", added = 5, deleted = 3 },
      }, {
        width = 30,
        icon = fake_icon,
        dir_status = function()
          return "D"
        end,
      })
      assert.same({ "O" }, highlighted(lines[1], "FolderHl"))
      assert.same({ "каталог/" }, highlighted(lines[1], "TwintreeDirectory"))
      assert.same({ "D" }, highlighted(lines[1], "TwintreeDeleted"))

      assert.same({ "│ " }, highlighted(lines[2], "TwintreeGuide"))
      assert.same({ "L" }, highlighted(lines[2], "LuaHl"))
      assert.same({ "+5" }, highlighted(lines[2], "TwintreeAdded"))
      assert.same({ "-3" }, highlighted(lines[2], "TwintreeDeleted"))
      assert.same({ "M" }, highlighted(lines[2], "TwintreeModified"))
    end)

    it("use the group of each status", function()
      local groups = {
        A = "TwintreeAdded",
        M = "TwintreeModified",
        D = "TwintreeDeleted",
        R = "TwintreeRenamed",
      }
      for status, group in pairs(groups) do
        local line = tree.lines({ { status = status, path = "f" } }, { width = 10 })[1]
        assert.same({ status }, highlighted(line, group))
      end
    end)
  end)
end)

describe("with ambiguous-width characters two cells wide", function()
  before_each(function()
    vim.o.ambiwidth = "double"
  end)

  after_each(function()
    vim.o.ambiwidth = "single"
  end)

  it("measures the ellipsis instead of assuming one cell", function()
    assert.equals(2, cells("…"))
    for room = 0, 30 do
      local cut = tree.cut(LONG, room)
      assert.is_true(cells(cut) <= room, ("%q for %d"):format(cut, room))
    end
    assert.equals("…", tree.cut(LONG, 2))
    assert.equals("k", tree.cut(LONG, 1))
    assert.truthy(tree.cut(LONG, 14):match("%.sql$"))
  end)

  it("keeps every line within the width", function()
    local entries = {
      { status = "A", path = "deep/er/" .. LONG, added = 40, deleted = 0 },
      { status = "R", path = "b.lua", old_path = "a.lua", added = 1, deleted = 1 },
    }
    for width = 1, 45 do
      for _, line in ipairs(tree.lines(entries, { width = width })) do
        assert.is_true(
          cells(line.text) <= width,
          ("%q is %d cells at width %d"):format(line.text, cells(line.text), width)
        )
        if line.type == "file" then
          assert.truthy(line.text:match("[AMDR]$"), line.text)
        end
      end
    end
  end)
end)

describe("tree.cut", function()
  it("leaves a name that fits alone", function()
    assert.equals("a.lua", tree.cut("a.lua", 5))
    assert.equals("a.lua", tree.cut("a.lua", 50))
  end)

  it("keeps the beginning and the extension", function()
    local cut = tree.cut(LONG, 20)
    assert.equals(20, cells(cut))
    assert.equals("kz_028_pro…vents.sql", cut)
  end)

  it("keeps a long extension whole when it fits", function()
    assert.equals("abcdef….markdown", tree.cut("abcdefgh_description.markdown", 16))
    assert.equals("a….markdown", tree.cut("abcdefgh.markdown", 11))
  end)

  it("gives up on an extension longer than the room", function()
    assert.equals("abc…own", tree.cut("abcdefgh.markdown", 7))
  end)

  it("cuts a name without an extension in half", function()
    assert.equals("Make…file", tree.cut("Makefile_for_everything_file", 9))
    assert.equals(".git…_ore", tree.cut(".gitignore_but_very_long_ore", 9))
  end)

  it("handles very little room", function()
    assert.equals("", tree.cut("abcdef", 0))
    assert.equals("…", tree.cut("abcdef", 1))
    assert.equals("a…", tree.cut("abcdef", 2))
    assert.equals("a…f", tree.cut("abcdef", 3))
  end)

  it("can come out two cells short around wide characters", function()
    assert.equals("日…語", tree.cut("日本語日本語日本語", 7))
  end)

  it("never splits a wide character", function()
    local name = "日本語のファイル名前.txt"
    for room = 1, 24 do
      local cut = tree.cut(name, room)
      assert.is_true(cells(cut) <= room, ("%q for %d"):format(cut, room))
      assert.is_true(vim.fn.strchars(cut) > 0)
    end
    assert.truthy(tree.cut(name, 12):match("%.txt$"))
  end)
end)
