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
    it("reuses a lone empty tab", function()
      local tab = assert(twintree.open())
      assert.equals(1, #api.nvim_list_tabpages())

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
      assert.is_true(vim.wo[before].scrollbind)
      assert.is_false(vim.bo.modifiable)
      assert.equals("twintree://empty", name(state.wins.after))
      assert.is_true(vim.wo[state.wins.after].diff)

      vim.cmd.buffer(first_buf)
      assert.is_true(vim.wo[before].diff)
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

  it("keeps two sessions independent", function()
    dirty()
    local one = session.get(assert(twintree.open()))
    local two = session.get(assert(twintree.open()))
    assert.equals(2, #api.nvim_list_tabpages())

    two = select(two, "new.txt")
    one = session.get(api.nvim_win_get_tabpage(one.wins.tree))
    assert.is_nil(one.selected)

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
end)
