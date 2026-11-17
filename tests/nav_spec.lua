local h = require("tests.helpers")
local nav = require("twintree.nav")
local session = require("twintree.session")
local treeview = require("twintree.treeview")
local twintree = require("twintree")

local api = vim.api

local INFO, ERROR = vim.log.levels.INFO, vim.log.levels.ERROR

---`count` numbered lines as file text, after `edit` changed the list.
local function text(count, edit)
  local lines = {}
  for i = 1, count do
    lines[i] = "line " .. i
  end
  if edit then
    edit(lines)
  end
  return table.concat(lines, "\n") .. "\n"
end

describe("moving between changed files", function()
  local repo, tab, messages, notify

  -- The files of the tree in its order.
  local ORDER = { "d1/x.txt", "d1/y.txt", "d2/z.txt", "a.txt", "b.txt", "c.txt", "d.txt" }

  local function state()
    return assert(session.get(tab))
  end

  local function name(win)
    return api.nvim_buf_get_name(api.nvim_win_get_buf(win))
  end

  local function line(win)
    return api.nvim_win_get_cursor(win)[1]
  end

  ---The changed file the after pane shows, as a path of the repository.
  local function shown()
    local path = name(state().wins.after)
    return vim.startswith(path, repo .. "/") and path:sub(#repo + 2) or path
  end

  local function run(action, count)
    return nav.run(action, count)
  end

  ---Go to a file of the list by selecting it in the tree.
  local function select(path)
    local s = state()
    for _, file in ipairs(treeview.files(tab)) do
      if file.entry.path == path then
        assert(session.show(tab, file.entry))
        return
      end
    end
    error("not a changed file: " .. path .. " " .. vim.inspect(s.selected))
  end

  local function collapse(path)
    local s = state()
    s.collapsed[path] = true
    session.save(tab, s)
    treeview.draw(tab)
  end

  ---Take the after pane to a file, as a jump to a definition would.
  local function jump(path)
    api.nvim_set_current_win(state().wins.after)
    vim.cmd.edit(vim.fn.fnameescape(repo .. "/" .. path))
  end

  local function refresh()
    api.nvim_set_current_tabpage(tab)
    treeview.refresh()
  end

  local function marked_lines()
    local s = state()
    local ns = api.nvim_get_namespaces().twintree
    local lines = h.tree_lines(s.tree_buf)
    local result = {}
    for _, mark in ipairs(api.nvim_buf_get_extmarks(s.tree_buf, ns, 0, -1, { details = true })) do
      if mark[4].line_hl_group == "TwintreeSelected" then
        table.insert(result, lines[mark[2] + 1])
      end
    end
    return result
  end

  ---Open a diff of a repository with `files` committed and `changes`
  ---written on top.
  local function open(files, changes)
    repo = h.repo(files)
    for path, content in pairs(changes) do
      h.write(repo, path, content)
    end
    api.nvim_set_current_dir(repo)
    tab = assert(twintree.open())
    -- Opening reports the checkout of the before side.
    messages = {}
  end

  local function open_default()
    local files = { ["bb.txt"] = "same\n", ["zz.txt"] = "same too\n" }
    local changes = {}
    for _, path in ipairs(ORDER) do
      files[path] = path .. "\n"
      changes[path] = path .. " changed\n"
    end
    files["d1/x.txt"], files["c.txt"] = text(100), text(100)
    local function change(lines)
      lines[60] = "changed"
    end
    changes["d1/x.txt"], changes["c.txt"] = text(100, change), text(100, change)
    open(files, changes)
  end

  before_each(function()
    h.reset()
    vim.o.columns = 160
    messages = {}
    notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(messages, { msg = msg, level = level })
    end
  end)

  after_each(function()
    vim.notify = notify
    vim.o.columns = 80
  end)

  describe("with several changed files", function()
    before_each(open_default)

    it("lists the files in the order the specs rely on", function()
      local paths = vim.tbl_map(function(file)
        return file.entry.path
      end, treeview.files(tab))
      assert.same(ORDER, paths)
      assert.equals("d1/x.txt", shown())
    end)

    it("goes to the next and the previous file", function()
      assert.is_true(run("next"))
      assert.equals("d1/y.txt", shown())
      local s = state()
      assert.equals(s.before.root .. "/d1/y.txt", name(s.wins.before))
      assert.is_true(vim.wo[s.wins.before].diff)
      assert.is_true(vim.wo[s.wins.after].diff)
      assert.equals("d1/y.txt", s.selected)
      assert.same({ "│ y.txt +1 -1 M" }, marked_lines())

      assert.is_true(run("prev"))
      assert.equals("d1/x.txt", shown())
      assert.same({}, messages)
    end)

    it("goes from a file in a directory to the top-level file below it", function()
      select("d2/z.txt")
      run("next")
      assert.equals("a.txt", shown())
    end)

    it("goes to the first and the last file", function()
      assert.is_true(run("last"))
      assert.equals("d.txt", shown())
      assert.is_true(run("first"))
      assert.equals("d1/x.txt", shown())
      assert.same({}, messages)
    end)

    it("leaves the first file alone when it is already shown", function()
      local after = state().wins.after
      api.nvim_set_current_win(after)
      h.keys("70G")
      assert.is_true(run("first"))
      assert.equals("d1/x.txt", shown())
      assert.equals(70, line(after))
      assert.is_true(vim.wo[after].diff)
      assert.same({}, messages)
    end)

    it("moves by a count", function()
      run("next", 3)
      assert.equals("a.txt", shown())
      run("prev", 2)
      assert.equals("d1/y.txt", shown())
    end)

    it("stops at the last file for a count past the end", function()
      select("b.txt")
      assert.is_true(run("next", 5))
      assert.equals("d.txt", shown())
      assert.same({}, messages)
    end)

    it("stops at the first file for a count past the start", function()
      select("d2/z.txt")
      assert.is_true(run("prev", 5))
      assert.equals("d1/x.txt", shown())
      assert.same({}, messages)
    end)

    it("puts the cursor on the first change of a file not shown before", function()
      select("b.txt")
      run("next")
      local s = state()
      assert.equals("c.txt", shown())
      assert.equals(60, line(s.wins.after))
      assert.equals(60, line(s.wins.before))
    end)

    it("leaves the cursor of a file shown before where it was", function()
      select("c.txt")
      api.nvim_set_current_win(state().wins.after)
      h.keys("80G")
      run("next")
      assert.equals("d.txt", shown())
      run("prev")
      assert.equals("c.txt", shown())
      assert.equals(80, line(state().wins.after))
    end)

    describe("at the ends", function()
      local function assert_end(action, file)
        local s = state()
        local before, after = name(s.wins.before), name(s.wins.after)
        assert.is_false(run(action))
        assert.same({ { msg = "twintree: no more changed files", level = INFO } }, messages)
        assert.equals(file, shown())
        assert.equals(before, name(s.wins.before))
        assert.equals(after, name(s.wins.after))
        assert.equals(file, state().selected)
      end

      it("reports the end for next on the last file", function()
        select("d.txt")
        assert_end("next", "d.txt")
      end)

      it("reports the end for previous on the first file", function()
        assert_end("prev", "d1/x.txt")
      end)

      it("reports a list that a refresh emptied and keeps the panes", function()
        for _, path in ipairs(ORDER) do
          h.git(repo, "checkout", "-q", "--", path)
        end
        refresh()
        assert.same({ "No changes" }, h.tree_lines(state().tree_buf))
        for _, action in ipairs({ "next", "prev", "first", "last" }) do
          assert.is_false(run(action))
        end
        assert.equals(4, #messages)
        for _, message in ipairs(messages) do
          assert.same({ msg = "twintree: no changed files", level = INFO }, message)
        end
        assert.equals("d1/x.txt", shown())
      end)
    end)

    describe("collapsed directories", function()
      it("are skipped and stay collapsed", function()
        select("d1/y.txt")
        collapse("d2")
        run("next")
        assert.equals("a.txt", shown())
        assert.is_true(state().collapsed.d2)
        run("prev")
        assert.equals("d1/y.txt", shown())
      end)

      it("are left behind when the current file is inside one", function()
        collapse("d1")
        assert.equals("d1/x.txt", shown())
        run("next")
        assert.equals("d2/z.txt", shown())
        assert.is_true(state().collapsed.d1)
      end)

      it("have no previous file when the current file is in the first one", function()
        collapse("d1")
        assert.is_false(run("prev"))
        assert.same({ { msg = "twintree: no more changed files", level = INFO } }, messages)
      end)

      it("are ignored by first and last", function()
        select("b.txt")
        collapse("d1")
        run("first")
        assert.equals("d2/z.txt", shown())
      end)
    end)

    describe("the position", function()
      it("is the changed file shown last after a jump to another file", function()
        select("d1/y.txt")
        jump("zz.txt")
        local s = state()
        assert.is_nil(s.selected)
        assert.equals("d1/y.txt", s.last_entry)

        run("next")
        assert.equals("d2/z.txt", shown())
        assert.equals("d2/z.txt", state().last_entry)
      end)

      it("is relative to that file for previous as well", function()
        select("d1/y.txt")
        jump("zz.txt")
        run("prev")
        assert.equals("d1/x.txt", shown())
      end)

      it("is kept for a session saved before the last file was recorded", function()
        select("d1/y.txt")
        local s = state()
        s.last_entry = nil
        session.save(tab, s)
        jump("zz.txt")
        assert.equals("d1/y.txt", state().last_entry)
        run("next")
        assert.equals("d2/z.txt", shown())
      end)

      it("is nothing after a refresh that dropped the file shown last", function()
        select("b.txt")
        h.git(repo, "checkout", "-q", "--", "b.txt")
        refresh()
        assert.is_nil(state().selected)
        run("next")
        assert.equals("d1/x.txt", shown())
      end)

      it("is a file that a refresh put into the list", function()
        select("b.txt")
        jump("bb.txt")
        h.write(repo, "bb.txt", "changed\n")
        refresh()
        local s = state()
        assert.equals("bb.txt", s.selected)
        assert.equals("bb.txt", s.last_entry)

        jump("zz.txt")
        run("next")
        assert.equals("c.txt", shown())
      end)

      it("survives a tree buffer that was deleted and rebuilt", function()
        select("d1/y.txt")
        jump("zz.txt")
        local old = state().tree_buf
        api.nvim_buf_delete(old, { force = true })

        assert.is_true(run("next"))
        assert.equals("d2/z.txt", shown())
        assert.are_not.equal(old, state().tree_buf)
        assert.same({}, messages)
      end)
    end)

    describe("the current window", function()
      it("stays the before pane", function()
        local s = state()
        api.nvim_set_current_win(s.wins.before)
        run("next")
        assert.equals("d1/y.txt", shown())
        assert.equals(s.wins.before, api.nvim_get_current_win())
      end)

      it("stays the tree, with its cursor on the file", function()
        local s = state()
        local tree = assert(session.tree_win(s))
        api.nvim_set_current_win(tree)
        run("next", 4)
        assert.equals("b.txt", shown())
        assert.equals(tree, api.nvim_get_current_win())
        local row = line(tree)
        assert.equals("b.txt +1 -1 M", h.tree_lines(s.tree_buf)[row])
      end)

      it("stays a window the user split off, which keeps its buffer", function()
        api.nvim_set_current_win(state().wins.before)
        vim.cmd("new")
        local own, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
        run("next")
        assert.equals("d1/y.txt", shown())
        assert.equals(own, api.nvim_get_current_win())
        assert.equals(buf, api.nvim_win_get_buf(own))
        assert.is_false(vim.wo[own].diff)
      end)

      it("is left alone by show when asked, and entered otherwise", function()
        local s = state()
        local tree = assert(session.tree_win(s))
        api.nvim_set_current_win(tree)
        local files = treeview.files(tab)
        assert(session.show(tab, files[6].entry, { keep_focus = true }))
        assert.equals("c.txt", shown())
        assert.equals(tree, api.nvim_get_current_win())
        assert.equals(60, line(s.wins.after))
        assert.equals(60, line(s.wins.before))

        h.goto_line(tree, "d.txt")
        h.keys("<CR>")
        assert.equals("d.txt", shown())
        assert.equals(s.wins.after, api.nvim_get_current_win())
      end)
    end)
  end)

  it("reports the end with one changed file", function()
    open({ ["a.txt"] = "a\n", ["b.txt"] = "b\n" }, { ["a.txt"] = "A\n" })
    assert.is_false(run("next"))
    assert.is_false(run("prev"))
    assert.same({
      { msg = "twintree: no more changed files", level = INFO },
      { msg = "twintree: no more changed files", level = INFO },
    }, messages)
    assert.equals("a.txt", shown())
  end)

  it("reports a diff without changed files", function()
    open({ ["a.txt"] = "a\n" }, {})
    for _, action in ipairs({ "next", "prev", "first", "last" }) do
      assert.is_false(run(action))
    end
    assert.equals(4, #messages)
    for _, message in ipairs(messages) do
      assert.same({ msg = "twintree: no changed files", level = INFO }, message)
    end
    assert.equals("twintree://empty", name(state().wins.after))
  end)

  it("reports that every changed file is in a collapsed directory", function()
    open({ ["d/a.txt"] = "a\n", ["d/b.txt"] = "b\n" }, { ["d/a.txt"] = "A\n", ["d/b.txt"] = "B\n" })
    collapse("d")
    for _, action in ipairs({ "next", "prev", "first", "last" }) do
      assert.is_false(run(action))
    end
    assert.equals(4, #messages)
    for _, message in ipairs(messages) do
      assert.same({
        msg = "twintree: every changed file is in a collapsed directory",
        level = INFO,
      }, message)
    end
    assert.equals("d/a.txt", shown())
  end)

  it("takes the last visible file when the last file is in a collapsed directory", function()
    local files, changes = {}, {}
    for _, path in ipairs({ "d/a.txt", "d/b.txt", "e/c.txt" }) do
      files[path], changes[path] = "old\n", "new\n"
    end
    open(files, changes)
    collapse("e")
    assert.is_true(run("last"))
    assert.equals("d/b.txt", shown())
    assert.is_false(run("next"))
    assert.same({ { msg = "twintree: no more changed files", level = INFO } }, messages)
  end)

  describe("with nothing shown yet", function()
    before_each(function()
      -- Opened before the files change, so that the panes start empty.
      repo = h.repo({ ["a.txt"] = "a\n", ["b.txt"] = "b\n", ["c.txt"] = "c\n" })
      api.nvim_set_current_dir(repo)
      tab = assert(twintree.open())
      for _, path in ipairs({ "a.txt", "b.txt", "c.txt" }) do
        h.write(repo, path, "changed\n")
      end
      refresh()
      assert.is_nil(state().selected)
      assert.is_nil(state().last_entry)
      messages = {}
    end)

    it("next shows the first file", function()
      assert.is_true(run("next"))
      assert.equals("a.txt", shown())
      assert.equals("a.txt", state().last_entry)
    end)

    it("previous shows the last file", function()
      assert.is_true(run("prev"))
      assert.equals("c.txt", shown())
    end)
  end)

  describe("commands", function()
    it("are registered", function()
      local commands = api.nvim_get_commands({})
      for _, command in ipairs({ "NextFile", "PrevFile", "FirstFile", "LastFile" }) do
        assert.truthy(commands["Twintree" .. command], command)
      end
    end)

    it("move as their names say, next and previous with a count", function()
      open_default()
      vim.cmd("3TwintreeNextFile")
      assert.equals("a.txt", shown())
      vim.cmd("TwintreeNextFile")
      assert.equals("b.txt", shown())
      vim.cmd("2TwintreePrevFile")
      assert.equals("d2/z.txt", shown())
      vim.cmd("TwintreePrevFile")
      assert.equals("d1/y.txt", shown())
      vim.cmd("TwintreeLastFile")
      assert.equals("d.txt", shown())
      vim.cmd("TwintreeFirstFile")
      assert.equals("d1/x.txt", shown())
      assert.same({}, messages)
    end)

    it("report the end of the list as information", function()
      open_default()
      vim.cmd("TwintreePrevFile")
      vim.cmd("TwintreeLastFile")
      vim.cmd("TwintreeNextFile")
      assert.same({
        { msg = "twintree: no more changed files", level = INFO },
        { msg = "twintree: no more changed files", level = INFO },
      }, messages)
    end)

    it("report a tab without a diff session as an error", function()
      for _, command in ipairs({ "NextFile", "PrevFile", "FirstFile", "LastFile" }) do
        vim.cmd("Twintree" .. command)
      end
      assert.equals(4, #messages)
      for _, message in ipairs(messages) do
        assert.same({ msg = "twintree: " .. session.NO_SESSION, level = ERROR }, message)
      end
    end)
  end)

  it("reports a tab without a diff session", function()
    for _, action in ipairs({ "next", "prev", "first", "last" }) do
      assert.is_false(run(action))
    end
    assert.equals(4, #messages)
    for _, message in ipairs(messages) do
      assert.same({ msg = "twintree: " .. session.NO_SESSION, level = ERROR }, message)
    end
  end)
end)
