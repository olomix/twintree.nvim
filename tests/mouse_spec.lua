local h = require("tests.helpers")
local session = require("twintree.session")
local twintree = require("twintree")

local api = vim.api

describe("the mouse in the tree", function()
  local repo, tab, mouse, messages, notify

  local function state()
    return assert(session.get(tab))
  end

  ---In parentheses: one value, also as the argument of another call.
  local function tree()
    return (assert(session.tree_win(state())))
  end

  local function shown(pane)
    return api.nvim_buf_get_name(api.nvim_win_get_buf(state().wins[pane]))
  end

  ---Double-click the tree line containing `text` in `win`.
  local function double_click(text, win)
    win = win or tree()
    local row = h.goto_line(win, text)
    mouse = { winid = win, line = row }
    h.keys("<2-LeftMouse>")
  end

  before_each(function()
    h.reset()
    messages = {}
    notify = vim.notify
    vim.notify = function(msg)
      table.insert(messages, msg)
    end
    vim.fn.getmousepos = function()
      return mouse
    end
    repo = h.repo({ ["a.txt"] = "a\n", ["src/app.lua"] = "app\n" })
    h.write(repo, "a.txt", "a changed\n")
    h.write(repo, "src/app.lua", "app changed\n")
    vim.cmd.cd(repo)
  end)

  after_each(function()
    vim.notify = notify
    vim.fn.getmousepos = nil
    pcall(api.nvim_del_augroup_by_name, "mouse_spec")
  end)

  describe("double click", function()
    before_each(function()
      tab = assert(twintree.open())
    end)

    it("shows the file of the line", function()
      double_click("app.lua")
      assert.equals(repo .. "/src/app.lua", shown("after"))
      assert.equals("src/app.lua", state().selected)
      assert.equals(state().wins.after, api.nvim_get_current_win())
    end)

    it("folds and unfolds a directory", function()
      double_click("src/")
      assert.is_true(state().collapsed["src"])
      assert.is_nil(h.tree_lines(state().tree_buf)[3])
      double_click("src/")
      assert.is_nil(state().collapsed["src"])
      assert.truthy(h.tree_lines(state().tree_buf)[3])
    end)

    it("works in a second window that shows the tree", function()
      api.nvim_set_current_win(tree())
      vim.cmd.split()
      double_click("app.lua", api.nvim_get_current_win())
      assert.equals(repo .. "/src/app.lua", shown("after"))
    end)

    it("asks to reset the layout when a pane is missing", function()
      api.nvim_win_close(state().wins.before, true)
      double_click("app.lua")
      assert.equals("twintree: " .. session.BROKEN_LAYOUT, messages[#messages])
    end)

    it("leaves a click outside the text of the tree to Neovim", function()
      local before = shown("after")
      for _, position in ipairs({
        { winid = tree(), line = 0 },
        { winid = state().wins.after, line = 1 },
        { winid = 0, line = 0 },
      }) do
        h.goto_line(tree(), "src/")
        mouse = position
        h.keys("<2-LeftMouse>")
        h.keys("<Esc>")
        assert.is_nil(state().collapsed["src"])
        assert.equals(before, shown("after"))
      end
    end)

    it("maps no other click", function()
      api.nvim_set_current_win(tree())
      for _, key in ipairs({
        "<LeftMouse>",
        "<LeftDrag>",
        "<LeftRelease>",
        "<3-LeftMouse>",
        "<4-LeftMouse>",
      }) do
        assert.equals("", vim.fn.maparg(key, "n"))
      end
      assert.equals(1, vim.fn.maparg("<2-LeftMouse>", "n", false, true).buffer)
    end)
  end)

  it("says that the diff of a tree shown in another tab is elsewhere", function()
    tab = assert(twintree.open())
    local before, buf = shown("after"), state().tree_buf
    local other = h.repo({ ["z.txt"] = "z\n", ["y.txt"] = "y\n" })
    h.write(other, "z.txt", "z changed\n")
    h.write(other, "y.txt", "y changed\n")

    local function assert_refused(key)
      messages = {}
      local win = api.nvim_get_current_win()
      api.nvim_win_set_cursor(win, { 1, 0 })
      mouse = { winid = win, line = 1 }
      h.keys(key)
      assert.same({ "twintree: the diff of this tree is in another tab" }, messages)
      assert.equals(before, shown("after"))
      assert.is_nil(state().collapsed["src"])
    end

    -- A tab without a diff.
    vim.cmd("tab sbuffer " .. buf)
    assert_refused("<CR>")
    assert_refused("<2-LeftMouse>")
    vim.cmd.tabclose()

    -- Another diff tab: its own lines are not those of this tree.
    vim.cmd.cd(other)
    local second = assert(twintree.open())
    local second_after = api.nvim_win_get_buf(session.get(second).wins.after)
    vim.cmd("sbuffer " .. buf)
    assert_refused("<CR>")
    assert_refused("<2-LeftMouse>")
    assert.equals(second_after, api.nvim_win_get_buf(session.get(second).wins.after))
  end)

  it("lets a key of the user for the filetype replace the plugin's", function()
    local pressed = {}
    api.nvim_create_autocmd("FileType", {
      group = api.nvim_create_augroup("mouse_spec", {}),
      pattern = "twintree",
      callback = function(ev)
        for _, key in ipairs({ "<2-LeftMouse>", "<CR>" }) do
          vim.keymap.set("n", key, function()
            table.insert(pressed, key)
          end, { buffer = ev.buf })
        end
      end,
    })
    tab = assert(twintree.open())
    local before = shown("after")

    double_click("app.lua")
    h.goto_line(tree(), "app.lua")
    h.keys("<CR>")

    assert.same({ "<2-LeftMouse>", "<CR>" }, pressed)
    assert.equals(before, shown("after"))
  end)
end)

-- A second Neovim in a pseudo-terminal: only a real screen turns a click
-- into a window, a line and a menu.
describe("the mouse on a real screen", function()
  local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
  local job, chan, tab, repo

  local function lua(code, ...)
    return vim.rpcrequest(chan, "nvim_exec_lua", code, { ... })
  end

  local STATE = [[
    local session = require("twintree.session")
    local state = session.get(...)
    local tree = session.tree_win(state)
    local function file(pane)
      return vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(state.wins[pane]))
    end
    return {
      after = vim.fs.basename(file("after")),
      mode = vim.fn.mode(),
      in_tree = vim.api.nvim_get_current_win() == tree,
      tree_line = vim.api.nvim_win_get_cursor(tree)[1],
      lines = #vim.api.nvim_buf_get_lines(state.tree_buf, 0, -1, false),
      clipboard = _G.test_clipboard or vim.NIL,
      popups = _G.popups,
    }
  ]]

  local function current()
    return lua(STATE, tab)
  end

  ---Wait until the child satisfies `check` and return its state.
  local function settle(check, what)
    local last
    local ok = vim.wait(5000, function()
      last = current()
      return check(last)
    end, 50)
    assert(ok, ("%s; last state: %s"):format(what, vim.inspect(last)))
    return last
  end

  ---Screen cell, counted from 1, of the tree line containing `text`, or of
  ---the status line of the tree.
  local function cell(text)
    return lua(
      [[
        local session = require("twintree.session")
        local state = session.get(select(1, ...))
        local win = session.tree_win(state)
        local top = vim.api.nvim_win_get_position(win)[1]
        if select(2, ...) == vim.NIL then
          return { row = top + vim.api.nvim_win_get_height(win) + 1, col = 6 }
        end
        for i, line in ipairs(vim.api.nvim_buf_get_lines(state.tree_buf, 0, -1, false)) do
          if line:find(select(2, ...), 1, true) then
            return { row = top + i, col = 6 }
          end
        end
        error("no tree line with " .. select(2, ...))
      ]],
      tab,
      text or vim.NIL
    )
  end

  ---Send mouse input as the terminal does (SGR). Button 0 is the left one,
  ---2 the right one; 32 is added for a move with the button down.
  local function mouse(button, at, kind)
    local final = kind == "release" and "m" or "M"
    vim.fn.chansend(job, ("\27[<%d;%d;%d%s"):format(button, at.col, at.row, final))
    -- Events sent in one burst are not all seen: a drag is lost.
    vim.wait(40)
  end

  local function click(at, times, button)
    for _ = 1, times or 1 do
      mouse(button or 0, at, "press")
      mouse(button or 0, at, "release")
    end
  end

  ---Keys typed into the terminal: the child answers no request while a
  ---menu is open.
  local function type_keys(keys)
    vim.fn.chansend(job, keys)
  end

  local function focus(pane)
    lua(
      [[
        local session = require("twintree.session")
        local state = session.get(select(1, ...))
        local win = select(2, ...) == "tree" and session.tree_win(state)
          or state.wins[select(2, ...)]
        vim.api.nvim_set_current_win(win)
      ]],
      tab,
      pane
    )
  end

  before_each(function()
    repo = h.repo({ ["0.txt"] = "zero\n", ["b.txt"] = "one\n", ["src/app.lua"] = "app\n" })
    h.write(repo, "0.txt", "ZERO\n")
    h.write(repo, "b.txt", "two\n")
    h.write(repo, "src/app.lua", "app changed\n")
    local socket = vim.fn.tempname()
    local ok, id = pcall(vim.fn.jobstart, {
      vim.v.progpath,
      "-u",
      root .. "/tests/minimal_init.lua",
      "--listen",
      socket,
    }, { pty = true, width = 160, height = 40, cwd = repo, env = { TERM = "xterm-256color" } })
    job = ok and id > 0 and id or nil
    if not job then
      return
    end
    assert(vim.wait(5000, function()
      return vim.uv.fs_stat(socket) ~= nil
    end, 50), "child Neovim did not start")
    chan = vim.fn.sockconnect("pipe", socket, { rpc = true })
    assert(vim.wait(5000, function()
      local ready, entered = pcall(lua, "return vim.v.vim_did_enter")
      return ready and entered == 1
    end, 50), "child Neovim did not finish starting")
    tab = lua(
      [[
        require("twintree").setup({ cache_dir = ... })
        vim.o.mouse = "a"
        vim.o.mousemodel = "popup_setpos"
        -- What the menu held each time it opened, and for which mode.
        _G.popups = {}
        vim.api.nvim_create_autocmd("MenuPopup", {
          callback = function(ev)
            local ok, menus = pcall(vim.fn.menu_get, "PopUp", "n")
            local names = {}
            for _, item in ipairs(ok and menus[1] and menus[1].submenus or {}) do
              table.insert(names, item.name)
            end
            table.insert(_G.popups, { mode = ev.match, first = names[1] })
          end,
        })
        return assert(require("twintree").open())
      ]],
      h.tmpdir()
    )
    -- The tree lists src/, app.lua, 0.txt and b.txt; app.lua is shown.
    settle(function(s)
      return s.after == "app.lua"
    end, "the diff after opening")
  end)

  after_each(function()
    if chan then
      pcall(vim.fn.chanclose, chan)
      chan = nil
    end
    if job then
      vim.fn.jobstop(job)
      job = nil
    end
  end)

  ---Skip when this system cannot open a pseudo-terminal.
  local function pty_it(name, fn)
    it(name, function()
      if not job then
        print("skipped, no pseudo-terminal available: " .. name)
        return
      end
      fn()
    end)
  end

  pty_it("shows a file on a double click and only moves on a single one", function()
    focus("after")
    -- Not the line of the double click below: three clicks on one cell in
    -- a row are a triple click.
    click(cell("b.txt"))
    local s = settle(function(now)
      return now.in_tree
    end, "a single click")
    assert.equals("app.lua", s.after)
    assert.equals(4, s.tree_line)

    focus("after")
    click(cell("0.txt"), 2)
    settle(function(now)
      return now.after == "0.txt" and not now.in_tree
    end, "a double click from a pane")

    -- Below the last line the cursor lands on the last line, b.txt.
    local last = cell("b.txt")
    click({ row = last.row + 5, col = last.col }, 2)
    settle(function(now)
      return now.after == "b.txt"
    end, "a double click below the last line")
  end)

  pty_it("selects text on a drag and a line on a triple click", function()
    focus("tree")
    local at = cell("b.txt")
    mouse(0, at, "press")
    mouse(32, { row = at.row, col = at.col + 2 }, "press")
    mouse(32, { row = at.row, col = at.col + 4 }, "press")
    mouse(0, { row = at.row, col = at.col + 4 }, "release")
    local s = settle(function(now)
      return now.mode == "v"
    end, "a drag")
    assert.equals("app.lua", s.after)
    type_keys("\27")
    settle(function(now)
      return now.mode == "n"
    end, "leaving the selection")

    -- A directory line: the first two clicks fold it, the third selects.
    click(cell("src/"), 3)
    s = settle(function(now)
      return now.mode == "V"
    end, "a triple click")
    assert.equals("app.lua", s.after)
  end)

  pty_it("leaves a double click on the status line of the tree alone", function()
    focus("tree")
    local lines = current().lines
    -- On the directory: acting on the line of the cursor would fold it.
    lua("vim.api.nvim_win_set_cursor(0, { 1, 0 })")
    click(cell(), 2)
    vim.wait(300)
    local s = current()
    assert.equals(lines, s.lines)
    assert.equals("app.lua", s.after)
  end)

  pty_it("copies the path of the line that was clicked with the right button", function()
    focus("tree")
    lua("vim.api.nvim_win_set_cursor(0, { 1, 0 })")
    focus("after")
    click(cell("b.txt"), 1, 2)
    type_keys("\27[B\r")
    local s = settle(function(now)
      return now.clipboard ~= vim.NIL
    end, "choosing the first item of the menu")
    assert.equals("b.txt", s.clipboard)
    assert.same({ mode = "n", first = "Copy relative path" }, s.popups[#s.popups])

    -- In a pane the menu has none of the items.
    lua("_G.test_clipboard = nil")
    mouse(2, { row = 5, col = 100 }, "press")
    mouse(2, { row = 5, col = 100 }, "release")
    type_keys("\27")
    s = settle(function(now)
      return #now.popups == 2
    end, "a right click in a pane")
    assert.are_not.equal("Copy relative path", s.popups[2].first)
    assert.equals(vim.NIL, s.clipboard)
  end)

  pty_it("keeps Neovim's menu for a right click in a selection", function()
    focus("tree")
    type_keys("V")
    settle(function(now)
      return now.mode == "V"
    end, "selecting a line")
    local line = current().tree_line
    local top = cell("src/")
    click({ row = top.row + line - 1, col = top.col }, 1, 2)
    type_keys("\27")
    local s = settle(function(now)
      return #now.popups == 1
    end, "a right click in the selection")
    assert.equals("v", s.popups[1].mode)
    assert.are_not.equal("Copy relative path", s.popups[1].first)
  end)
end)
