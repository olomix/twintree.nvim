local h = require("tests.helpers")
local layout = require("twintree.layout")
local session = require("twintree.session")
local twintree = require("twintree")

local api = vim.api

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

describe("layout", function()
  local cache, repo, tab

  local function state()
    return assert(session.get(tab))
  end

  ---The tree window. A function so that luassert's extra return values
  ---never end up as arguments of the caller.
  local function tree()
    local win = session.tree_win(state())
    assert.truthy(win)
    return win
  end

  ---Widths of tree, before and after; the tree is nil when hidden.
  local function widths()
    local s = state()
    local tree = session.tree_win(s)
    return tree and api.nvim_win_get_width(tree) or nil,
      api.nvim_win_get_width(s.wins.before),
      api.nvim_win_get_width(s.wins.after)
  end

  local function assert_equal_panes()
    local _, before, after = widths()
    assert.is_true(math.abs(before - after) <= 1, ("%d vs %d"):format(before, after))
  end

  local function assert_ratio(expected)
    local _, before, after = widths()
    local actual = before / (before + after)
    assert.is_true(
      math.abs(actual - expected) < 0.02,
      ("ratio %.3f, expected %.3f"):format(actual, expected)
    )
  end

  local function select(text)
    h.goto_line(tree(), text)
    h.keys("<CR>")
  end

  ---Simulate a terminal resize. Neovim changes the rightmost window only
  ---and fires VimResized, which the plugin's autocommand handles.
  local function resize_terminal(columns)
    vim.o.columns = columns
    assert.equals(columns, state().layout.columns)
  end

  before_each(function()
    cache = h.reset()
    vim.o.columns = 160
    repo = h.repo({
      ["a.txt"] = "one\ntwo\n",
      ["src/b.txt"] = "b\n",
    })
    h.write(repo, "a.txt", "one\nTWO\n")
    h.write(repo, "src/b.txt", "B\n")
    api.nvim_set_current_dir(repo)
    tab = assert(twintree.open())
  end)

  after_each(function()
    vim.o.columns = 80
  end)

  it("fills in a layout for a session that has none", function()
    local s = state()
    s.layout = nil
    session.save(tab, s)
    assert.same(
      { ratio = 0.5, tree_width = 35, columns = 160, tree_shown = true, zoomed = false },
      state().layout
    )
  end)

  it("does nothing in a tab without a session", function()
    vim.cmd.tabnew()
    assert.is_nil(layout.sync())
    assert.is_nil(session.get())
  end)

  describe("terminal resize", function()
    it("keeps equal panes and the tree width when growing and shrinking", function()
      resize_terminal(220)
      assert.equals(35, (widths()))
      assert_equal_panes()

      resize_terminal(110)
      assert.equals(35, (widths()))
      assert_equal_panes()
    end)

    it("keeps a hand-set ratio", function()
      api.nvim_win_set_width(state().wins.before, 40)
      assert.equals("learn", layout.sync(tab))
      local ratio = state().layout.ratio
      assert.is_true(ratio < 0.4)

      resize_terminal(220)
      assert_ratio(ratio)
      resize_terminal(120)
      assert_ratio(ratio)
    end)

    it("is applied when returning from another tab", function()
      api.nvim_win_set_width(state().wins.before, 40)
      layout.sync(tab)
      local ratio = state().layout.ratio

      vim.cmd.tabnew()
      vim.o.columns = 220
      vim.cmd.tabprevious()

      assert.equals(220, state().layout.columns)
      assert_ratio(ratio)
      assert.equals(35, (widths()))
    end)

    it("keeps the ratio of the panes while the tree is hidden", function()
      api.nvim_win_set_width(state().wins.before, 40)
      layout.sync(tab)
      local ratio = state().layout.ratio
      assert(twintree.toggle_tree())

      resize_terminal(220)
      assert_ratio(ratio)
    end)

    it("recovers from a shrink that squeezes a pane", function()
      resize_terminal(60)
      resize_terminal(160)
      assert.equals(35, (widths()))
      assert_equal_panes()
      assert.is_false(state().layout.zoomed)
    end)

    -- Each resize is followed by a second size event for the same widths.
    for _, narrow in ipairs({ 30, 40 }) do
      it(("recovers from a terminal only %d columns wide"):format(narrow), function()
        resize_terminal(narrow)
        layout.sync(tab)
        assert.is_false(state().layout.zoomed)
        assert.is_true(vim.wo[tree()].winfixwidth)

        resize_terminal(200)
        layout.sync(tab)
        assert.equals(35, (widths()))
        assert_equal_panes()
        assert.equals(0.5, state().layout.ratio)
      end)
    end

    it("leaves a window of the user between the panes alone", function()
      local extra = api.nvim_open_win(api.nvim_create_buf(false, true), false, {
        split = "right",
        win = state().wins.before,
      })
      vim.cmd.wincmd("=")
      layout.sync(tab)
      local width = api.nvim_win_get_width(extra)

      resize_terminal(220)
      assert.equals(width, api.nvim_win_get_width(extra))
      assert_equal_panes()
      assert.equals(0.5, state().layout.ratio)
    end)

    it("leaves a zoomed window alone", function()
      api.nvim_set_current_win(state().wins.after)
      vim.cmd.wincmd("|")
      layout.sync(tab)
      resize_terminal(220)
      local tree_width, before = widths()
      assert.equals(1, tree_width)
      assert.equals(1, before)
    end)
  end)

  it("makes one half the kept ratio after equalizing", function()
    api.nvim_win_set_width(state().wins.before, 40)
    layout.sync(tab)
    vim.cmd.wincmd("=")
    assert.equals("learn", layout.sync(tab))
    assert.equals(0.5, state().layout.ratio)

    resize_terminal(220)
    assert_equal_panes()
  end)

  it("remembers a tree width set by hand", function()
    api.nvim_win_set_width(tree(), 50)
    layout.sync(tab)
    assert.equals(50, state().layout.tree_width)

    vim.cmd.wincmd("=")
    layout.sync(tab)
    assert.equals(50, (widths()))

    resize_terminal(220)
    assert.equals(50, (widths()))
  end)

  describe("zoom", function()
    it("of a pane is undone by equalizing", function()
      api.nvim_win_set_width(tree(), 50)
      layout.sync(tab)

      api.nvim_set_current_win(state().wins.after)
      vim.cmd.wincmd("|")
      local squeezed = { widths() }
      assert.equals(1, squeezed[1])
      assert.equals("none", layout.sync(tab))
      assert.same(squeezed, { widths() })
      assert.equals(50, state().layout.tree_width)

      vim.cmd.wincmd("=")
      assert.equals(1, (widths()))
      assert.equals("restore", layout.sync(tab))
      assert.equals(50, (widths()))
      assert_equal_panes()
      assert.equals(0.5, state().layout.ratio)
    end)

    it("of the tree is undone by equalizing", function()
      local tree = tree()
      api.nvim_set_current_win(tree)
      vim.cmd.wincmd("|")
      assert.equals("unfix", layout.sync(tab))
      assert.is_false(vim.wo[tree].winfixwidth)
      assert.equals(35, state().layout.tree_width)

      vim.cmd.wincmd("=")
      assert.equals("restore", layout.sync(tab))
      assert.equals(35, (widths()))
      assert.is_true(vim.wo[tree].winfixwidth)
      assert_equal_panes()
    end)

    it("is restored through the resize autocommand", function()
      api.nvim_set_current_win(state().wins.after)
      vim.cmd.wincmd("|")
      api.nvim_exec_autocmds("WinResized", { group = "twintree" })
      vim.cmd.wincmd("=")
      api.nvim_exec_autocmds("WinResized", { group = "twintree" })

      assert.equals(35, (widths()))
      assert_equal_panes()
    end)
  end)

  describe("hiding the tree", function()
    it("by closing its window keeps the session and the tree content", function()
      select("src/")
      select("a.txt")
      local s = state()
      local lines = h.buf_lines(s.tree_buf)

      api.nvim_win_close(assert(session.tree_win(s)), false)
      layout.sync(tab)

      s = state()
      assert.is_nil(session.tree_win(s))
      assert.is_true(api.nvim_buf_is_valid(s.tree_buf))
      assert.same(lines, h.buf_lines(s.tree_buf))
      assert.equals(2, #api.nvim_tabpage_list_wins(tab))
      assert.is_true(vim.wo[s.wins.before].diff)
      assert.is_true(vim.wo[s.wins.after].diff)
      assert.equals("a.txt", s.selected)
      assert.is_true(s.collapsed.src)
    end)

    it("by closing its window keeps the pane ratio", function()
      api.nvim_win_set_width(state().wins.before, 40)
      layout.sync(tab)
      local ratio = state().layout.ratio

      api.nvim_win_close(tree(), false)
      assert.equals("apply", layout.sync(tab))
      assert_ratio(ratio)
    end)

    it("lets a file be selected from a window the user made", function()
      local s = state()
      api.nvim_win_close(assert(session.tree_win(s)), false)
      vim.cmd("botright split")
      api.nvim_win_set_buf(0, s.tree_buf)
      h.goto_line(api.nvim_get_current_win(), "a.txt")
      h.keys("<CR>")

      s = state()
      assert.equals("a.txt", s.selected)
      assert.equals(repo .. "/a.txt", api.nvim_buf_get_name(api.nvim_win_get_buf(s.wins.after)))
      assert.is_true(vim.wo[s.wins.after].diff)
    end)
  end)

  describe("toggle_tree", function()
    it("hides and shows the tree, keeping width, ratio and selection", function()
      select("a.txt")
      api.nvim_win_set_width(tree(), 50)
      api.nvim_win_set_width(state().wins.before, 30)
      layout.sync(tab)
      local ratio = state().layout.ratio

      assert.is_true(twintree.toggle_tree())
      assert.is_nil(session.tree_win(state()))
      assert.equals(2, #api.nvim_tabpage_list_wins(tab))
      assert_ratio(ratio)

      assert.is_true(twintree.toggle_tree())
      local s = state()
      local tree = assert(session.tree_win(s))
      assert.same({ tree, s.wins.before, s.wins.after }, api.nvim_tabpage_list_wins(tab))
      assert.equals(tree, api.nvim_get_current_win())
      assert.equals(50, api.nvim_win_get_width(tree))
      assert.is_true(vim.wo[tree].winfixwidth)
      assert.is_false(vim.wo[tree].number)
      assert_ratio(ratio)
      assert.equals("M a.txt", api.nvim_get_current_line())
    end)

    it("puts the tree at the far left of any layout", function()
      assert(twintree.toggle_tree())
      api.nvim_set_current_win(state().wins.after)
      vim.cmd("topleft vsplit")
      vim.cmd("botright split")

      assert(twintree.toggle_tree())
      local tree = tree()
      assert.same({ 0, 0 }, api.nvim_win_get_position(tree))
      assert.equals(vim.o.lines - vim.o.cmdheight - 1, api.nvim_win_get_height(tree))
    end)

    it("rebuilds a tree whose buffer was deleted", function()
      local old = state().tree_buf
      local lines = h.buf_lines(old)
      api.nvim_win_close(tree(), false)
      api.nvim_buf_delete(old, { force = true })

      assert.is_true(twintree.toggle_tree())
      local s = state()
      assert.are_not.equal(old, s.tree_buf)
      assert.same(lines, h.buf_lines(s.tree_buf))
      assert.equals(s.tree_buf, api.nvim_win_get_buf(tree()))
    end)

    it("rebuilds a tree whose buffer was unloaded with :bdelete", function()
      select("a.txt")
      local old = state().tree_buf
      local lines = h.buf_lines(old)
      vim.cmd.bdelete(old)
      assert.is_true(api.nvim_buf_is_valid(old))
      assert.is_nil(session.tree_win(state()))

      assert.is_true(twintree.toggle_tree())
      local s = state()
      assert.are_not.equal(old, s.tree_buf)
      assert.is_false(api.nvim_buf_is_valid(old))
      assert.same(lines, h.buf_lines(s.tree_buf))
      assert.equals("twintree", vim.bo[s.tree_buf].filetype)
      assert.equals("nofile", vim.bo[s.tree_buf].buftype)
      assert.equals("M a.txt", api.nvim_get_current_line())

      h.goto_line(tree(), "b.txt")
      h.keys("<CR>")
      assert.equals("src/b.txt", state().selected)
    end)

    it("shows the tree at its width when it was hidden without a size change", function()
      local other = api.nvim_create_buf(false, true)
      api.nvim_win_set_buf(tree(), other)
      assert.is_nil(session.tree_win(state()))
      assert.is_true(state().layout.tree_shown)

      assert.is_true(twintree.toggle_tree())
      assert.equals(35, api.nvim_win_get_width(tree()))
      assert.equals(35, state().layout.tree_width)
      assert.equals(0.5, state().layout.ratio)
      assert_equal_panes()
    end)

    it("reports a tab with no room for the tree", function()
      assert(twintree.toggle_tree())
      while pcall(vim.cmd.vsplit) do
      end
      local count = #api.nvim_tabpage_list_wins(tab)

      local ok, err = twintree.toggle_tree()
      assert.is_nil(ok)
      assert.truthy(err:find("no room for the tree window", 1, true))
      assert.equals(count, #api.nvim_tabpage_list_wins(tab))
    end)

    it("refuses to close the tree when it is the only window", function()
      local s = state()
      api.nvim_win_close(s.wins.before, true)
      api.nvim_win_close(s.wins.after, true)

      local ok, err = twintree.toggle_tree()
      assert.is_nil(ok)
      assert.truthy(err:find(":TwintreeResetLayout", 1, true))
      assert.is_true(api.nvim_tabpage_is_valid(tab))
      assert.truthy(session.tree_win(state()))
    end)
  end)

  describe("reset_layout", function()
    local function assert_original_view()
      local s = state()
      local tree = assert(session.tree_win(s))
      assert.same({ tree, s.wins.before, s.wins.after }, api.nvim_tabpage_list_wins(tab))
      assert.equals(35, api.nvim_win_get_width(tree))
      assert.is_true(vim.wo[tree].winfixwidth)
      assert_equal_panes()
      assert.equals(0.5, s.layout.ratio)
      assert.equals(35, s.layout.tree_width)
      assert.equals(vim.o.columns, s.layout.columns)
      assert.is_true(s.layout.tree_shown)
      assert.is_false(s.layout.zoomed)
      return s
    end

    local function assert_showing(path)
      local s = state()
      assert.equals(path, s.selected)
      assert.equals(
        s.before.root .. "/" .. path,
        api.nvim_buf_get_name(api.nvim_win_get_buf(s.wins.before))
      )
      assert.equals(repo .. "/" .. path, api.nvim_buf_get_name(api.nvim_win_get_buf(s.wins.after)))
      assert.is_true(vim.wo[s.wins.before].diff)
      assert.is_true(vim.wo[s.wins.after].diff)
      assert.truthy(vim.tbl_contains(h.buf_lines(s.tree_buf), "M " .. path))
    end

    it("rebuilds the view after a pane was closed", function()
      select("a.txt")
      api.nvim_win_close(state().wins.before, true)

      assert.is_true(twintree.reset_layout())
      assert_original_view()
      assert_showing("a.txt")
    end)

    it("closes extra windows and brings back the selected file", function()
      select("src/")
      select("a.txt")
      local s = state()
      api.nvim_set_current_win(s.wins.before)
      vim.cmd.edit(s.before.root .. "/src/b.txt")
      vim.cmd("vsplit")
      vim.cmd("botright split")
      vim.cmd("topleft vnew")

      assert.is_true(twintree.reset_layout())
      s = assert_original_view()
      assert_showing("a.txt")
      assert.is_true(s.collapsed.src)
      assert.truthy(vim.tbl_contains(h.buf_lines(s.tree_buf), "▸ src/"))
    end)

    it("shows a hidden tree and forgets a widened one", function()
      api.nvim_win_set_width(tree(), 60)
      layout.sync(tab)
      assert(twintree.toggle_tree())

      assert.is_true(twintree.reset_layout())
      assert_original_view()
    end)

    it("undoes a zoom", function()
      api.nvim_set_current_win(tree())
      vim.cmd.wincmd("|")
      layout.sync(tab)

      assert.is_true(twintree.reset_layout())
      assert_original_view()
    end)

    it("leaves empty panes and the cursor in the tree when nothing is selected", function()
      api.nvim_win_close(state().wins.after, true)

      assert.is_true(twintree.reset_layout())
      local s = assert_original_view()
      assert.equals(session.tree_win(s), api.nvim_get_current_win())
      assert.equals("twintree://empty", api.nvim_buf_get_name(api.nvim_win_get_buf(s.wins.before)))
      assert.equals("twintree://empty", api.nvim_buf_get_name(api.nvim_win_get_buf(s.wins.after)))
      assert.is_false(vim.wo[s.wins.before].diff)
    end)

    it("keeps a buffer with unsaved changes when closing its window", function()
      vim.o.hidden = false
      vim.cmd("botright new")
      local buf = api.nvim_get_current_buf()
      api.nvim_buf_set_lines(buf, 0, -1, false, { "unsaved" })

      assert.is_true(twintree.reset_layout())
      vim.o.hidden = true
      assert_original_view()
      assert.is_true(api.nvim_buf_is_loaded(buf))
      assert.is_true(vim.bo[buf].modified)
      assert.same({ "unsaved" }, h.buf_lines(buf))
      api.nvim_buf_delete(buf, { force = true })
    end)

    it("rebuilds a tree whose buffer was deleted", function()
      select("a.txt")
      local old = state().tree_buf
      api.nvim_buf_delete(old, { force = true })

      assert.is_true(twintree.reset_layout())
      assert_original_view()
      assert_showing("a.txt")
    end)

    it("rebuilds a tree whose buffer was unloaded with :bdelete", function()
      select("a.txt")
      vim.cmd.bdelete(state().tree_buf)

      assert.is_true(twintree.reset_layout())
      assert_original_view()
      assert_showing("a.txt")
    end)

    it("keeps a buffer that is set to be wiped when hidden", function()
      vim.cmd("botright new")
      local buf = api.nvim_get_current_buf()
      vim.bo[buf].buftype = "nofile"
      vim.bo[buf].bufhidden = "wipe"
      api.nvim_buf_set_lines(buf, 0, -1, false, { "scratch" })

      assert.is_true(twintree.reset_layout())
      assert_original_view()
      assert.is_true(api.nvim_buf_is_valid(buf))
      assert.same({ "scratch" }, h.buf_lines(buf))
      assert.equals("wipe", vim.bo[buf].bufhidden)
      api.nvim_buf_delete(buf, { force = true })
    end)

    it("works in a tab that has no room for another window", function()
      select("a.txt")
      api.nvim_set_current_win(state().wins.after)
      while pcall(vim.cmd.vsplit) do
      end
      assert.is_false(pcall(vim.cmd.vsplit))

      assert.is_true(twintree.reset_layout())
      assert_original_view()
      assert_showing("a.txt")
    end)
  end)

  describe("commands", function()
    it("are registered", function()
      local commands = api.nvim_get_commands({})
      assert.truthy(commands.TwintreeToggleTree)
      assert.truthy(commands.TwintreeResetLayout)
    end)

    it("work in a diff tab", function()
      vim.cmd("TwintreeToggleTree")
      assert.is_nil(session.tree_win(state()))
      vim.cmd("TwintreeResetLayout")
      assert.truthy(session.tree_win(state()))
      assert.equals(3, #api.nvim_tabpage_list_wins(tab))
    end)

    for _, command in ipairs({ "TwintreeToggleTree", "TwintreeResetLayout" }) do
      it(command .. " reports a tab without a diff session", function()
        vim.cmd.tabnew()
        vim.cmd.vsplit()
        local wins = api.nvim_tabpage_list_wins(0)

        local messages, restore = capture_notify()
        vim.cmd(command)
        restore()

        assert.same({
          {
            msg = "twintree: no diff session in this tab",
            level = vim.log.levels.ERROR,
          },
        }, messages)
        assert.same(wins, api.nvim_tabpage_list_wins(0))
        assert.is_nil(session.get())
      end)
    end
  end)

  describe("tree buffer", function()
    ---Open a second diff in its own tab.
    local function open_second()
      vim.cmd.tabnew()
      vim.cmd.edit(repo .. "/a.txt")
      local second = assert(twintree.open())
      assert.are_not.equal(tab, second)
      return second, assert(session.get(second)).tree_buf
    end

    it("is deleted when its tab closes", function()
      local second, buf = open_second()
      api.nvim_set_current_tabpage(second)
      vim.cmd.tabclose()
      assert.is_false(api.nvim_buf_is_valid(buf))
    end)

    it("is deleted with its tab after :bdelete unloaded it", function()
      local second, buf = open_second()
      api.nvim_set_current_tabpage(second)
      vim.cmd.bdelete(buf)
      assert.is_true(api.nvim_buf_is_valid(buf))
      vim.cmd.tabclose()
      assert.is_false(api.nvim_buf_is_valid(buf))
    end)

    it("is deleted when its tab closes with the tree hidden", function()
      local second, buf = open_second()
      api.nvim_set_current_tabpage(second)
      assert(twintree.toggle_tree())
      assert.is_true(api.nvim_buf_is_valid(buf))
      vim.cmd.tabclose()
      assert.is_false(api.nvim_buf_is_valid(buf))
    end)

    it("of another diff tab survives", function()
      local second = open_second()
      local first_buf = state().tree_buf
      api.nvim_set_current_tabpage(second)
      vim.cmd.tabclose()

      assert.is_true(api.nvim_buf_is_valid(first_buf))
      api.nvim_set_current_tabpage(tab)
      select("a.txt")
      assert.equals("a.txt", state().selected)
    end)
  end)

  it("keeps one set of autocommands after the plugin file is sourced again", function()
    local before = #api.nvim_get_autocmds({ group = "twintree" })
    vim.cmd.runtime("plugin/twintree.lua")
    assert.equals(before, #api.nvim_get_autocmds({ group = "twintree" }))
    assert.equals(
      1,
      #api.nvim_get_autocmds({ group = "twintree", event = "WinResized" })
    )
    assert.equals(1, #api.nvim_get_autocmds({ group = "twintree", event = "TabClosed" }))
    assert.truthy(cache)
  end)
end)
