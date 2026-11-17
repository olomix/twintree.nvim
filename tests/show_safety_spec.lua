-- A pane or the diff tab that goes away while a file is being shown.
-- Autocommands stand in for the user's own, and close things at the
-- events the plugin fires on the way.

local h = require("tests.helpers")
local session = require("twintree.session")
local treeview = require("twintree.treeview")
local twintree = require("twintree")

local api = vim.api

local ERROR = vim.log.levels.ERROR

describe("showing a file while the layout changes", function()
  local repo, tab, origin, messages, notify, armed

  local function state()
    return assert(session.get(tab))
  end

  local function name(win)
    return api.nvim_buf_get_name(api.nvim_win_get_buf(win))
  end

  local function entry(path)
    for _, file in ipairs(treeview.files(tab)) do
      if file.entry.path == path then
        return file.entry
      end
    end
    error("not a changed file: " .. path)
  end

  ---Run `fn` once, the first time `event` fires for a match of `pattern`
  ---and `when` agrees.
  local function once(event, pattern, fn, when)
    local id
    id = api.nvim_create_autocmd(event, {
      pattern = pattern,
      callback = function(args)
        if when and not when(args) then
          return
        end
        pcall(api.nvim_del_autocmd, id)
        fn()
      end,
    })
    table.insert(armed, id)
  end

  local function close(pane)
    return function()
      api.nvim_win_close(state().wins[pane], true)
    end
  end

  local function close_tab()
    vim.cmd("tabclose!")
  end

  local real_cmd = vim.cmd

  ---Run `fn` right after diff mode was switched on or off for the `nth`
  ---time. Stands in for an `OptionSet` autocommand: that event does not
  ---fire while Neovim starts, which is when the suite runs.
  local function after_diff(switch, nth, fn)
    local seen = 0
    vim.cmd = setmetatable({}, {
      __index = real_cmd,
      __call = function(_, command, ...)
        local result = real_cmd(command, ...)
        if command == switch then
          seen = seen + 1
          if seen == nth then
            vim.cmd = real_cmd
            fn()
          end
        end
        return result
      end,
    })
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

  ---The session as it was before an attempt to show b.txt, with `gone`
  ---closed on the way.
  local function assert_taken_back(gone, before)
    local s = state()
    local left = gone == "after" and "before" or "after"
    assert.is_false(api.nvim_win_is_valid(s.wins[gone]))
    assert.same(before.pair, s.pair)
    assert.equals("a.txt", s.selected)
    assert.same(before.bufs, s.bufs)
    assert.same({ "a.txt +1 -1 M" }, marked_lines())
    assert.equals(before.names[left], name(s.wins[left]))
    assert.is_false(vim.wo[s.wins[left]].diff)
    -- Not counted as shown.
    assert.same(before.viewed, s.viewed)
    assert.equals("a.txt", s.last_entry)
  end

  local function snapshot()
    local s = state()
    return {
      pair = vim.deepcopy(s.pair),
      bufs = vim.deepcopy(s.bufs),
      viewed = vim.deepcopy(s.viewed),
      names = { before = name(s.wins.before), after = name(s.wins.after) },
    }
  end

  before_each(function()
    h.reset()
    vim.o.columns = 160
    armed = {}
    repo = h.repo({ ["a.txt"] = "a\n", ["b.txt"] = "b\n", ["c.txt"] = "c\n" })
    for _, file in ipairs({ "a.txt", "b.txt" }) do
      h.write(repo, file, "changed\n")
    end
    api.nvim_set_current_dir(repo)
    -- A tab of the user, to see that it is left alone.
    vim.cmd.edit(repo .. "/c.txt")
    origin = api.nvim_get_current_win()
    tab = assert(twintree.open())
    assert.equals("a.txt", state().selected)

    messages = {}
    notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(messages, { msg = msg, level = level })
    end
  end)

  after_each(function()
    vim.notify = notify
    vim.cmd = real_cmd
    for _, id in ipairs(armed) do
      pcall(api.nvim_del_autocmd, id)
    end
    vim.o.columns = 80
  end)

  describe("layout_problem", function()
    it("is nil for an intact session", function()
      assert.is_nil(session.layout_problem(tab))
    end)

    it("is the missing pane message with either pane closed", function()
      api.nvim_win_close(state().wins.after, true)
      assert.equals(session.BROKEN_LAYOUT, session.layout_problem(tab))
      assert(twintree.reset_layout())
      api.nvim_win_close(state().wins.before, true)
      assert.equals(session.BROKEN_LAYOUT, session.layout_problem(tab))
    end)

    it("is the tab message for a closed tab and for a tab without a session", function()
      assert.equals(session.TAB_GONE, session.layout_problem(api.nvim_win_get_tabpage(origin)))
      vim.cmd("tabclose!")
      assert.equals(session.TAB_GONE, session.layout_problem(tab))
    end)
  end)

  ---Cases that close a pane at one event of an attempt to show b.txt.
  ---Each arms its autocommands and returns the pane that goes away.
  local pane_cases = {
    ["when the buffers are registered"] = function()
      once("BufNew", "*/b.txt", close("after"))
      return "after"
    end,
    ["when diff mode is switched off"] = function()
      after_diff("diffoff", 1, close("after"))
      return "after"
    end,
    ["the other pane, while the first file is loaded"] = function(s)
      once("BufReadPost", s.before.root .. "/b.txt", close("after"))
      return "after"
    end,
    ["the loading pane, while the first file is loaded"] = function(s)
      once("BufReadPost", s.before.root .. "/b.txt", close("before"))
      return "before"
    end,
    ["the other pane, while the second file is loaded"] = function()
      once("BufReadPost", repo .. "/b.txt", close("before"))
      return "before"
    end,
    ["the loading pane, while the second file is loaded"] = function()
      once("BufReadPost", repo .. "/b.txt", close("after"))
      return "after"
    end,
    ["the other pane, when diff mode is switched on"] = function()
      after_diff("diffthis", 1, close("after"))
      return "after"
    end,
    -- Nothing raises here: no step uses a window after this one.
    ["the first pane, when diff mode is switched on in the last"] = function()
      after_diff("diffthis", 2, close("before"))
      return "before"
    end,
  }

  for label, arm in pairs(pane_cases) do
    it("takes the attempt back for a pane closed " .. label, function()
      local before = snapshot()
      local gone = arm(state())

      local ran, ok, err = pcall(session.show, tab, entry("b.txt"))
      assert.is_true(ran, tostring(ok))
      assert.is_false(ok)
      assert.equals(session.BROKEN_LAYOUT, err)
      assert_taken_back(gone, before)
      assert.same({}, messages)
    end)
  end

  it("reports a pane closed during a selection in the tree in one line", function()
    local s = state()
    once("BufReadPost", s.before.root .. "/b.txt", close("after"))
    h.goto_line(assert(session.tree_win(s)), "b.txt")
    local ran, err = pcall(h.keys, "<CR>")
    assert.is_true(ran, tostring(err))
    assert.same({ { msg = "twintree: " .. session.BROKEN_LAYOUT, level = ERROR } }, messages)
    assert.truthy(messages[1].msg:find(":TwintreeResetLayout", 1, true))
  end)

  it("shows the file on its first change once the layout is back", function()
    local lines = {}
    for i = 1, 100 do
      lines[i] = "line " .. i
    end
    h.write(repo, "b.txt", table.concat(lines, "\n") .. "\n")
    h.commit(repo, "long")
    lines[60] = "changed"
    h.write(repo, "b.txt", table.concat(lines, "\n") .. "\n")
    h.write(repo, "a.txt", "changed again\n")
    -- A new session: the before side of the first one is the old commit.
    vim.cmd("tabclose!")
    tab = assert(twintree.open())

    local s = state()
    once("BufReadPost", s.before.root .. "/b.txt", close("after"))
    assert.is_false(session.show(tab, entry("b.txt")))
    assert(twintree.reset_layout())
    assert(session.show(tab, entry("b.txt")))
    assert.equals("b.txt", state().selected)
    assert.equals(60, api.nvim_win_get_cursor(state().wins.after)[1])
  end)

  it("keeps the declined swap file path: both panes, previous pair in diff mode", function()
    local swap = require("twintree.swap")
    local open = swap.open
    local s = state()
    local before = snapshot()
    -- Stands in for a swap file prompt answered with Abort.
    swap.open = function(win, buf, keepalt)
      if win == s.wins.after then
        return false, swap.DECLINED
      end
      return open(win, buf, keepalt)
    end
    local ran, ok, err = pcall(session.show, tab, entry("b.txt"))
    swap.open = open
    assert.is_true(ran, tostring(ok))
    assert.is_false(ok)
    assert.equals("b.txt was not opened: " .. swap.DECLINED, err)
    s = state()
    assert.same(before.pair, s.pair)
    assert.equals(before.names.before, name(s.wins.before))
    assert.equals(before.names.after, name(s.wins.after))
    assert.is_true(vim.wo[s.wins.before].diff)
    assert.is_true(vim.wo[s.wins.after].diff)
    assert.same(before.viewed, s.viewed)
  end)

  it("raises an error that the layout does not explain", function()
    local draw = treeview.draw
    treeview.draw = function()
      error("a bug in the tree", 0)
    end
    local ran, err = pcall(session.show, tab, entry("b.txt"))
    treeview.draw = draw
    assert.is_false(ran)
    assert.equals("a bug in the tree", err)
    assert.is_nil(session.layout_problem(tab))
  end)

  describe("a closed tab", function()
    local function assert_origin_untouched()
      assert.equals(1, #api.nvim_list_tabpages())
      assert.is_false(api.nvim_tabpage_is_valid(tab))
      assert.equals(origin, api.nvim_get_current_win())
      assert.same({ origin }, api.nvim_tabpage_list_wins(0))
      assert.equals(repo .. "/c.txt", name(origin))
      assert.is_false(vim.wo[origin].diff)
    end

    it("while a selected file is loaded gives one message", function()
      local s = state()
      once("BufReadPost", s.before.root .. "/b.txt", close_tab)
      local ran, ok, err = pcall(session.show, tab, entry("b.txt"))
      assert.is_true(ran, tostring(ok))
      assert.is_false(ok)
      assert.equals(session.TAB_GONE, err)
      assert_origin_untouched()
    end)

    it("while the second file is loaded gives one message", function()
      once("BufReadPost", repo .. "/b.txt", close_tab)
      local ran, ok, err = pcall(session.show, tab, entry("b.txt"))
      assert.is_true(ran, tostring(ok))
      assert.is_false(ok)
      assert.equals(session.TAB_GONE, err)
      assert_origin_untouched()
    end)

    it("during a selection in the tree is reported in one line", function()
      local s = state()
      once("BufReadPost", s.before.root .. "/b.txt", close_tab)
      h.goto_line(assert(session.tree_win(s)), "b.txt")
      local ran, err = pcall(h.keys, "<CR>")
      assert.is_true(ran, tostring(err))
      assert.same({ { msg = "twintree: " .. session.TAB_GONE, level = ERROR } }, messages)
      assert_origin_untouched()
    end)

    it("while the tree is drawn gives the message, not an error", function()
      local draw = treeview.draw
      treeview.draw = function(...)
        treeview.draw = draw
        vim.cmd("tabclose!")
        return draw(...)
      end
      local ran, ok, err = pcall(session.show, tab, entry("b.txt"))
      treeview.draw = draw
      assert.is_true(ran, tostring(ok))
      assert.is_false(ok)
      assert.equals(session.TAB_GONE, err)
      assert_origin_untouched()
    end)
  end)
end)
