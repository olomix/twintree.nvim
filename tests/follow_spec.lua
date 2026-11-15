local h = require("tests.helpers")
local session = require("twintree.session")
local twintree = require("twintree")

local api = vim.api

local EMPTY = "twintree://empty"

describe("following", function()
  local repo, tab, outside

  local function state()
    return assert(session.get(tab))
  end

  local function name(win)
    return api.nvim_buf_get_name(api.nvim_win_get_buf(win))
  end

  local function before_path(path)
    return state().before.root .. "/" .. path
  end

  local function after_path(path)
    return repo .. "/" .. path
  end

  ---The tree window. A function so that luassert's extra return values
  ---never end up as arguments of the caller.
  local function tree()
    local win = session.tree_win(state())
    assert.truthy(win)
    return win
  end

  local function select(text)
    h.goto_line(tree(), text)
    h.keys("<CR>")
  end

  ---Make `pane` current and open a file in it.
  local function edit(pane, path)
    api.nvim_set_current_win(state().wins[pane])
    vim.cmd.edit(vim.fn.fnameescape(path))
  end

  local function assert_panes(before, after)
    local s = state()
    assert.equals(before, name(s.wins.before))
    assert.equals(after, name(s.wins.after))
    assert.is_true(vim.wo[s.wins.before].diff)
    assert.is_true(vim.wo[s.wins.after].diff)
  end

  ---Lines of the tree that carry the mark of the selected file.
  local function marked()
    local s = state()
    local ns = api.nvim_get_namespaces().twintree
    local lines = h.buf_lines(s.tree_buf)
    local result = {}
    local marks = api.nvim_buf_get_extmarks(s.tree_buf, ns, 0, -1, { details = true })
    for _, mark in ipairs(marks) do
      if mark[4].line_hl_group == "TwintreeSelected" then
        table.insert(result, lines[mark[2] + 1])
      end
    end
    return result
  end

  ---Whether a line of a pane is highlighted as changed.
  local function has_changes(win)
    return api.nvim_win_call(win, function()
      vim.cmd.diffupdate()
      for lnum = 1, vim.fn.line("$") do
        if vim.fn.diff_hlID(lnum, 1) ~= 0 then
          return true
        end
      end
      return false
    end)
  end

  ---Open the quickfix entry `path:lnum` with `win` current, and wait for
  ---the file to have reached the window it belongs to.
  local function quickfix_jump(win, path, lnum, target)
    vim.fn.setqflist({ { filename = path, lnum = lnum, col = 1 } })
    api.nvim_set_current_win(win)
    vim.cmd("cc 1")
    assert.is_true(vim.wait(1000, function()
      return name(target) == path
    end, 10))
  end

  before_each(function()
    h.reset()
    local long = {}
    for i = 1, 200 do
      long[i] = "line " .. i
    end
    local text = table.concat(long, "\n") .. "\n"
    repo = h.repo({
      ["a.txt"] = "one\ntwo\nthree\n",
      ["same.txt"] = "same 1\nsame 2\nsame 3\n",
      ["other.txt"] = "other\n",
      ["src/deep/b.txt"] = "b1\nb2\nb3\nb4\n",
      ["gone.txt"] = "gone\n",
      ["long.txt"] = text,
    })
    h.write(repo, "a.txt", "one\nTWO\nthree\n")
    h.write(repo, "new.txt", "new\n")
    h.write(repo, "long.txt", ("added\n"):rep(10) .. text)
    h.git(repo, "rm", "-q", "gone.txt")
    h.git(repo, "mv", "src/deep/b.txt", "src/deep/c.txt")
    outside = h.tmpdir() .. "/dep.txt"
    h.write(vim.fs.dirname(outside), "dep.txt", "dep 1\ndep 2\n")

    api.nvim_set_current_dir(repo)
    tab = assert(twintree.open())
    select("a.txt")
  end)

  describe("classifying a buffer", function()
    it("tells the sides apart", function()
      local s = state()
      assert.same({ "before", "a.txt" }, { session.side_of(s, before_path("a.txt")) })
      assert.same({ "after", "src/x.txt" }, { session.side_of(s, after_path("src/x.txt")) })
      assert.same({}, { session.side_of(s, outside) })
    end)

    it("classifies a file that does not exist yet", function()
      assert.same(
        { "after", "not-yet.txt" },
        { session.side_of(state(), after_path("not-yet.txt")) }
      )
    end)

    it("resolves a path that reaches a side through a symbolic link", function()
      local link = h.tmpdir() .. "/link"
      assert(vim.uv.fs_symlink(repo, link))
      assert.same({ "after", "a.txt" }, { session.side_of(state(), link .. "/a.txt") })
    end)

    it("lets the longer root win when one side is inside the other", function()
      local s = state()
      s.before.root = repo .. "/nested"
      assert.same({ "before", "a.txt" }, { session.side_of(s, repo .. "/nested/a.txt") })
      assert.same({ "after", "a.txt" }, { session.side_of(s, repo .. "/a.txt") })
    end)

    it("prefers the given side when both have the same root", function()
      local s = state()
      s.before.root = repo
      assert.equals("after", (session.side_of(s, repo .. "/a.txt", "after")))
      assert.equals("before", (session.side_of(s, repo .. "/a.txt", "before")))
    end)

    it("knows which buffers are files", function()
      assert.is_true(session.is_file_buf(vim.fn.bufadd(after_path("a.txt"))))
      assert.is_true(session.is_file_buf(vim.fn.bufadd(after_path("not-yet.txt"))))
      assert.is_false(session.is_file_buf(api.nvim_create_buf(true, false)))
      local scratch = api.nvim_create_buf(false, true)
      api.nvim_buf_set_name(scratch, "scratch-with-a-name")
      assert.is_false(session.is_file_buf(scratch))
      local term = api.nvim_create_buf(false, false)
      api.nvim_open_term(term, {})
      assert.is_false(session.is_file_buf(term))
    end)
  end)

  describe("pairing a file", function()
    it("pairs an unchanged file with the same path", function()
      local expected = { before = before_path("same.txt"), after = after_path("same.txt") }
      assert.same(expected, session.pair_of(state(), before_path("same.txt")))
      assert.same(expected, session.pair_of(state(), after_path("same.txt")))
    end)

    it("pairs a renamed file with its other name", function()
      local expected = {
        before = before_path("src/deep/b.txt"),
        after = after_path("src/deep/c.txt"),
      }
      assert.same(expected, session.pair_of(state(), before_path("src/deep/b.txt")))
      assert.same(expected, session.pair_of(state(), after_path("src/deep/c.txt")))
    end)

    it("leaves a side empty when the file is missing there", function()
      assert.same(
        { before = before_path("gone.txt") },
        session.pair_of(state(), before_path("gone.txt"))
      )
      assert.same({ after = after_path("new.txt") }, session.pair_of(state(), after_path("new.txt")))
    end)

    it("leaves a side empty when the path is a directory there", function()
      vim.fn.mkdir(repo .. "/gone.txt")
      assert.same(
        { before = before_path("gone.txt") },
        session.pair_of(state(), before_path("gone.txt"))
      )
    end)

    it("pairs a file outside both sides with itself", function()
      assert.same({ before = outside, after = outside }, session.pair_of(state(), outside))
    end)

    it("falls back to the same path when the tree buffer was deleted", function()
      api.nvim_buf_delete(state().tree_buf, { force = true })
      assert.same(
        { before = before_path("src/deep/b.txt") },
        session.pair_of(state(), before_path("src/deep/b.txt"))
      )
      assert.same(
        { before = before_path("a.txt"), after = after_path("a.txt") },
        session.pair_of(state(), after_path("a.txt"))
      )
    end)

    it("finds the entry of a rename whose old path a new file took", function()
      local s = state()
      vim.b[s.tree_buf].twintree_entries = {
        { path = "a.txt", status = "A" },
        { path = "z.txt", old_path = "a.txt", status = "R" },
      }
      local renamed = { before = before_path("a.txt"), after = after_path("z.txt") }
      assert.equals("z.txt", session.entry_path(s, renamed))
      assert.equals("z.txt", session.entry_path(s, { before = before_path("a.txt") }))
      local added = { before = before_path("a.txt"), after = after_path("a.txt") }
      assert.equals("a.txt", session.entry_path(s, added))
    end)

    it("finds the tree entry of a pair", function()
      local s = state()
      local function entry_of(path)
        return session.entry_path(s, session.pair_of(s, path))
      end
      assert.equals("a.txt", entry_of(before_path("a.txt")))
      assert.equals("src/deep/c.txt", entry_of(before_path("src/deep/b.txt")))
      assert.equals("src/deep/c.txt", entry_of(after_path("src/deep/c.txt")))
      assert.equals("gone.txt", entry_of(before_path("gone.txt")))
      assert.equals("new.txt", entry_of(after_path("new.txt")))
      assert.is_nil(entry_of(after_path("same.txt")))
      assert.is_nil(entry_of(outside))
    end)
  end)

  describe("a jump inside a pane", function()
    it("in the before pane takes the after pane along", function()
      edit("before", before_path("same.txt"))
      assert_panes(before_path("same.txt"), after_path("same.txt"))
      assert.equals(state().wins.before, api.nvim_get_current_win())
    end)

    it("in the after pane takes the before pane along", function()
      edit("after", after_path("same.txt"))
      assert_panes(before_path("same.txt"), after_path("same.txt"))
      assert.equals(state().wins.after, api.nvim_get_current_win())
    end)

    it("loads the other side like any file of a cached worktree", function()
      edit("after", after_path("same.txt"))
      local buf = api.nvim_win_get_buf(state().wins.before)
      assert.same({ "same 1", "same 2", "same 3" }, h.buf_lines(buf))
      assert.is_true(vim.bo[buf].readonly)
      assert.is_false(vim.bo[buf].modifiable)
    end)

    it("shows no changes for a file that did not change", function()
      edit("before", before_path("same.txt"))
      assert.is_false(has_changes(state().wins.before))
      assert.is_false(has_changes(state().wins.after))
      assert.is_nil(state().selected)
    end)

    it("shows the changes of a changed file", function()
      edit("before", before_path("same.txt"))
      edit("before", before_path("a.txt"))
      assert_panes(before_path("a.txt"), after_path("a.txt"))
      assert.is_true(has_changes(state().wins.after))
    end)

    it("pairs a renamed file from either pane", function()
      edit("before", before_path("src/deep/b.txt"))
      assert_panes(before_path("src/deep/b.txt"), after_path("src/deep/c.txt"))
      edit("after", after_path("same.txt"))
      edit("after", after_path("src/deep/c.txt"))
      assert_panes(before_path("src/deep/b.txt"), after_path("src/deep/c.txt"))
    end)

    it("shows the placeholder for a file missing on the other side", function()
      edit("before", before_path("gone.txt"))
      assert_panes(before_path("gone.txt"), EMPTY)
      edit("after", after_path("new.txt"))
      assert_panes(EMPTY, after_path("new.txt"))
    end)

    it("pairs a file that is not on disk yet with the placeholder", function()
      edit("after", after_path("not-yet.txt"))
      assert_panes(EMPTY, after_path("not-yet.txt"))
    end)

    it("returns to the previous file through the jump list", function()
      edit("before", before_path("same.txt"))
      h.keys("<C-o>")
      assert_panes(before_path("a.txt"), after_path("a.txt"))
    end)

    it("keeps the previous file as the alternate file of the other pane", function()
      edit("before", before_path("same.txt"))
      api.nvim_set_current_win(state().wins.after)
      assert.equals(after_path("a.txt"), vim.fn.fnamemodify(vim.fn.bufname("#"), ":p"))
    end)

    it("puts the other pane on the corresponding line", function()
      local s = state()
      quickfix_jump(s.wins.before, before_path("long.txt"), 120, s.wins.before)
      assert_panes(before_path("long.txt"), after_path("long.txt"))
      -- Neovim binds the cursors when a command ends, which a test run
      -- never reaches; any command does. `resize_spec` checks it for real.
      h.keys("0")
      assert.same({ 120, 0 }, api.nvim_win_get_cursor(s.wins.before))
      assert.equals(130, api.nvim_win_get_cursor(s.wins.after)[1])
      assert.equals("line 120", api.nvim_win_call(s.wins.after, api.nvim_get_current_line))
      assert.is_true(vim.wo[s.wins.before].scrollbind)
      assert.is_true(vim.wo[s.wins.after].scrollbind)
    end)

    it("shows a file outside both sides in both panes", function()
      edit("before", outside)
      assert_panes(outside, outside)
      assert.is_false(has_changes(state().wins.before))
      assert.equals(state().wins.before, api.nvim_get_current_win())
    end)

    it("makes the new file the selected file", function()
      edit("after", after_path("new.txt"))
      assert.equals("new.txt", state().selected)
      assert.same({ after = after_path("new.txt") }, state().pair)
    end)
  end)

  describe("a buffer that is not a file", function()
    it("gets a plain pane and leaves the other pane alone", function()
      local s = state()
      local term = api.nvim_create_buf(false, false)
      api.nvim_open_term(term, {})
      api.nvim_win_set_buf(s.wins.before, term)

      assert.is_false(vim.wo[s.wins.before].diff)
      assert.is_false(vim.wo[s.wins.before].scrollbind)
      assert.equals(after_path("a.txt"), name(s.wins.after))
      assert.is_true(vim.wo[s.wins.after].diff)
      assert.equals("a.txt", state().selected)
    end)

    it("gives way to the file when the pane returns to it", function()
      local s = state()
      api.nvim_set_current_win(s.wins.before)
      vim.cmd.enew()
      assert.is_false(vim.wo[s.wins.before].diff)

      vim.cmd.buffer(s.bufs.before)
      assert_panes(before_path("a.txt"), after_path("a.txt"))
    end)
  end)

  describe("with a missing pane", function()
    local function assert_untouched(wins, pane, path)
      local s = state()
      assert.same(wins, api.nvim_tabpage_list_wins(tab))
      assert.equals(path, name(s.wins[pane]))
      assert.is_false(vim.wo[s.wins[pane]].diff)
      assert.equals("", vim.v.errmsg)
    end

    it("shows a file of its side without diff mode", function()
      local s = state()
      api.nvim_win_close(s.wins.after, true)
      local wins = api.nvim_tabpage_list_wins(tab)
      vim.v.errmsg = ""

      edit("before", before_path("same.txt"))
      assert_untouched(wins, "before", before_path("same.txt"))
    end)

    it("leaves a file of the other side where it landed", function()
      local s = state()
      api.nvim_win_close(s.wins.before, true)
      local wins = api.nvim_tabpage_list_wins(tab)
      vim.v.errmsg = ""

      edit("after", before_path("same.txt"))
      vim.wait(50)
      assert_untouched(wins, "after", before_path("same.txt"))
    end)

    it("still diffs the remaining pane on its recorded file", function()
      local s = state()
      api.nvim_win_close(s.wins.after, true)
      edit("before", before_path("same.txt"))
      vim.cmd.buffer(s.bufs.before)
      assert.is_true(vim.wo[s.wins.before].diff)
    end)
  end)

  it("ignores windows the user made", function()
    local s = state()
    api.nvim_set_current_win(s.wins.before)
    vim.cmd.split()
    vim.cmd.edit(before_path("same.txt"))
    assert_panes(before_path("a.txt"), after_path("a.txt"))
    assert.equals("a.txt", state().selected)
  end)

  it("keeps a window split off a pane out of the diff", function()
    local s = state()
    local function changed_lines()
      return api.nvim_win_call(s.wins.after, function()
        vim.cmd.diffupdate()
        local lines = {}
        for lnum = 1, vim.fn.line("$") do
          if vim.fn.diff_hlID(lnum, 1) ~= 0 then
            table.insert(lines, lnum)
          end
        end
        return lines
      end)
    end
    assert.same({ 2 }, changed_lines())

    api.nvim_set_current_win(s.wins.before)
    vim.cmd.split()
    local split = api.nvim_get_current_win()
    assert.is_false(vim.wo[split].diff)
    assert.is_false(vim.wo[split].scrollbind)
    assert.equals(before_path("a.txt"), name(split))
    assert.is_true(vim.wo[s.wins.before].diff)

    -- Another file in it does not become a third side of the diff.
    vim.cmd.edit(before_path("long.txt"))
    assert.is_false(vim.wo[split].diff)
    assert.same({ 2 }, changed_lines())
  end)

  describe("a buffer that left a pane", function()
    it("leaves the diff while a window split off the pane shows it", function()
      local s = state()
      api.nvim_set_current_win(s.wins.before)
      vim.cmd.split()
      assert.equals(before_path("a.txt"), name(api.nvim_get_current_win()))

      edit("before", before_path("same.txt"))
      assert_panes(before_path("same.txt"), after_path("same.txt"))
      assert.is_false(has_changes(s.wins.before))
      assert.is_false(has_changes(s.wins.after))
    end)

    it("leaves the diff while another tab shows it", function()
      local s = state()
      vim.cmd.tabnew()
      vim.cmd.edit(after_path("a.txt"))
      api.nvim_set_current_tabpage(tab)

      edit("after", after_path("same.txt"))
      assert_panes(before_path("same.txt"), after_path("same.txt"))
      assert.is_false(has_changes(s.wins.before))
      assert.is_false(has_changes(s.wins.after))
    end)

    it("stays in a diff the user set up in a window of their own", function()
      local s = state()
      api.nvim_set_current_win(s.wins.after)
      vim.cmd.split()
      vim.cmd.diffthis()
      local own = api.nvim_get_current_win()

      edit("after", after_path("same.txt"))
      assert.is_true(vim.wo[own].diff)
      assert.equals(after_path("a.txt"), name(own))
    end)
  end)

  it("leaves another diff tab alone", function()
    local first = tab
    tab = assert(twintree.open())
    select("new.txt")
    edit("after", after_path("same.txt"))
    assert_panes(before_path("same.txt"), after_path("same.txt"))

    tab = first
    assert_panes(before_path("a.txt"), after_path("a.txt"))
    assert.equals("a.txt", state().selected)
  end)

  it("keeps working after the plugin file is sourced again", function()
    vim.cmd.runtime("plugin/twintree.lua")
    assert.equals(1, #api.nvim_get_autocmds({ group = "twintree", event = "BufEnter" }))
    assert.equals(1, #api.nvim_get_autocmds({ group = "twintree", event = "BufWinEnter" }))
    edit("before", before_path("same.txt"))
    assert_panes(before_path("same.txt"), after_path("same.txt"))
  end)

  describe("a file that lands in the pane of the other side", function()
    it("is moved to its own pane with the cursor", function()
      local s = state()
      quickfix_jump(s.wins.after, before_path("same.txt"), 3, s.wins.before)

      assert_panes(before_path("same.txt"), after_path("same.txt"))
      assert.equals(s.wins.before, api.nvim_get_current_win())
      assert.same({ 3, 0 }, api.nvim_win_get_cursor(s.wins.before))
      assert.is_nil(state().selected)
    end)

    it("works in the other direction", function()
      local s = state()
      quickfix_jump(s.wins.before, after_path("long.txt"), 150, s.wins.after)

      assert_panes(before_path("long.txt"), after_path("long.txt"))
      assert.equals(s.wins.after, api.nvim_get_current_win())
      assert.same({ 150, 0 }, api.nvim_win_get_cursor(s.wins.after))
      assert.equals("long.txt", state().selected)
    end)

    it("keeps the alternate file of the pane it landed in", function()
      local s = state()
      quickfix_jump(s.wins.after, before_path("same.txt"), 3, s.wins.before)

      api.nvim_set_current_win(s.wins.after)
      h.keys("<C-^>")
      assert_panes(before_path("a.txt"), after_path("a.txt"))
    end)

    it("gives up when the window it landed in was closed", function()
      local s = state()
      vim.v.errmsg = ""
      edit("after", before_path("same.txt"))
      api.nvim_win_close(s.wins.after, true)
      vim.wait(50)

      assert.equals(before_path("a.txt"), name(s.wins.before))
      assert.equals("", vim.v.errmsg)
    end)

    it("gives up when a layout reset replaced the windows in between", function()
      vim.v.errmsg = ""
      edit("after", before_path("same.txt"))
      assert.is_true(twintree.reset_layout())
      vim.wait(50)

      assert.equals("", vim.v.errmsg)
      assert.equals(3, #api.nvim_tabpage_list_wins(tab))
    end)

    it("gives up when the window shows another buffer by then", function()
      local s = state()
      vim.v.errmsg = ""
      edit("after", before_path("same.txt"))
      vim.cmd.edit(after_path("other.txt"))
      vim.wait(50)

      assert_panes(before_path("other.txt"), after_path("other.txt"))
      assert.equals(s.wins.after, api.nvim_get_current_win())
      assert.equals("", vim.v.errmsg)
    end)
  end)

  describe("the tree window", function()
    it("sends a quickfix entry to the panes", function()
      local s = state()
      quickfix_jump(tree(), before_path("same.txt"), 2, s.wins.before)

      assert.equals(s.tree_buf, api.nvim_win_get_buf(tree()))
      assert_panes(before_path("same.txt"), after_path("same.txt"))
      assert.same({ 2, 0 }, api.nvim_win_get_cursor(s.wins.before))
    end)

    it("refuses to edit a file", function()
      api.nvim_set_current_win(tree())
      local ok, err = pcall(vim.cmd.edit, after_path("same.txt"))
      assert.is_false(ok)
      assert.truthy(tostring(err):find("E1513", 1, true))
      assert.equals(state().tree_buf, api.nvim_win_get_buf(tree()))
    end)

    it("is hidden when its buffer is deleted, and comes back", function()
      api.nvim_buf_delete(state().tree_buf, { force = true })
      assert.is_nil(session.tree_win(state()))
      assert_panes(before_path("a.txt"), after_path("a.txt"))

      assert.is_true(twintree.toggle_tree())
      assert.truthy(vim.tbl_contains(h.buf_lines(state().tree_buf), "M a.txt"))
      assert.same({ "M a.txt" }, marked())
    end)

    it("can be opened in a window that was the tree of an earlier diff", function()
      vim.cmd("silent! tabonly!")
      api.nvim_set_current_win(tree())
      vim.cmd("only!")
      vim.cmd("%bwipeout!")
      assert.is_true(vim.wo.winfixbuf)

      tab = assert(twintree.open())
      assert.equals(1, #api.nvim_list_tabpages())
      assert.equals(state().tree_buf, api.nvim_win_get_buf(tree()))
    end)
  end)

  describe("the mark in the tree", function()
    it("moves to a changed file reached by a jump", function()
      edit("after", after_path("new.txt"))
      assert.same({ "A new.txt" }, marked())
      assert.equals("A new.txt", api.nvim_win_call(tree(), api.nvim_get_current_line))
      assert.equals(state().wins.after, api.nvim_get_current_win())
    end)

    it("disappears on a file that did not change", function()
      edit("after", after_path("same.txt"))
      assert.same({}, marked())
    end)

    it("is set for a renamed file reached under its old path", function()
      edit("before", before_path("src/deep/b.txt"))
      assert.same({ "  R c.txt ← src/deep/b.txt" }, marked())
    end)

    it("is in place when a hidden tree is shown again", function()
      api.nvim_win_close(tree(), false)
      edit("after", after_path("new.txt"))

      assert.is_true(twintree.toggle_tree())
      assert.same({ "A new.txt" }, marked())
      assert.equals("A new.txt", api.nvim_get_current_line())
    end)
  end)

  describe("refreshing the tree", function()
    local function refresh()
      api.nvim_set_current_win(tree())
      h.keys("R")
    end

    it("keeps the panes on a file that is not listed", function()
      edit("after", after_path("same.txt"))
      refresh()
      assert_panes(before_path("same.txt"), after_path("same.txt"))
      assert.same({}, marked())
    end)

    it("marks the shown file when it becomes listed", function()
      edit("after", after_path("same.txt"))
      h.write(repo, "same.txt", "same 1\nCHANGED\nsame 3\n")
      refresh()
      assert_panes(before_path("same.txt"), after_path("same.txt"))
      assert.same({ "M same.txt" }, marked())
    end)
  end)

  describe("resetting the layout", function()
    it("brings back a file that is not in the tree", function()
      edit("before", before_path("same.txt"))
      vim.cmd.split()

      assert.is_true(twintree.reset_layout())
      assert.equals(3, #api.nvim_tabpage_list_wins(tab))
      assert_panes(before_path("same.txt"), after_path("same.txt"))
      assert.same({}, marked())
    end)

    it("brings back a file outside both sides", function()
      edit("after", outside)
      assert.is_true(twintree.reset_layout())
      assert_panes(outside, outside)
    end)

    it("brings back a file whose buffer was deleted", function()
      edit("before", before_path("same.txt"))
      vim.v.errmsg = ""
      api.nvim_buf_delete(state().bufs.before, { force = true })

      assert.is_true(twintree.reset_layout())
      assert_panes(before_path("same.txt"), after_path("same.txt"))
      assert.equals("", vim.v.errmsg)
    end)

    it("works for a session saved before pairs were recorded", function()
      local s = state()
      s.pair = nil
      s.bufs = nil
      session.save(tab, s)
      assert.same(
        { before = before_path("a.txt"), after = after_path("a.txt") },
        state().pair
      )

      assert.is_true(twintree.reset_layout())
      assert_panes(before_path("a.txt"), after_path("a.txt"))
      assert.same({ "M a.txt" }, marked())
    end)
  end)
end)
