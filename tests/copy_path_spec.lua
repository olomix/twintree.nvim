local h = require("tests.helpers")
local session = require("twintree.session")
local twintree = require("twintree")

local api = vim.api

describe("copying a path", function()
  local repo, tab, messages, notify, outside

  local function state()
    return assert(session.get(tab))
  end

  local function tree()
    local win = session.tree_win(state())
    assert.truthy(win)
    return win
  end

  ---Run the command and return what the clipboard holds afterwards.
  local function copy(form)
    vim.cmd("TwintreeCopyPath " .. (form or ""))
    return _G.test_clipboard
  end

  ---Run the command with the cursor on the tree line containing `text`.
  local function copy_line(text, form)
    h.goto_line(tree(), text)
    return copy(form)
  end

  local function last_message()
    return messages[#messages] or {}
  end

  ---Assert that the command copied nothing and reported `text`.
  local function assert_refused(text)
    assert.is_nil(_G.test_clipboard)
    assert.truthy(last_message().msg:find(text, 1, true), last_message().msg)
    assert.equals(vim.log.levels.ERROR, last_message().level)
  end

  local function open(revs)
    vim.cmd.cd(repo)
    tab = assert(twintree.open(revs))
  end

  before_each(function()
    h.reset()
    _G.test_clipboard = nil
    messages = {}
    notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(messages, { msg = msg, level = level })
    end
    repo = h.repo({
      ["a.txt"] = "a\n",
      ["src/app.lua"] = "app\n",
      ["lib/a/b/c.txt"] = "c\n",
      ["gone/old.txt"] = "old\n",
      ["same.txt"] = "same\n",
      ["my file.txt"] = "spaces\n",
      ["we\tird.txt"] = "tab\n",
      ["end\r"] = "cr\n",
      ["ren/first.txt"] = "renamed 1\nrenamed 2\nrenamed 3\n",
    })
    h.write(repo, "a.txt", "a changed\n")
    h.write(repo, "src/app.lua", "app changed\n")
    h.write(repo, "lib/a/b/c.txt", "c changed\n")
    h.write(repo, "my file.txt", "spaces changed\n")
    h.write(repo, "we\tird.txt", "tab changed\n")
    h.write(repo, "end\r", "cr changed\n")
    h.write(repo, "new.txt", "new\n")
    h.git(repo, "add", "new.txt")
    h.git(repo, "rm", "-q", "-r", "gone")
    h.git(repo, "mv", "ren/first.txt", "ren/second.txt")
    outside = h.tmpdir() .. "/dep.txt"
    h.write(vim.fs.dirname(outside), "dep.txt", "dep\n")
  end)

  after_each(function()
    vim.notify = notify
    vim.fn.has = nil
    vim.fn.setreg = nil
  end)

  it("uses a clipboard of the tests, not the one of the system", function()
    assert.equals(1, vim.fn.has("clipboard"))
    vim.fn.setreg("+", "from a spec")
    assert.equals("from a spec", _G.test_clipboard)
    assert.equals("from a spec", vim.fn.getreg("+"))
  end)

  describe("the three forms", function()
    before_each(open)

    it("copies the relative path and reports it", function()
      assert.equals("src/app.lua", copy_line("app.lua", "relative"))
      assert.equals("twintree: copied src/app.lua", last_message().msg)
    end)

    it("copies the relative path without an argument", function()
      assert.equals("src/app.lua", copy_line("app.lua"))
    end)

    it("copies the name", function()
      assert.equals("app.lua", copy_line("app.lua", "name"))
    end)

    it("copies the absolute path of a file of the working tree", function()
      assert.equals(repo .. "/src/app.lua", copy_line("app.lua", "absolute"))
    end)

    it("copies the path of a deleted file on the before side", function()
      assert.equals("gone/old.txt", copy_line("old.txt", "relative"))
      assert.equals(state().before.root .. "/gone/old.txt", copy_line("old.txt", "absolute"))
    end)

    it("copies the before side for a file that is on neither side", function()
      vim.fn.delete(repo .. "/new.txt")
      assert.equals(state().before.root .. "/new.txt", copy_line("new.txt", "absolute"))
    end)

    it("copies the new path of a renamed file", function()
      assert.equals("ren/second.txt", copy_line("second.txt", "relative"))
      assert.equals(repo .. "/ren/second.txt", copy_line("second.txt", "absolute"))
      assert.equals("second.txt", copy_line("second.txt", "name"))
    end)

    it("copies the path of a directory", function()
      assert.equals("src", copy_line("src/", "relative"))
      assert.equals(repo .. "/src", copy_line("src/", "absolute"))
      assert.equals("src", copy_line("src/", "name"))
    end)

    it("copies the innermost directory of a line of nested directories", function()
      assert.equals("lib/a/b", copy_line("lib/a/b/", "relative"))
      assert.equals(repo .. "/lib/a/b", copy_line("lib/a/b/", "absolute"))
      assert.equals("b", copy_line("lib/a/b/", "name"))
    end)

    it("copies the before side of a directory that is only there", function()
      assert.equals(state().before.root .. "/gone", copy_line("gone/", "absolute"))
    end)

    it("copies a path with spaces as it is", function()
      assert.equals("my file.txt", copy_line("my file.txt", "relative"))
      assert.equals(repo .. "/my file.txt", copy_line("my file.txt", "absolute"))
    end)

    it("copies a control character raw and reports it escaped", function()
      assert.equals("we\tird.txt", copy_line("ird.txt", "relative"))
      assert.equals("twintree: copied we\\x09ird.txt", last_message().msg)
    end)

    it("adds nothing to a name that ends in a line break", function()
      assert.equals("end\r", copy_line("end", "relative"))
      assert.equals("end\r", vim.fn.getreg("+"))
      assert.equals("twintree: copied end\\x0d", last_message().msg)
    end)

    it("completes the three forms", function()
      assert.same(
        { "relative", "absolute", "name" },
        vim.fn.getcompletion("TwintreeCopyPath ", "cmdline")
      )
      assert.same({ "absolute" }, vim.fn.getcompletion("TwintreeCopyPath a", "cmdline"))
    end)
  end)

  it("copies the after side of a diff of two commits", function()
    h.commit(repo, "second")
    open({ "HEAD~1", "HEAD" })
    local after = state().after.root
    assert.are_not.equal(repo, after)
    assert.equals(after .. "/src/app.lua", copy_line("app.lua", "absolute"))
    assert.equals(state().before.root .. "/gone/old.txt", copy_line("old.txt", "absolute"))
  end)

  describe("what it acts on", function()
    before_each(open)

    ---Show the file of the tree line containing `text`; the cursor ends in
    ---the after pane.
    local function show(text)
      h.goto_line(tree(), text)
      h.keys("<CR>")
      assert.equals(state().wins.after, api.nvim_get_current_win())
    end

    it("uses the shown file in a pane, wherever the tree cursor is", function()
      show("app.lua")
      h.goto_line(tree(), "a.txt")
      api.nvim_set_current_win(state().wins.before)
      assert.equals("src/app.lua", copy("relative"))
      assert.equals(repo .. "/src/app.lua", copy("absolute"))
    end)

    it("uses an unchanged file that a pane shows", function()
      api.nvim_set_current_win(state().wins.after)
      vim.cmd.edit(repo .. "/same.txt")
      assert.is_nil(state().selected)
      assert.equals("same.txt", copy("relative"))
      assert.equals(repo .. "/same.txt", copy("absolute"))
    end)

    it("copies no relative path of a file outside the repository", function()
      api.nvim_set_current_win(state().wins.after)
      vim.cmd.edit(outside)
      assert.equals(outside, copy("absolute"))
      assert.equals("dep.txt", copy("name"))
      _G.test_clipboard = nil
      copy("relative")
      assert_refused("not in the repository")
    end)

    it("uses the shown file from another window of the diff tab", function()
      show("app.lua")
      vim.cmd("botright new")
      assert.equals("src/app.lua", copy())
    end)

    it("uses the shown file when the tree is hidden", function()
      show("app.lua")
      twintree.toggle_tree()
      assert.is_nil(session.tree_win(state()))
      assert.equals("src/app.lua", copy())
    end)

    it("uses the line of the cursor in the tree when the panes are closed", function()
      local wins = state().wins
      api.nvim_win_close(wins.before, true)
      api.nvim_win_close(wins.after, true)
      assert.equals("src/app.lua", copy_line("app.lua"))
    end)

    it("uses the line of the cursor of a second tree window", function()
      h.goto_line(tree(), "a.txt")
      vim.cmd.split()
      h.goto_line(api.nvim_get_current_win(), "app.lua")
      assert.equals("src/app.lua", copy())
    end)

    it("uses the diff of a tree buffer that is shown in another tab", function()
      local root = state().before.root
      vim.cmd("tab sbuffer " .. state().tree_buf)
      assert.are_not.equal(tab, api.nvim_get_current_tabpage())
      h.goto_line(api.nvim_get_current_win(), "old.txt")
      assert.equals("gone/old.txt", copy("relative"))
      assert.equals(root .. "/gone/old.txt", copy("absolute"))
    end)
  end)

  describe("with nothing to copy", function()
    it("says so on the line without a file and in a pane without a file", function()
      local clean = h.repo({ ["a.txt"] = "a\n" })
      vim.cmd.cd(clean)
      tab = assert(twintree.open())
      assert.same({ "No changes" }, h.tree_lines(state().tree_buf))
      api.nvim_set_current_win(tree())
      copy()
      assert_refused("no file to copy the path of")

      messages = {}
      api.nvim_set_current_win(state().wins.after)
      copy()
      assert_refused("no file to copy the path of")
    end)

    it("refuses an unknown form", function()
      open()
      copy_line("app.lua", "full")
      assert_refused("unknown form 'full': use relative, absolute or name")
    end)

    it("refuses two arguments", function()
      open()
      copy_line("app.lua", "name absolute")
      assert_refused("unknown form 'name absolute'")
    end)

    it("says that the tab has no diff", function()
      copy()
      assert_refused(session.NO_SESSION)
    end)

    it("says that there is no clipboard and reports nothing as copied", function()
      open()
      local has = vim.fn.has
      vim.fn.has = function(feature)
        return feature == "clipboard" and 0 or has(feature)
      end
      messages = {}
      copy_line("app.lua")
      assert_refused("no clipboard provider")
      assert.equals(1, #messages)
    end)

    it("says that the clipboard could not be written", function()
      open()
      vim.fn.setreg = function()
        error("the clipboard is broken")
      end
      copy_line("app.lua")
      assert_refused("could not write the clipboard")
      assert.truthy(last_message().msg:find("the clipboard is broken", 1, true))
    end)
  end)
end)

describe("the menu of the right mouse button", function()
  local repo, tab, mouse_win
  local mouse_line = 1

  local function state()
    return assert(session.get(tab))
  end

  ---In parentheses: one value, also as the argument of another call.
  local function tree()
    return (assert(session.tree_win(state())))
  end

  ---Names of the normal-mode items of the menu, in the order shown.
  local function items()
    local ok, menus = pcall(vim.fn.menu_get, "PopUp", "n")
    if not ok or not menus[1] then
      return {}
    end
    local sorted = vim.deepcopy(menus[1].submenus or {})
    table.sort(sorted, function(a, b)
      return a.priority < b.priority
    end)
    return vim.tbl_map(function(item)
      return item.name
    end, sorted)
  end

  local function rhs(name)
    for _, item in ipairs(vim.fn.menu_get("PopUp", "n")[1].submenus) do
      if item.name == name then
        return item.mappings.n.rhs
      end
    end
  end

  local OWN = { "Copy relative path", "Copy absolute path", "Copy file name", "-twintree-" }

  local function has_own()
    local names = items()
    for _, name in ipairs(OWN) do
      if vim.list_contains(names, name) then
        return true
      end
    end
    return false
  end

  ---Open the menu as a right click in `win` does; the click is where the
  ---cursor is unless `clicked` names another window.
  local function popup(clicked)
    mouse_win = clicked or api.nvim_get_current_win()
    api.nvim_exec_autocmds("MenuPopup", { group = "twintree", pattern = "n" })
  end

  before_each(function()
    h.reset()
    vim.cmd("silent! aunmenu PopUp")
    vim.cmd([[anoremenu PopUp.Inspect <Cmd>Inspect<CR>]])
    vim.cmd([[nnoremenu PopUp.Mine <Cmd>echo "mine"<CR>]])
    vim.fn.getmousepos = function()
      return { winid = mouse_win, line = mouse_line }
    end
    repo = h.repo({ ["a.txt"] = "a\n", ["src/app.lua"] = "app\n" })
    h.write(repo, "a.txt", "a changed\n")
    h.write(repo, "src/app.lua", "app changed\n")
    vim.cmd.cd(repo)
    vim.cmd.edit(h.tmpdir() .. "/unrelated.txt")
    tab = assert(twintree.open())
  end)

  after_each(function()
    vim.fn.getmousepos = nil
    require("twintree.menu").remove()
  end)

  it("starts with the copy items on a file and on a directory line", function()
    for _, text in ipairs({ "app.lua", "src/" }) do
      h.goto_line(tree(), text)
      popup()
      assert.same(OWN, vim.list_slice(items(), 1, 4))
      assert.equals("<Cmd>TwintreeCopyPath absolute<CR>", rhs("Copy absolute path"))
    end
  end)

  it("copies the path of the line when an item is chosen", function()
    h.goto_line(tree(), "app.lua")
    popup()
    _G.test_clipboard = nil
    vim.cmd([[emenu PopUp.Copy\ relative\ path]])
    assert.equals("src/app.lua", _G.test_clipboard)
  end)

  it("has no copy items outside a tree line", function()
    h.goto_line(tree(), "app.lua")
    popup()
    assert.is_true(has_own())

    api.nvim_set_current_win(state().wins.after)
    popup()
    assert.is_false(has_own())
    assert.same({ "Inspect", "Mine" }, items())

    -- 'mousemodel' "popup": the click is in a pane, the cursor in the tree.
    api.nvim_set_current_win(tree())
    popup(state().wins.after)
    assert.is_false(has_own())

    -- On the separator of the tree window the mouse is on no line.
    mouse_line = 0
    popup()
    assert.is_false(has_own())
    mouse_line = 1
    popup()
    assert.is_true(has_own())

    api.nvim_set_current_tabpage(api.nvim_list_tabpages()[1])
    popup()
    assert.is_false(has_own())
  end)

  it("has no copy items on a line without a file", function()
    local clean = h.repo({ ["a.txt"] = "a\n" })
    vim.cmd.cd(clean)
    tab = assert(twintree.open())
    api.nvim_set_current_win(tree())
    popup()
    assert.is_false(has_own())
  end)

  it("takes the items out when the tree is left", function()
    h.goto_line(tree(), "app.lua")
    popup()
    api.nvim_set_current_win(state().wins.after)
    assert.is_false(has_own())

    h.goto_line(tree(), "app.lua")
    popup()
    vim.cmd.tabclose()
    assert.is_false(has_own())
  end)

  it("takes the items out when the plugin file is sourced again", function()
    h.goto_line(tree(), "app.lua")
    popup()
    vim.cmd.runtime("plugin/twintree.lua")
    assert.is_false(has_own())
    assert.equals(1, #api.nvim_get_autocmds({ group = "twintree", event = "MenuPopup" }))
  end)

  it("leaves the items of the user alone", function()
    vim.cmd([[nnoremenu PopUp.Copy\ file\ name <Cmd>echo "theirs"<CR>]])
    h.goto_line(tree(), "app.lua")
    popup()
    assert.equals('<Cmd>echo "theirs"<CR>', rhs("Copy file name"))
    assert.equals('<Cmd>echo "mine"<CR>', rhs("Mine"))
    assert.truthy(rhs("Copy relative path"))

    api.nvim_set_current_win(state().wins.after)
    assert.same({ "Inspect", "Mine", "Copy file name" }, items())
    assert.equals('<Cmd>echo "theirs"<CR>', rhs("Copy file name"))
  end)

  it("raises nothing when the user removed the menu", function()
    vim.cmd("aunmenu PopUp")
    h.goto_line(tree(), "app.lua")
    popup()
    api.nvim_set_current_win(state().wins.after)
    popup()
    assert.same({}, items())
  end)

  it("leaves the mouse options alone", function()
    local mouse, model = vim.o.mouse, vim.o.mousemodel
    h.goto_line(tree(), "app.lua")
    popup()
    vim.cmd([[emenu PopUp.Copy\ file\ name]])
    assert.same({ mouse, model }, { vim.o.mouse, vim.o.mousemodel })
  end)
end)
