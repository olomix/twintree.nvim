local h = require("tests.helpers")
local session = require("twintree.session")
local twintree = require("twintree")
local worktree = require("twintree.worktree")

local api = vim.api

local function name(win)
  return api.nvim_buf_get_name(api.nvim_win_get_buf(win))
end

local function tree_lines(state)
  return h.tree_lines(state.tree_buf)
end

---Press `<CR>` in the tree on the line containing `text`.
local function select(state, text)
  h.goto_line(state.wins.tree, text)
  h.keys("<CR>")
  return session.get(api.nvim_win_get_tabpage(state.wins.tree))
end

local function capture_notify()
  local messages = {}
  local original = vim.notify
  vim.notify = function(msg, level)
    table.insert(messages, { msg = msg, level = level })
  end
  return messages, function()
    vim.notify = original
  end
end

describe("session", function()
  local cache, repo, first

  before_each(function()
    cache = h.reset()
    repo, first = h.repo({
      ["a.txt"] = "one\ntwo\nthree\n",
      ["src/deep/b.txt"] = "b1\nb2\nb3\nb4\n",
      ["gone.txt"] = "gone\n",
    })
    api.nvim_set_current_dir(repo)
  end)

  ---Working tree with one change of every kind.
  local function dirty()
    h.write(repo, "a.txt", "one\nTWO\nthree\n")
    h.write(repo, "new.txt", "new\n")
    h.git(repo, "rm", "-q", "gone.txt")
    h.git(repo, "mv", "src/deep/b.txt", "src/deep/c.txt")
  end

  describe("layout", function()
    it("opens a new tab next to a lone empty tab and leaves that one alone", function()
      local first, win = api.nvim_get_current_tabpage(), api.nvim_get_current_win()
      local buf = api.nvim_get_current_buf()
      local tab = assert(twintree.open())
      assert.same({ first, tab }, api.nvim_list_tabpages())
      assert.equals(tab, api.nvim_get_current_tabpage())
      assert.same({ win }, api.nvim_tabpage_list_wins(first))
      assert.equals(buf, api.nvim_win_get_buf(win))
      assert.is_true(vim.bo[buf].buflisted)
      assert.equals("", vim.bo[buf].bufhidden)

      local state = session.get(tab)
      assert.same(
        { state.wins.tree, state.wins.before, state.wins.after },
        api.nvim_tabpage_list_wins(tab)
      )
      assert.equals(state.wins.tree, api.nvim_get_current_win())
      assert.equals(35, api.nvim_win_get_width(state.wins.tree))
      assert.is_true(vim.wo[state.wins.tree].winfixwidth)
    end)

    it("opens a new tab when something is being edited", function()
      vim.cmd.edit(repo .. "/a.txt")
      local original = api.nvim_get_current_tabpage()

      local tab = assert(twintree.open())
      assert.are_not.equal(original, tab)
      assert.equals(2, #api.nvim_list_tabpages())
      assert.equals(repo .. "/a.txt", name(api.nvim_tabpage_get_win(original)))
      assert.equals(1, #api.nvim_tabpage_list_wins(original))
    end)

    it("honours the configured tree width", function()
      twintree.setup({ cache_dir = cache, tree_width = 20 })
      local state = session.get(assert(twintree.open()))
      assert.equals(20, api.nvim_win_get_width(state.wins.tree))
    end)
  end)

  describe("sides", function()
    it("uses the checkout as the after side by default", function()
      local state = session.get(assert(twintree.open()))
      assert.equals(first, state.before.commit)
      assert.equals(worktree.path(repo, first), state.before.root)
      assert.equals(repo, state.after.root)
      assert.is_nil(state.after.commit)
      assert.same({ state.before.root }, worktree.list(repo))
    end)

    it("uses the merge-base for one revision", function()
      h.write(repo, "a.txt", "second\n")
      h.commit(repo, "second")
      local state = session.get(assert(twintree.open({ "HEAD~1" })))
      assert.equals(first, state.before.commit)
      assert.same({ "a.txt +1 -3 M" }, tree_lines(state))
    end)

    it("uses two worktrees for two revisions", function()
      h.git(repo, "checkout", "-q", "-b", "feature")
      h.write(repo, "a.txt", "feature\n")
      local feature = h.commit(repo, "feature")
      h.git(repo, "checkout", "-q", "main")
      h.write(repo, "main.txt", "main\n")
      h.commit(repo, "main")

      local state = session.get(assert(twintree.open({ "main", "feature" })))
      assert.equals(first, state.before.commit)
      assert.equals(feature, state.after.commit)
      assert.equals(worktree.path(repo, feature), state.after.root)
      assert.same({ "a.txt +1 -3 M" }, tree_lines(state))

      state = select(state, "a.txt")
      assert.equals(state.after.root .. "/a.txt", name(state.wins.after))
      assert.is_false(vim.bo[state.bufs.after].modifiable)
    end)
  end)

  describe("errors", function()
    local function assert_nothing_opened()
      assert.equals(1, #api.nvim_list_tabpages())
      assert.equals(1, #api.nvim_tabpage_list_wins(0))
      assert.is_nil(session.get())
      assert.is_nil(vim.uv.fs_stat(cache .. "/" .. (worktree.repo_id(repo) or "x")))
    end

    it("rejects a directory that is not a repository", function()
      local dir = h.tmpdir()
      api.nvim_set_current_dir(dir)
      local tab, err = twintree.open()
      assert.is_nil(tab)
      assert.equals("not a git repository: " .. dir, err)
      assert.equals(1, #api.nvim_tabpage_list_wins(0))
    end)

    it("rejects an unknown revision", function()
      local tab, err = twintree.open({ "no-such-rev" })
      assert.is_nil(tab)
      assert.equals("cannot resolve revision: no-such-rev", err)
      assert_nothing_opened()
    end)

    it("rejects revisions without a common ancestor", function()
      h.git(repo, "checkout", "-q", "--orphan", "other")
      h.git(repo, "rm", "-rfq", ".")
      h.write(repo, "o.txt", "o\n")
      h.commit(repo, "orphan")

      local tab, err = twintree.open({ "main", "other" })
      assert.is_nil(tab)
      assert.equals("no common ancestor of main and other", err)
      assert_nothing_opened()
    end)

    it("removes the worktrees it created when opening fails later", function()
      h.write(repo, "a.txt", "second\n")
      local second = h.commit(repo, "second")
      local git = require("twintree.git")
      local original = git.changed_files
      git.changed_files = function()
        return nil, "boom"
      end

      local tab, err = twintree.open({ "HEAD~1", "HEAD" })
      assert.is_nil(tab)
      assert.equals("boom", err)
      assert_nothing_opened()
      assert.same({}, worktree.list(repo))

      -- A worktree that was already cached is not this call's to remove.
      local cached = assert(worktree.ensure(repo, first))
      tab, err = twintree.open({ "HEAD~1", "HEAD" })
      git.changed_files = original
      assert.is_nil(tab)
      assert.same({ cached }, worktree.list(repo))
      assert.is_false(worktree.is_ready(repo, second))
    end)

    it("treats a tab closed while the first file is shown as a failed open", function()
      h.write(repo, "a.txt", "one\nTWO\nthree\n")
      vim.cmd.edit(repo .. "/a.txt")
      local origin = api.nvim_get_current_win()
      local function close_on_load()
        -- The after side is loaded already; this is the before side.
        return api.nvim_create_autocmd("BufReadPost", {
          pattern = "*/a.txt",
          once = true,
          callback = function()
            vim.cmd("tabclose!")
          end,
        })
      end

      local id = close_on_load()
      local ok, tab, err = pcall(twintree.open)
      pcall(api.nvim_del_autocmd, id)
      assert.is_true(ok, tostring(tab))
      assert.is_nil(tab)
      assert.equals(session.TAB_GONE, err)
      assert.equals(1, #api.nvim_list_tabpages())
      assert.equals(origin, api.nvim_get_current_win())
      assert.is_nil(session.get())
      assert.same({}, worktree.list(repo))

      -- A worktree that was already cached is not this call's to remove.
      local cached = assert(worktree.ensure(repo, first))
      vim.cmd("silent! bwipeout! " .. vim.fn.fnameescape(cached .. "/a.txt"))
      id = close_on_load()
      ok, tab, err = pcall(twintree.open)
      pcall(api.nvim_del_autocmd, id)
      assert.is_true(ok, tostring(tab))
      assert.is_nil(tab)
      assert.equals(session.TAB_GONE, err)
      assert.same({ cached }, worktree.list(repo))
    end)

    it("reports git's error when a worktree cannot be created", function()
      h.write(repo, ".git/hooks/post-checkout", "#!/bin/sh\necho hook-says-no >&2\nexit 1\n")
      vim.uv.fs_chmod(repo .. "/.git/hooks/post-checkout", 493)

      local tab, err = twintree.open()
      assert.is_nil(tab)
      assert.truthy(err:find("hook-says-no", 1, true))
      assert_nothing_opened()
    end)

    it("rejects more than two revisions", function()
      local tab, err = twintree.open({ "a", "b", "c" })
      assert.is_nil(tab)
      assert.equals("expected at most two revisions", err)
      assert_nothing_opened()
    end)
  end)

  describe("tree buffer", function()
    it("lists the changes and cannot be edited", function()
      dirty()
      local state = session.get(assert(twintree.open()))
      assert.same({
        "▾ src/deep/",
        "│ c.txt ← b.txt +0 -0 R",
        "a.txt +1 -1 M",
        "gone.txt +0 -1 D",
        "new.txt +1 -0 A",
      }, tree_lines(state))

      local buf = state.tree_buf
      assert.equals("nofile", vim.bo[buf].buftype)
      assert.equals("twintree", vim.bo[buf].filetype)
      assert.is_false(vim.bo[buf].modifiable)
      assert.is_false(pcall(api.nvim_buf_set_lines, buf, 0, -1, false, { "x" }))
    end)

    it("marks directories missing on the other side", function()
      h.write(repo, "a.txt", "changed\n")
      h.write(repo, "added/more/x.txt", "x\n")
      h.git(repo, "rm", "-rq", "src")
      local state = session.get(assert(twintree.open()))
      assert.same({
        "▾ added/more/ A",
        "│ x.txt +1 -0 A",
        "▾ src/deep/ D",
        "│ b.txt +0 -4 D",
        "a.txt +1 -3 M",
      }, tree_lines(state))

      state = select(state, "src/deep/")
      assert.equals("▸ src/deep/ D", tree_lines(state)[3])
    end)

    it("shows a message when nothing changed", function()
      local state = session.get(assert(twintree.open()))
      assert.same({ "No changes" }, tree_lines(state))
      h.keys("<CR>")
      assert.equals(state.wins.tree, api.nvim_get_current_win())
      assert.equals("twintree://empty", name(state.wins.before))
      assert.equals("twintree://empty", name(state.wins.after))
    end)

    it("folds and unfolds a directory", function()
      dirty()
      local state = session.get(assert(twintree.open()))

      state = select(state, "src/deep/")
      assert.same(
        { "▸ src/deep/", "a.txt +1 -1 M", "gone.txt +0 -1 D", "new.txt +1 -0 A" },
        tree_lines(state)
      )
      assert.equals(state.wins.tree, api.nvim_get_current_win())

      state = select(state, "src/deep/")
      assert.equals(5, #tree_lines(state))
    end)

    it("refreshes, keeping folds and the selection", function()
      dirty()
      local state = session.get(assert(twintree.open()))
      state = select(state, "src/deep/")
      state = select(state, "a.txt")

      h.write(repo, "later.txt", "later\n")
      api.nvim_set_current_win(state.wins.tree)
      h.keys("R")

      state = session.get()
      assert.same(
        {
          "▸ src/deep/",
          "a.txt +1 -1 M",
          "gone.txt +0 -1 D",
          "later.txt +1 -0 A",
          "new.txt +1 -0 A",
        },
        tree_lines(state)
      )
      assert.equals("a.txt", state.selected)
      assert.is_true(vim.wo[state.wins.before].diff)
    end)

    it("drops the mark but keeps the panes when the file is no longer changed", function()
      dirty()
      local state = session.get(assert(twintree.open()))
      state = select(state, "new.txt")

      vim.fn.delete(repo .. "/new.txt")
      api.nvim_set_current_win(state.wins.tree)
      h.keys("R")

      state = session.get()
      assert.is_nil(state.selected)
      assert.equals(repo .. "/new.txt", name(state.wins.after))
      assert.is_true(vim.wo[state.wins.after].diff)
    end)
  end)

  describe("opening", function()
    local function marked_rows(state)
      local ns = api.nvim_get_namespaces().twintree
      local rows = {}
      for _, mark in ipairs(api.nvim_buf_get_extmarks(state.tree_buf, ns, 0, -1, { details = true })) do
        if mark[4].line_hl_group == "TwintreeSelected" then
          table.insert(rows, mark[2] + 1)
        end
      end
      return rows
    end

    it("shows the first file of the tree with the cursor in the after pane", function()
      dirty()
      local tab, err = twintree.open()
      assert.is_nil(err)
      local state = session.get(tab)

      -- The renamed file in the directory is listed above a.txt.
      assert.equals(state.before.root .. "/src/deep/b.txt", name(state.wins.before))
      assert.equals(repo .. "/src/deep/c.txt", name(state.wins.after))
      assert.is_true(vim.wo[state.wins.before].diff)
      assert.is_true(vim.wo[state.wins.after].diff)
      assert.equals("src/deep/c.txt", state.selected)
      assert.same({ 2 }, marked_rows(state))
      assert.equals(state.wins.after, api.nvim_get_current_win())
      assert.same({ 2, 0 }, api.nvim_win_get_cursor(state.wins.tree))
    end)

    it("leaves empty panes and the cursor in the tree when nothing changed", function()
      local tab, err = twintree.open()
      assert.is_nil(err)
      local state = session.get(tab)
      assert.equals("twintree://empty", name(state.wins.before))
      assert.equals("twintree://empty", name(state.wins.after))
      assert.is_false(vim.wo[state.wins.after].diff)
      assert.is_nil(state.selected)
      assert.same({}, marked_rows(state))
      assert.equals(state.wins.tree, api.nvim_get_current_win())
    end)

    it("shows a deleted first file next to the placeholder", function()
      h.git(repo, "rm", "-q", "gone.txt")
      local state = session.get(assert(twintree.open()))
      assert.equals(state.before.root .. "/gone.txt", name(state.wins.before))
      assert.equals("twintree://empty", name(state.wins.after))
      assert.is_true(vim.wo[state.wins.before].diff)
      assert.equals("gone.txt", state.selected)
      assert.equals(state.wins.after, api.nvim_get_current_win())
    end)
  end)

  describe("selecting a file", function()
    local state

    before_each(function()
      dirty()
      state = session.get(assert(twintree.open()))
    end)

    local function assert_diffed()
      assert.is_true(vim.wo[state.wins.before].diff)
      assert.is_true(vim.wo[state.wins.after].diff)
      assert.equals(state.wins.after, api.nvim_get_current_win())
    end

    it("shows a modified file from both roots in diff mode", function()
      state = select(state, "a.txt")
      assert.equals(state.before.root .. "/a.txt", name(state.wins.before))
      assert.equals(repo .. "/a.txt", name(state.wins.after))
      assert_diffed()
      assert.same({ "one", "two", "three" }, h.buf_lines(state.bufs.before))
      assert.same({ "one", "TWO", "three" }, h.buf_lines(state.bufs.after))
      assert.equals("a.txt", state.selected)
    end)

    it("shows the whole file without folding unchanged lines", function()
      local long = {}
      for i = 1, 60 do
        long[i] = "line " .. i
      end
      h.write(repo, "long.txt", table.concat(long, "\n") .. "\n")
      h.commit(repo, "long")
      long[30] = "changed"
      h.write(repo, "long.txt", table.concat(long, "\n") .. "\n")

      state = session.get(assert(twintree.open()))
      state = select(state, "long.txt")
      for _, pane in ipairs({ "before", "after" }) do
        local win = state.wins[pane]
        assert.is_true(vim.wo[win].diff)
        assert.is_false(vim.wo[win].foldenable)
        assert.equals(-1, api.nvim_win_call(win, function()
          return vim.fn.foldclosed(1)
        end))
      end

      -- Folding stays off after leaving the file and coming back.
      api.nvim_set_current_win(state.wins.before)
      vim.cmd.edit(state.before.root .. "/a.txt")
      vim.cmd.buffer(state.bufs.before)
      assert.is_true(vim.wo[state.wins.before].diff)
      assert.is_false(vim.wo[state.wins.before].foldenable)
    end)

    it("shows an added file against an empty placeholder", function()
      state = select(state, "new.txt")
      assert.equals("twintree://empty", name(state.wins.before))
      assert.equals(repo .. "/new.txt", name(state.wins.after))
      assert_diffed()
    end)

    it("shows a deleted file against an empty placeholder", function()
      state = select(state, "gone.txt")
      assert.equals(state.before.root .. "/gone.txt", name(state.wins.before))
      assert.equals("twintree://empty", name(state.wins.after))
      assert_diffed()
    end)

    it("shows a renamed file under its old and new path", function()
      state = select(state, "c.txt")
      assert.equals(state.before.root .. "/src/deep/b.txt", name(state.wins.before))
      assert.equals(repo .. "/src/deep/c.txt", name(state.wins.after))
      assert_diffed()
    end)

    it("does not open a directory that replaced a file", function()
      vim.fn.delete(repo .. "/a.txt")
      h.write(repo, "a.txt/inner.txt", "inner\n")
      state = session.get(assert(twintree.open()))
      assert.truthy(vim.tbl_contains(tree_lines(state), "▾ a.txt/ A"))

      -- With a space: the directory of the same name is listed as `a.txt/`.
      state = select(state, "a.txt ")
      assert.equals(state.before.root .. "/a.txt", name(state.wins.before))
      assert.equals("twintree://empty", name(state.wins.after))
      assert_diffed()
    end)

    it("lists and opens a file whose name contains a newline", function()
      h.write(repo, "odd\nname.txt", "odd\n")
      state = session.get(assert(twintree.open()))
      assert.truthy(vim.tbl_contains(tree_lines(state), "odd\\nname.txt +1 -0 A"))
      assert.is_false(vim.bo[state.tree_buf].modifiable)

      state = select(state, "odd\\nname.txt")
      assert.equals("odd\nname.txt", state.selected)
      assert.same({ "odd" }, h.buf_lines(state.bufs.after))
    end)

    it("marks the selected line in the tree", function()
      state = select(state, "a.txt")
      local ns = api.nvim_get_namespaces().twintree
      local marked = {}
      for _, mark in ipairs(api.nvim_buf_get_extmarks(state.tree_buf, ns, 0, -1, { details = true })) do
        if mark[4].line_hl_group == "TwintreeSelected" then
          table.insert(marked, mark[2] + 1)
        end
      end
      assert.same({ 3 }, marked)
    end)

    it("switches between files", function()
      state = select(state, "a.txt")
      state = select(state, "new.txt")
      assert.equals("twintree://empty", name(state.wins.before))
      assert_diffed()
      state = select(state, "a.txt")
      assert.equals(state.before.root .. "/a.txt", name(state.wins.before))
      assert_diffed()
    end)

    it("keeps the before side read-only and the after side editable", function()
      state = select(state, "a.txt")
      assert.is_true(vim.bo[state.bufs.before].readonly)
      assert.is_false(vim.bo[state.bufs.before].modifiable)

      local function is_changed(lnum)
        return api.nvim_win_call(state.wins.after, function()
          vim.cmd.diffupdate()
          return vim.fn.diff_hlID(lnum, 1) ~= 0
        end)
      end
      assert.is_false(is_changed(1))
      assert.is_true(is_changed(2))

      api.nvim_buf_set_lines(state.bufs.after, 0, 1, false, { "ONE" })
      vim.cmd("silent write")
      assert.same({ "ONE", "TWO", "three" }, vim.fn.readfile(repo .. "/a.txt"))
      assert.is_true(is_changed(1))
    end)

    it("stays in diff mode when a pane is taken to another file", function()
      state = select(state, "a.txt")
      local before = state.wins.before
      local first_buf = state.bufs.before

      api.nvim_set_current_win(before)
      vim.cmd.edit(state.before.root .. "/gone.txt")
      assert.is_true(vim.wo[before].diff)
      assert.is_false(vim.bo.modifiable)
      assert.equals("twintree://empty", name(state.wins.after))
      assert.is_true(vim.wo[state.wins.after].diff)

      vim.cmd.buffer(first_buf)
      assert.is_true(vim.wo[before].diff)
      assert.is_true(vim.wo[before].scrollbind)
      assert.equals(repo .. "/a.txt", name(state.wins.after))
    end)

    it("reports a layout that was taken apart", function()
      api.nvim_win_close(state.wins.before, true)
      local messages, restore = capture_notify()
      select(state, "a.txt")
      restore()
      assert.equals(1, #messages)
      assert.equals(
        "twintree: a pane of this diff is missing; run :TwintreeResetLayout",
        messages[1].msg
      )
      assert.equals(vim.log.levels.ERROR, messages[1].level)
    end)
  end)

  describe("cursor", function()
    local dir, state

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

    local function view(win)
      return api.nvim_win_call(win, vim.fn.winsaveview)
    end

    local function line(win)
      return api.nvim_win_get_cursor(win)[1]
    end

    local function current_line(win)
      return api.nvim_win_call(win, api.nvim_get_current_line)
    end

    ---Move the cursor of the after pane as the user would.
    local function move(lnum)
      api.nvim_set_current_win(state.wins.after)
      h.keys(lnum .. "G")
    end

    before_each(function()
      h.reset()
      local files = { "far", "removed", "top", "above", "below", "same", "gone" }
      local initial = { ["0.txt"] = "zero\n", ["other.txt"] = "other\n" }
      for _, file in ipairs(files) do
        initial[file .. ".txt"] = text(100)
      end
      dir = h.repo(initial)
      h.write(dir, "0.txt", "ZERO\n")
      h.write(dir, "other.txt", "OTHER\n")
      h.write(dir, "far.txt", text(100, function(lines)
        lines[60] = "changed"
        lines[90] = "changed again"
      end))
      h.write(dir, "removed.txt", text(100, function(lines)
        lines[80] = "changed"
        for _ = 1, 3 do
          table.remove(lines, 40)
        end
      end))
      h.write(dir, "top.txt", text(100, function(lines)
        lines[1] = "changed"
        lines[50] = "changed again"
      end))
      h.write(dir, "above.txt", text(100, function(lines)
        lines[50] = "changed"
        table.insert(lines, 1, "added")
      end))
      h.write(dir, "below.txt", text(100, function(lines)
        lines[50] = "changed"
        table.remove(lines, 1)
      end))
      h.write(dir, "new.txt", text(100))
      vim.fn.delete(dir .. "/gone.txt")
      vim.fn.setfperm(dir .. "/same.txt", "rwxr-xr-x")
      api.nvim_set_current_dir(dir)
      state = session.get(assert(twintree.open()))
    end)

    it("is on the first change of the file a session opens with", function()
      h.reset()
      h.write(dir, "0.txt", "ZERO\n")
      h.commit(dir, "all")
      h.write(dir, "far.txt", text(100, function(lines)
        lines[70] = "later"
      end))
      state = session.get(assert(twintree.open()))
      assert.equals(dir .. "/far.txt", name(state.wins.after))
      assert.equals(state.wins.after, api.nvim_get_current_win())
      assert.equals(60, line(state.wins.after))
      assert.equals(60, line(state.wins.before))
    end)

    it("is on the first change of a selected file, in both panes", function()
      state = select(state, "far.txt")
      assert.equals(state.wins.after, api.nvim_get_current_win())
      assert.equals(60, line(state.wins.after))
      assert.equals("changed", current_line(state.wins.after))
      assert.equals(60, line(state.wins.before))
      assert.equals("line 60", current_line(state.wins.before))

      local after, before = view(state.wins.after), view(state.wins.before)
      assert.is_true(after.topline > 1)
      assert.equals(after.topline, before.topline)
      local height = api.nvim_win_get_height(state.wins.after)
      assert.is_true(after.topline + height > 60)
    end)

    it("is next to the gap when the first change removes lines", function()
      state = select(state, "removed.txt")
      assert.equals(40, line(state.wins.after))
      assert.equals("line 43", current_line(state.wins.after))
      -- The before pane is on the same text, right below the removed lines.
      assert.equals("line 43", current_line(state.wins.before))
      local before = view(state.wins.before)
      assert.is_true(before.topline <= 40)
      assert.is_true(before.topline + api.nvim_win_get_height(state.wins.before) > 43)
    end)

    it("stays on a first line that is changed", function()
      state = select(state, "top.txt")
      assert.equals(1, line(state.wins.after))
    end)

    it("stays on the first line when lines were added above it", function()
      state = select(state, "above.txt")
      assert.equals(1, line(state.wins.after))
      assert.equals("added", current_line(state.wins.after))
    end)

    it("stays on the first line when lines were removed above it", function()
      state = select(state, "below.txt")
      assert.equals(1, line(state.wins.after))
      assert.equals("line 2", current_line(state.wins.after))
    end)

    it("finds a change at the top when filler lines are not shown", function()
      local diffopt = vim.o.diffopt
      vim.cmd("set diffopt-=filler")
      assert.is_nil(vim.o.diffopt:find("filler", 1, true))
      local ok, err = pcall(function()
        state = select(state, "below.txt")
        assert.equals(1, line(state.wins.after))
        state = select(state, "above.txt")
        assert.equals(1, line(state.wins.after))
        state = select(state, "top.txt")
        assert.equals(1, line(state.wins.after))
        state = select(state, "far.txt")
        assert.equals(60, line(state.wins.after))
      end)
      vim.o.diffopt = diffopt
      assert(ok, err)
    end)

    it("stays at the top of a file with the same content on both sides", function()
      local messages, restore = capture_notify()
      state = select(state, "same.txt")
      restore()
      assert.same({}, messages)
      assert.equals("same.txt", state.selected)
      assert.equals(1, line(state.wins.after))
      assert.equals(1, line(state.wins.before))
    end)

    it("stays at the top of an added and of a deleted file", function()
      state = select(state, "new.txt")
      assert.equals(1, line(state.wins.after))
      state = select(state, "gone.txt")
      assert.equals(state.wins.after, api.nvim_get_current_win())
      -- Any command: Neovim scrolls bound windows when a command ends.
      h.keys("0")
      assert.equals(1, line(state.wins.before))
      assert.equals(1, view(state.wins.before).topline)
      assert.is_true(vim.wo[state.wins.before].diff)

      -- A pair with both sides scrolls together again.
      state = select(state, "far.txt")
      assert.is_true(vim.wo[state.wins.before].scrollbind)
      assert.is_true(vim.wo[state.wins.after].scrollbind)
    end)

    it("adds no entry to the jump list", function()
      state = select(state, "far.txt")
      local jumps = api.nvim_win_call(state.wins.after, function()
        return vim.fn.getjumplist()[1]
      end)
      local far = state.bufs.after
      for _, jump in ipairs(jumps) do
        assert.is_false(jump.bufnr == far and jump.lnum == 1, vim.inspect(jump))
      end
      h.keys("<C-o>")
      local win = state.wins.after
      assert.is_false(api.nvim_win_get_buf(win) == far and line(win) == 1)
    end)

    it("ignores mappings of ]c and [c", function()
      vim.keymap.set("n", "]c", "G")
      vim.keymap.set("n", "[c", "G")
      local ok, err = pcall(function()
        state = select(state, "far.txt")
        assert.equals(60, line(state.wins.after))
        state = select(state, "top.txt")
        assert.equals(1, line(state.wins.after))
      end)
      vim.keymap.del("n", "]c")
      vim.keymap.del("n", "[c")
      assert(ok, err)
    end)

    it("leaves the cursor of a window in another tab alone", function()
      h.reset()
      vim.cmd.edit(dir .. "/far.txt")
      local elsewhere = api.nvim_get_current_win()
      api.nvim_win_set_cursor(elsewhere, { 5, 0 })
      state = session.get(assert(twintree.open()))
      assert.equals(2, #api.nvim_list_tabpages())

      state = select(state, "far.txt")
      assert.equals(60, line(state.wins.after))
      assert.equals(5, line(elsewhere))
    end)

    describe("of a file shown again", function()
      it("is where it was left", function()
        state = select(state, "far.txt")
        move(75)
        state = select(state, "other.txt")
        state = select(state, "far.txt")
        assert.equals(75, line(state.wins.after))
        assert.equals(75, line(state.wins.before))
        assert.equals(state.wins.after, api.nvim_get_current_win())
      end)

      it("does not move when the file is already shown", function()
        state = select(state, "far.txt")
        move(75)
        state = select(state, "far.txt")
        assert.equals(75, line(state.wins.after))
        assert.equals(state.wins.after, api.nvim_get_current_win())
      end)

      it("is on the first change again after the buffer was wiped out", function()
        state = select(state, "far.txt")
        move(75)
        local far = state.bufs.after
        state = select(state, "other.txt")
        vim.cmd.bwipeout(far)
        state = select(state, "far.txt")
        assert.are_not.equal(far, state.bufs.after)
        assert.equals(60, line(state.wins.after))
      end)

      it("is on the first change in another diff tab", function()
        state = select(state, "far.txt")
        move(75)
        local second = session.get(assert(twintree.open()))
        second = select(second, "far.txt")
        assert.equals(60, line(second.wins.after))
        assert.equals(75, line(state.wins.after))
      end)
    end)

    describe("record of shown files", function()
      local function count()
        return vim.tbl_count(session.get().viewed)
      end

      it("holds the buffers of both panes", function()
        state = select(state, "far.txt")
        assert.is_true(state.viewed[tostring(state.bufs.before)])
        assert.is_true(state.viewed[tostring(state.bufs.after)])
      end)

      it("holds no placeholder", function()
        local known = count()
        state = select(state, "gone.txt")
        assert.is_true(state.viewed[tostring(state.bufs.before)])
        assert.is_nil(state.viewed[tostring(state.bufs.after)])
        assert.equals(known + 1, count())
      end)

      it("is not changed by a file that was not shown", function()
        local known = count()
        api.nvim_win_close(state.wins.before, true)
        local messages, restore = capture_notify()
        select(state, "far.txt")
        restore()
        assert.equals(1, #messages)
        assert.equals(known, count())
      end)

      it("is filled in for a session that has none", function()
        state.viewed = nil
        session.save(api.nvim_get_current_tabpage(), state)
        assert.same({}, session.get().viewed)
        state = select(state, "far.txt")
        assert.equals(60, line(state.wins.after))
        assert.is_true(state.viewed[tostring(state.bufs.after)])
      end)
    end)
  end)

  it("keeps two sessions independent", function()
    dirty()
    local one = session.get(assert(twintree.open()))
    local two = session.get(assert(twintree.open()))
    assert.equals(3, #api.nvim_list_tabpages())

    two = select(two, "new.txt")
    one = session.get(api.nvim_win_get_tabpage(one.wins.tree))
    assert.equals("src/deep/c.txt", one.selected)

    api.nvim_set_current_tabpage(api.nvim_win_get_tabpage(one.wins.tree))
    one = select(one, "a.txt")
    two = session.get(api.nvim_win_get_tabpage(two.wins.tree))
    assert.equals("a.txt", one.selected)
    assert.equals("new.txt", two.selected)
    assert.equals(repo .. "/new.txt", name(two.wins.after))
  end)

  it("ends with its tab and keeps the worktree", function()
    vim.cmd.edit(repo .. "/a.txt")
    local state = session.get(assert(twintree.open()))
    vim.cmd.tabclose()

    assert.equals(1, #api.nvim_list_tabpages())
    assert.is_nil(session.get())
    assert.same({}, session.roots_in_use())
    assert.truthy(vim.uv.fs_stat(state.before.root))
  end)

  it("survives a reload of the plugin", function()
    dirty()
    local state = session.get(assert(twintree.open()))
    local autocmds = #api.nvim_get_autocmds({ group = "twintree" })

    local originals = {}
    for module, value in pairs(package.loaded) do
      if module:match("^twintree") then
        originals[module] = value
      end
    end
    for module in pairs(originals) do
      package.loaded[module] = nil
    end

    local ok, err = pcall(function()
      vim.cmd.runtime("plugin/twintree.lua")
      require("twintree").setup({ cache_dir = cache })

      assert.equals(autocmds, #api.nvim_get_autocmds({ group = "twintree" }))
      assert.are_not.equal(session, require("twintree.session"))
      h.goto_line(state.wins.tree, "a.txt")
      h.keys("<CR>")

      state = require("twintree.session").get()
      assert.equals(state.before.root .. "/a.txt", name(state.wins.before))
      assert.equals(repo .. "/a.txt", name(state.wins.after))
      assert.is_true(vim.wo[state.wins.before].diff)
      assert.truthy(vim.tbl_contains(tree_lines(state), "a.txt +1 -1 M"))

      -- The keys set before the reload run the reloaded code.
      local function mappings(lhs)
        return vim.tbl_filter(function(mapping)
          return vim.keycode(mapping.lhs) == vim.keycode(lhs)
        end, api.nvim_get_keymap("n"))
      end
      assert.equals(1, #mappings("]<C-f>"))
      assert.equals("Twintree: next changed file", mappings("]<C-f>")[1].desc)
      h.keys("]<C-f>")
      assert.equals("gone.txt", require("twintree.session").get().selected)
      vim.cmd.tabnew()
      assert.equals(0, #mappings("]<C-f>"))
      assert.equals(0, #mappings("[<C-f>"))
      vim.cmd.tabclose()
    end)

    -- Later tests hold references to the original modules.
    for module, value in pairs(originals) do
      package.loaded[module] = value
    end
    assert(ok, err)
  end)

  describe("commands", function()
    it("are registered", function()
      local commands = api.nvim_get_commands({})
      assert.truthy(commands.Twintree)
      assert.truthy(commands.TwintreeClean)
    end)

    it(":Twintree opens a session", function()
      vim.cmd("Twintree HEAD")
      assert.equals(first, session.get().before.commit)
    end)

    it(":Twintree reports too many arguments", function()
      local messages, restore = capture_notify()
      vim.cmd("Twintree a b c")
      restore()

      assert.same({
        {
          msg = "twintree: expected at most two revisions",
          level = vim.log.levels.ERROR,
        },
      }, messages)
      assert.is_nil(session.get())
    end)

    it(":Twintree completes revisions", function()
      h.git(repo, "branch", "feature")
      assert.same({ "feature" }, vim.fn.getcompletion("Twintree fea", "cmdline"))
    end)

    it(":TwintreeClean keeps worktrees of open sessions", function()
      h.write(repo, "a.txt", "second\n")
      local second = h.commit(repo, "second")
      local stale = assert(worktree.ensure(repo, first))
      local state = session.get(assert(twintree.open()))
      assert.equals(second, state.before.commit)

      local messages, restore = capture_notify()
      vim.cmd("TwintreeClean")
      restore()

      assert.equals("twintree: removed 1 cached worktree(s)", messages[1].msg)
      assert.is_nil(vim.uv.fs_stat(stale))
      assert.same({ state.before.root }, worktree.list(repo))
    end)
  end)

  describe("the tab of a diff", function()
    local function tree_bufs()
      return vim.tbl_filter(function(buf)
        return vim.startswith(api.nvim_buf_get_name(buf), "twintree://tree/")
      end, api.nvim_list_bufs())
    end

    it("closes with `:tabclose` when the diff was opened in an empty Neovim", function()
      dirty()
      local origin, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
      assert(twintree.open())

      vim.cmd.tabclose()

      assert.equals(1, #api.nvim_list_tabpages())
      assert.equals(origin, api.nvim_get_current_win())
      assert.equals(buf, api.nvim_win_get_buf(origin))
      assert.is_nil(session.get())
      assert.same({}, tree_bufs())
    end)

    it("counts as a failed open when an autocommand closes it, also from an empty Neovim", function()
      h.write(repo, "a.txt", "one\nTWO\nthree\n")
      local origin = api.nvim_get_current_win()
      local id = api.nvim_create_autocmd("BufReadPost", {
        pattern = "*/a.txt",
        once = true,
        callback = function()
          vim.cmd("tabclose!")
        end,
      })
      local ok, tab, err = pcall(twintree.open)
      pcall(api.nvim_del_autocmd, id)

      assert.is_true(ok, tostring(tab))
      assert.is_nil(tab)
      assert.equals(session.TAB_GONE, err)
      assert.equals(1, #api.nvim_list_tabpages())
      assert.equals(origin, api.nvim_get_current_win())
      assert.is_nil(session.get())
      assert.same({}, tree_bufs())
      -- What TabClosed and TabEnter do for a tab that closes in the open.
      assert.equals("", vim.fn.maparg("]<C-f>", "n"))
      for _, loaded in ipairs(api.nvim_list_bufs()) do
        assert.is_nil(worktree.root_of(api.nvim_buf_get_name(loaded)))
      end

      -- The buffers of a worktree that was cached before go as well.
      local cached = assert(worktree.ensure(repo, first))
      id = api.nvim_create_autocmd("BufReadPost", {
        pattern = "*/a.txt",
        once = true,
        callback = function()
          vim.cmd("tabclose!")
        end,
      })
      assert.is_nil(twintree.open())
      pcall(api.nvim_del_autocmd, id)
      assert.same({ cached }, worktree.list(repo))
      for _, loaded in ipairs(api.nvim_list_bufs()) do
        assert.is_nil(worktree.root_of(api.nvim_buf_get_name(loaded)))
      end
    end)

    it("is gone again when the windows of the diff cannot be made", function()
      dirty()
      local origin, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
      local open_panes = session.open_panes
      session.open_panes = function()
        error("E36: Not enough room")
      end
      local ok, tab, err = pcall(twintree.open)
      session.open_panes = open_panes

      assert.is_true(ok, tostring(tab))
      assert.is_nil(tab)
      assert.truthy(err:find("could not create the windows of the diff", 1, true), err)
      assert.truthy(err:find("E36: Not enough room", 1, true), err)
      assert.equals(1, #api.nvim_list_tabpages())
      assert.equals(origin, api.nvim_get_current_win())
      assert.equals(buf, api.nvim_win_get_buf(origin))
      assert.is_nil(session.get())
      assert.same({}, tree_bufs())
      assert.same({}, worktree.list(repo))
    end)

    it("leaves the tab of the command alone when an autocommand closes the new tab", function()
      dirty()
      vim.cmd.edit(repo .. "/a.txt")
      local origin, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
      local id = api.nvim_create_autocmd("TabEnter", {
        once = true,
        callback = function()
          vim.cmd("tabclose")
        end,
      })
      local ok, tab, err = pcall(twintree.open)
      pcall(api.nvim_del_autocmd, id)

      assert.is_true(ok, tostring(tab))
      assert.is_nil(tab)
      assert.truthy(err:find("could not open a tab for the diff", 1, true), err)
      assert.equals(1, #api.nvim_list_tabpages())
      assert.same({ origin }, api.nvim_tabpage_list_wins(0))
      assert.equals(buf, api.nvim_win_get_buf(origin))
      assert.equals("", vim.bo[buf].bufhidden)
      assert.is_nil(session.get())
      assert.same({}, tree_bufs())
      assert.same({}, worktree.list(repo))
    end)

    it("leaves the next tab alone when an autocommand closes the new tab", function()
      dirty()
      vim.cmd.edit(repo .. "/a.txt")
      local origin = api.nvim_get_current_tabpage()
      vim.cmd.tabedit(repo .. "/new.txt")
      local next_tab, next_win = api.nvim_get_current_tabpage(), api.nvim_get_current_win()
      local next_buf = api.nvim_get_current_buf()
      api.nvim_set_current_tabpage(origin)
      -- Neovim makes the tab after the closed one current, not the origin.
      local id = api.nvim_create_autocmd("TabEnter", {
        once = true,
        callback = function()
          vim.cmd("tabclose")
        end,
      })
      local ok, tab, err = pcall(twintree.open)
      pcall(api.nvim_del_autocmd, id)

      assert.is_true(ok, tostring(tab))
      assert.is_nil(tab)
      assert.truthy(err:find("could not open a tab for the diff", 1, true), err)
      assert.same({ origin, next_tab }, api.nvim_list_tabpages())
      assert.equals(origin, api.nvim_get_current_tabpage())
      assert.same({ next_win }, api.nvim_tabpage_list_wins(next_tab))
      assert.equals(next_buf, api.nvim_win_get_buf(next_win))
      assert.equals("", vim.bo[next_buf].bufhidden)
      assert.is_nil(session.get(next_tab))
      assert.is_nil(session.get(origin))
      assert.same({}, tree_bufs())
      assert.same({}, worktree.list(repo))
    end)

    it("leaves the next tab alone when the new tab is closed and the layout fails", function()
      dirty()
      vim.cmd.edit(repo .. "/a.txt")
      local origin = api.nvim_get_current_tabpage()
      vim.cmd.tabedit(repo .. "/new.txt")
      local next_tab = api.nvim_get_current_tabpage()
      api.nvim_set_current_tabpage(origin)
      local id = api.nvim_create_autocmd("TabEnter", {
        once = true,
        callback = function()
          vim.cmd("tabclose")
        end,
      })
      local open_panes = session.open_panes
      session.open_panes = function()
        error("E36: Not enough room")
      end
      local ok, tab = pcall(twintree.open)
      session.open_panes = open_panes
      pcall(api.nvim_del_autocmd, id)

      assert.is_true(ok, tostring(tab))
      assert.is_nil(tab)
      assert.same({ origin, next_tab }, api.nvim_list_tabpages())
      assert.equals(origin, api.nvim_get_current_tabpage())
    end)

    it("reports an autocommand that fails while the tab is opened", function()
      dirty()
      local origin = api.nvim_get_current_win()
      local id = api.nvim_create_autocmd("TabNew", {
        once = true,
        callback = function()
          error("a broken autocommand")
        end,
      })
      local ok, tab, err = pcall(twintree.open)
      pcall(api.nvim_del_autocmd, id)

      assert.is_true(ok, tostring(tab))
      assert.is_nil(tab)
      assert.truthy(err:find("a broken autocommand", 1, true), err)
      assert.equals(1, #api.nvim_list_tabpages())
      assert.equals(origin, api.nvim_get_current_win())
      assert.is_nil(session.get())
      assert.same({}, tree_bufs())
      assert.same({}, worktree.list(repo))
    end)

    it("counts as a failed open when an autocommand closes it after the file was shown", function()
      h.write(repo, "a.txt", "one\nTWO\nthree\n")
      local origin = api.nvim_get_current_win()
      -- The focus goes to the after pane when both files are loaded.
      local id = api.nvim_create_autocmd("WinEnter", {
        callback = function()
          local state = session.get()
          if state and api.nvim_get_current_win() == state.wins.after and state.pair then
            vim.cmd("tabclose!")
          end
        end,
      })
      local ok, tab, err = pcall(twintree.open)
      pcall(api.nvim_del_autocmd, id)

      assert.is_true(ok, tostring(tab))
      assert.is_nil(tab)
      assert.equals(session.TAB_GONE, err)
      assert.equals(1, #api.nvim_list_tabpages())
      assert.equals(origin, api.nvim_get_current_win())
      assert.same({}, tree_bufs())
      assert.same({}, worktree.list(repo))
      assert.equals("", vim.fn.maparg("]<C-f>", "n"))
    end)

    it("returns to the tab of the command when that one has tabs after it", function()
      dirty()
      vim.cmd.edit(repo .. "/a.txt")
      local origin = api.nvim_get_current_tabpage()
      vim.cmd.tabnew()
      api.nvim_set_current_tabpage(origin)
      local open_panes = session.open_panes
      session.open_panes = function()
        error("E36: Not enough room")
      end
      local tab = twintree.open()
      session.open_panes = open_panes

      assert.is_nil(tab)
      assert.equals(2, #api.nvim_list_tabpages())
      assert.equals(origin, api.nvim_get_current_tabpage())
    end)

    it("closes when it is between other tabs", function()
      dirty()
      vim.cmd.edit(repo .. "/a.txt")
      local origin = api.nvim_get_current_tabpage()
      vim.cmd.tabnew()
      api.nvim_set_current_tabpage(origin)
      local tab = assert(twintree.open())
      assert.equals(2, api.nvim_tabpage_get_number(tab))

      vim.cmd.tabclose()

      assert.equals(2, #api.nvim_list_tabpages())
      assert.is_false(api.nvim_tabpage_is_valid(tab))
      assert.same({}, tree_bufs())
    end)

    it("cannot be closed once the user made it the only tab", function()
      dirty()
      local tab = assert(twintree.open())
      vim.cmd.tabonly()

      local ok, err = pcall(vim.cmd.tabclose)

      assert.is_false(ok)
      assert.truthy(tostring(err):find("E784", 1, true), err)
      assert.truthy(session.get(tab))
    end)
  end)
end)
