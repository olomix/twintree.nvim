-- Runs a second Neovim in a pseudo-terminal, because the events of a real
-- terminal resize and of real key presses do not occur in a headless run.

local h = require("tests.helpers")

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

local WIDTHS = [[
  local session = require("twintree.session")
  local state = session.get(...)
  local tree = session.tree_win(state)
  return {
    columns = vim.o.columns,
    tree = tree and vim.api.nvim_win_get_width(tree) or vim.NIL,
    before = vim.api.nvim_win_get_width(state.wins.before),
    after = vim.api.nvim_win_get_width(state.wins.after),
  }
]]

local PANES = [[
  local state = require("twintree.session").get(...)
  local function pane(name)
    local win = state.wins[name]
    return {
      file = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)),
      line = vim.api.nvim_win_get_cursor(win)[1],
      text = vim.api.nvim_win_call(win, vim.api.nvim_get_current_line),
      diff = vim.wo[win].diff,
      current = vim.api.nvim_get_current_win() == win,
    }
  end
  return { before = pane("before"), after = pane("after"), root = state.before.root }
]]

describe("in a real terminal", function()
  local job, chan, tab, repo

  local function lua(code, ...)
    return vim.rpcrequest(chan, "nvim_exec_lua", code, { ... })
  end

  local function widths()
    return lua(WIDTHS, tab)
  end

  ---Wait until the child's layout satisfies `check`.
  local function settle(check, what)
    local last
    local ok = vim.wait(5000, function()
      last = widths()
      return check(last)
    end, 50)
    assert(ok, ("%s; last layout: %s"):format(what, vim.inspect(last)))
    return last
  end

  local function equal_panes(w)
    return math.abs(w.before - w.after) <= 1
  end

  ---Wait until the panes satisfy `check` and return them.
  local function settle_panes(check)
    local last
    local ok = vim.wait(5000, function()
      last = lua(PANES, tab)
      return check(last)
    end, 50)
    assert(ok, "panes: " .. vim.inspect(last))
    return last
  end

  local function resize(columns)
    vim.fn.jobresize(job, columns, 40)
  end

  local function press(keys)
    vim.rpcrequest(chan, "nvim_input", keys)
  end

  local function focus(pane)
    lua(
      [[
        local state = require("twintree.session").get(select(1, ...))
        vim.api.nvim_set_current_win(state.wins[select(2, ...)])
      ]],
      tab,
      pane
    )
  end

  local socket

  ---Start the child Neovim with extra command line arguments.
  local function launch(args)
    socket = vim.fn.tempname()
    local cmd = { vim.v.progpath, "-u", root .. "/tests/minimal_init.lua", "--listen", socket }
    vim.list_extend(cmd, args or {})
    local ok, id = pcall(vim.fn.jobstart, cmd, {
      pty = true,
      width = 160,
      height = 40,
      cwd = repo,
      env = { TERM = "xterm-256color" },
    })
    job = ok and id > 0 and id or nil
    if job then
      assert(vim.wait(5000, function()
        return vim.uv.fs_stat(socket) ~= nil
      end, 50), "child Neovim did not start")
    end
    return job ~= nil
  end

  local function connect()
    chan = vim.fn.sockconnect("pipe", socket, { rpc = true })
    -- The socket accepts requests before the init file has been read.
    assert(vim.wait(5000, function()
      local ready, entered = pcall(lua, "return vim.v.vim_did_enter")
      return ready and entered == 1
    end, 50), "child Neovim did not finish starting")
  end

  local function stop()
    if chan then
      pcall(vim.fn.chanclose, chan)
      chan = nil
    end
    if job then
      vim.fn.jobstop(job)
      job = nil
    end
  end

  before_each(function()
    local long = {}
    for i = 1, 200 do
      long[i] = "line " .. i
    end
    local text = table.concat(long, "\n") .. "\n"
    -- 0.txt is the file shown when the diff opens; the others are not
    -- loaded until a spec selects them.
    repo = h.repo({ ["0.txt"] = "zero\n", ["a.txt"] = "one\n", ["long.txt"] = text })
    h.write(repo, "0.txt", "ZERO\n")
    h.write(repo, "a.txt", "two\n")
    h.write(repo, "long.txt", ("added\n"):rep(10) .. text)
    if not launch() then
      return
    end
    connect()

    tab = lua(
      [[
        require("twintree").setup({ cache_dir = ... })
        return assert(require("twintree").open())
      ]],
      h.tmpdir()
    )
    settle(function(w)
      return w.columns == 160 and w.tree == 35 and equal_panes(w)
    end, "layout after opening")
  end)

  after_each(stop)

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

  pty_it("keeps equal panes when the terminal grows and shrinks", function()
    resize(220)
    settle(function(w)
      return w.columns == 220 and w.tree == 35 and equal_panes(w)
    end, "after growing to 220")

    resize(100)
    settle(function(w)
      return w.columns == 100 and w.tree == 35 and equal_panes(w)
    end, "after shrinking to 100")

    resize(160)
    settle(function(w)
      return w.columns == 160 and w.tree == 35 and equal_panes(w)
    end, "after returning to 160")
  end)

  pty_it("recovers from a terminal too narrow for the layout", function()
    for _, narrow in ipairs({ 30, 40 }) do
      resize(narrow)
      assert(vim.wait(5000, function()
        return lua("return vim.o.columns") == narrow
      end, 50), "child did not see the resize")
      -- Let the size events that follow the resize be handled.
      vim.wait(300)

      resize(200)
      settle(function(w)
        return w.columns == 200 and w.tree == 35 and equal_panes(w)
      end, ("after returning from %d columns"):format(narrow))
    end
  end)

  pty_it("redraws the tree for the width of its window", function()
    local function tree_lines()
      return lua(
        [[
          local session = require("twintree.session")
          local state = session.get(...)
          local win = session.tree_win(state)
          return {
            width = vim.api.nvim_win_get_width(win),
            lines = vim.api.nvim_buf_get_lines(state.tree_buf, 0, -1, false),
          }
        ]],
        tab
      )
    end
    ---Every line ends with its status letter at the edge of the window.
    local function fits(width)
      local last
      local ok = vim.wait(5000, function()
        last = tree_lines()
        if last.width ~= width then
          return false
        end
        for _, line in ipairs(last.lines) do
          if vim.fn.strdisplaywidth(line) ~= width or not line:match(" [AMDR]$") then
            return false
          end
        end
        return #last.lines > 0
      end, 50)
      assert(ok, ("tree at width %d: %s"):format(width, vim.inspect(last)))
    end

    fits(35)
    focus("tree")
    press(":vertical resize 50<CR>")
    fits(50)
    press(":vertical resize 16<CR>")
    fits(16)
  end)

  pty_it("redraws the tree when line numbers take part of its window", function()
    focus("tree")
    press(":setlocal number numberwidth=6<CR>")
    local last
    local ok = vim.wait(5000, function()
      last = lua(
        [[
          local session = require("twintree.session")
          local state = session.get(...)
          local win = session.tree_win(state)
          return {
            room = vim.api.nvim_win_get_width(win) - vim.fn.getwininfo(win)[1].textoff,
            lines = vim.api.nvim_buf_get_lines(state.tree_buf, 0, -1, false),
          }
        ]],
        tab
      )
      if last.room ~= 35 - 6 then
        return false
      end
      for _, line in ipairs(last.lines) do
        if vim.fn.strdisplaywidth(line) ~= last.room or not line:match(" [AMDR]$") then
          return false
        end
      end
      return #last.lines > 0
    end, 50)
    assert(ok, vim.inspect(last))
  end)

  pty_it("keeps a hand-set ratio across a resize", function()
    focus("before")
    press(":vertical resize 30<CR>")
    local set = settle(function(w)
      return w.before == 30
    end, "after resizing the before pane by hand")
    local ratio = set.before / (set.before + set.after)

    resize(220)
    settle(function(w)
      local now = w.before / (w.before + w.after)
      return w.columns == 220 and w.tree == 35 and math.abs(now - ratio) < 0.02
    end, "after growing with a hand-set ratio")
  end)

  pty_it("applies a resize that happened while another tab was current", function()
    press(":tabnew<CR>")
    resize(220)
    assert(vim.wait(5000, function()
      return lua("return vim.o.columns") == 220
    end, 50), "child did not see the resize")
    press(":tabprevious<CR>")

    settle(function(w)
      return w.tree == 35 and equal_panes(w) and w.before > 80
    end, "after returning to the diff tab")
  end)

  pty_it("returns from a pane zoom with <C-w>| and <C-w>=", function()
    focus("after")
    press("<C-w>|")
    settle(function(w)
      return w.tree == 1 and w.before == 1
    end, "while the after pane is maximized")

    press("<C-w>=")
    settle(function(w)
      return w.tree == 35 and equal_panes(w)
    end, "after equalizing")
  end)

  pty_it("returns from a tree zoom with <C-w>| and <C-w>=", function()
    focus("tree")
    press("<C-w>|")
    settle(function(w)
      return w.before == 1 and w.after == 1
    end, "while the tree is maximized")

    press("<C-w>=")
    settle(function(w)
      return w.tree == 35 and equal_panes(w)
    end, "after equalizing")
  end)

  pty_it("keeps the tree width set by hand after a zoom", function()
    focus("tree")
    press(":vertical resize 50<CR>")
    settle(function(w)
      return w.tree == 50
    end, "after widening the tree")

    focus("before")
    press("<C-w>|")
    settle(function(w)
      return w.tree == 1
    end, "while the before pane is maximized")
    press("<C-w>=")
    settle(function(w)
      return w.tree == 50 and equal_panes(w)
    end, "after equalizing")
  end)

  pty_it("keeps the pane ratio when the tree is closed with <C-w>c", function()
    focus("before")
    press(":vertical resize 30<CR>")
    local set = settle(function(w)
      return w.before == 30
    end, "after resizing the before pane by hand")
    local ratio = set.before / (set.before + set.after)

    focus("tree")
    press("<C-w>c")
    settle(function(w)
      local now = w.before / (w.before + w.after)
      return w.tree == vim.NIL and math.abs(now - ratio) < 0.02
    end, "after closing the tree")
  end)

  pty_it("puts a quickfix entry opened from the other pane into the pane of its side", function()
    local root = lua(PANES, tab).root
    -- A quickfix jump avoids windows that show the empty placeholder.
    lua([[require("twintree.session").show(..., { path = "a.txt" })]], tab)
    lua("vim.fn.setqflist({ { filename = ..., lnum = 120, col = 1 } })", root .. "/long.txt")
    focus("after")
    press(":copen<CR>")
    -- Record every redraw in which the after pane shows a before side
    -- file: the file must be moved before the screen is drawn.
    lua(
      [[
        local tab, root = ...
        local after = require("twintree.session").get(tab).wins.after
        vim.g.drawn_in_wrong_pane = 0
        local ns = vim.api.nvim_create_namespace("twintree_test")
        vim.api.nvim_set_decoration_provider(ns, {
          on_win = function(_, win, buf)
            local name = vim.api.nvim_buf_get_name(buf)
            if win == after and vim.startswith(name, root .. "/") then
              vim.g.drawn_in_wrong_pane = vim.g.drawn_in_wrong_pane + 1
            end
          end,
        })
      ]],
      tab,
      root
    )
    press("<CR>")

    local last
    local ok = vim.wait(5000, function()
      last = lua(PANES, tab)
      return last.before.file == root .. "/long.txt"
        and last.before.current
        and last.before.line == 120
        -- Ten lines were added above it on the after side.
        and last.after.line == 130
    end, 50)
    assert(ok, "panes after the jump: " .. vim.inspect(last))
    assert.equals(repo .. "/long.txt", last.after.file)
    assert.equals("line 120", last.after.text)
    assert.is_true(last.before.diff)
    assert.is_true(last.after.diff)
    assert.equals(0, lua("return vim.g.drawn_in_wrong_pane"))
  end)

  describe("with a swap file left by a killed Neovim", function()
    local owner

    ---Leave a swap file for a.txt and make the child record what it asks.
    local function leave_swap_file()
      local swap_dir = h.tmpdir()
      lua(
        [[
          vim.o.swapfile = true
          vim.o.directory = ... .. "//"
          local swap = require("twintree.swap")
          local ask = swap.ask
          swap.ask = function(text, labels)
            vim.g.asked = text
            return ask(text, labels)
          end
        ]],
        swap_dir
      )
      owner = h.swap_owner(repo .. "/a.txt", swap_dir, true)
    end

    ---The prompt blocks requests, so the answer is typed after a pause.
    ---The messages that follow can leave a "Press ENTER" prompt, which
    ---blocks requests as well; Escape dismisses it and does nothing else.
    local function answer(key)
      vim.wait(1000)
      press(key)
      vim.wait(500)
      press("<Esc>")
    end

    local function after_pane()
      return lua(
        [[
          local state = require("twintree.session").get(...)
          local buf = vim.api.nvim_win_get_buf(state.wins.after)
          return {
            file = vim.api.nvim_buf_get_name(buf),
            readonly = vim.bo[buf].readonly,
            diff = vim.wo[state.wins.after].diff,
            asked = vim.g.asked or "",
            messages = vim.api.nvim_exec2("messages", { output = true }).output,
          }
        ]],
        tab
      )
    end

    after_each(function()
      if owner then
        pcall(vim.fn.jobstop, owner)
        owner = nil
      end
    end)

    pty_it("asks and opens the file read-only on that answer", function()
      leave_swap_file()
      focus("tree")
      press("/a.txt<CR><CR>")
      answer("o")

      local last
      local ok = vim.wait(5000, function()
        last = after_pane()
        return last.file == repo .. "/a.txt" and last.diff
      end, 50)
      assert(ok, vim.inspect(last))
      assert.is_true(last.readonly)
      assert.truthy(last.asked:find("E325: ATTENTION", 1, true))
      assert.truthy(last.asked:find("process ID: no longer running", 1, true))
      assert.is_nil(last.messages:find("stack traceback", 1, true))
    end)

    pty_it("asks and leaves the panes as they were on Abort", function()
      leave_swap_file()
      focus("tree")
      press("/a.txt<CR><CR>")
      answer("a")

      local last
      local ok = vim.wait(5000, function()
        last = after_pane()
        return last.messages:find("a.txt was not opened", 1, true) ~= nil
      end, 50)
      assert(ok, vim.inspect(last))
      assert.equals(repo .. "/0.txt", last.file)
      assert.is_true(last.diff)
      assert.truthy(last.asked:find("E325: ATTENTION", 1, true))
      assert.is_nil(last.messages:find("stack traceback", 1, true))
    end)

    pty_it("asks after a jump in the before pane and shows the counterpart", function()
      focus("tree")
      press("/long.txt<CR><CR>")
      local root = settle_panes(function(p)
        return p.after.file == repo .. "/long.txt"
      end).root
      leave_swap_file()

      focus("before")
      press(":edit " .. root .. "/a.txt<CR>")
      answer("e")

      local last
      local ok = vim.wait(5000, function()
        last = after_pane()
        return last.file == repo .. "/a.txt" and last.diff
      end, 50)
      assert(ok, vim.inspect(last))
      assert.is_false(last.readonly)
      assert.truthy(last.asked:find("E325: ATTENTION", 1, true))
      assert.is_nil(last.messages:find("stack traceback", 1, true))
    end)
  end)

  describe("started with +Twintree", function()
    local owner

    local function setup_arg(cache)
      return ("lua require('twintree').setup({ cache_dir = '%s' })"):format(cache)
    end

    local function tree_state()
      return lua([[
        local session = require("twintree.session")
        local state = session.get()
        return {
          tabs = #vim.api.nvim_list_tabpages(),
          lines = vim.api.nvim_buf_get_lines(state.tree_buf, 0, -1, false),
          in_tree = vim.api.nvim_get_current_win() == session.tree_win(state),
          selected = state.selected or vim.NIL,
          asked = vim.g.asked or "",
          messages = vim.api.nvim_exec2("messages", { output = true }).output,
        }
      ]])
    end

    ---The pseudo-terminal answers no terminal queries, and the warning
    ---about that leaves a "Press ENTER" prompt, which blocks requests.
    local function dismiss_messages()
      vim.wait(1500)
      vim.fn.chansend(job, "\27")
      vim.wait(300)
    end

    after_each(function()
      if owner then
        pcall(vim.fn.jobstop, owner)
        owner = nil
      end
    end)

    pty_it("shows the first file with the cursor in the after pane", function()
      stop()
      assert(launch({ "-c", setup_arg(h.tmpdir()), "-c", "Twintree" }))
      dismiss_messages()
      connect()
      tab = lua("return vim.api.nvim_get_current_tabpage()")

      local panes = settle_panes(function(p)
        return p.after.file == repo .. "/0.txt" and p.after.current
      end)
      assert.equals(panes.root .. "/0.txt", panes.before.file)
      assert.is_true(panes.before.diff)
      assert.is_true(panes.after.diff)
      local tree = tree_state()
      assert.equals(2, tree.tabs)
      assert.equals("0.txt", tree.selected)
      settle(function(w)
        return w.tree == 35 and equal_panes(w)
      end, "layout after starting with +Twintree")
    end)

    pty_it("shows the first change of the first file on screen", function()
      stop()
      local lines = {}
      for i = 1, 200 do
        lines[i] = "line " .. i
      end
      h.write(repo, "0.txt", table.concat(lines, "\n") .. "\n")
      h.commit(repo, "long first file")
      lines[150] = "changed"
      h.write(repo, "0.txt", table.concat(lines, "\n") .. "\n")
      assert(launch({ "-c", setup_arg(h.tmpdir()), "-c", "Twintree" }))
      dismiss_messages()
      connect()
      tab = lua("return vim.api.nvim_get_current_tabpage()")

      local panes = settle_panes(function(p)
        return p.after.file == repo .. "/0.txt" and p.after.current and p.before.line == 150
      end)
      assert.equals(150, panes.after.line)
      assert.equals("changed", panes.after.text)
      assert.equals("line 150", panes.before.text)
      local shown = lua(
        [[
          local state = require("twintree.session").get(...)
          local function lines(win)
            return vim.api.nvim_win_call(win, function()
              return { vim.fn.line("w0"), vim.fn.line("w$") }
            end)
          end
          return { before = lines(state.wins.before), after = lines(state.wins.after) }
        ]],
        tab
      )
      assert.same(shown.after, shown.before)
      assert.is_true(shown.after[1] > 1 and shown.after[1] <= 150)
      assert.is_true(shown.after[2] >= 150)
    end)

    pty_it("moves between the files with its keys and gives them back in another tab", function()
      stop()
      assert(launch({
        "-c",
        "nnoremap ]<C-f> <Cmd>let g:user_hits = get(g:, 'user_hits', 0) + 1<CR>",
        "-c",
        setup_arg(h.tmpdir()),
        "-c",
        "Twintree",
      }))
      dismiss_messages()
      connect()
      tab = lua("return vim.api.nvim_get_current_tabpage()")
      settle_panes(function(p)
        return p.after.file == repo .. "/0.txt" and p.after.current
      end)

      press("]<C-f>")
      settle_panes(function(p)
        return p.after.file == repo .. "/a.txt" and p.after.current and p.after.diff
      end)
      press("2]<C-f>")
      settle_panes(function(p)
        return p.after.file == repo .. "/long.txt"
      end)
      press("[<C-f>")
      local panes = settle_panes(function(p)
        return p.after.file == repo .. "/a.txt"
      end)
      assert.equals(panes.root .. "/a.txt", panes.before.file)
      assert.equals(vim.NIL, lua("return vim.g.user_hits or vim.NIL"))

      -- In a tab without a diff the key is the user's again.
      press(":tabnew<CR>")
      press("]<C-f>")
      assert(vim.wait(5000, function()
        return lua("return vim.g.user_hits or 0") == 1
      end, 50), "the mapping of the user did not run")
      assert.equals(repo .. "/a.txt", lua(PANES, tab).after.file)
      assert.equals("", lua("return vim.fn.maparg('[<C-f>', 'n')"))

      -- And the plugin's when the diff tab is entered again. Not `gt`: the
      -- tab after the new one is the empty tab Neovim started with.
      press("gT")
      press("]<C-f>")
      settle_panes(function(p)
        return p.after.file == repo .. "/long.txt"
      end)
      assert.equals(1, lua("return vim.g.user_hits"))
    end)

    pty_it("shows the first change of the next file when the key is pressed in the tree", function()
      stop()
      local lines = {}
      for i = 1, 200 do
        lines[i] = "line " .. i
      end
      h.write(repo, "a.txt", table.concat(lines, "\n") .. "\n")
      -- The commit takes the changes of the other files with it.
      h.commit(repo, "long second file")
      h.write(repo, "0.txt", "zero again\n")
      lines[150] = "changed"
      h.write(repo, "a.txt", table.concat(lines, "\n") .. "\n")
      assert(launch({ "-c", setup_arg(h.tmpdir()), "-c", "Twintree" }))
      dismiss_messages()
      connect()
      tab = lua("return vim.api.nvim_get_current_tabpage()")
      settle_panes(function(p)
        return p.after.file == repo .. "/0.txt" and p.after.current
      end)

      lua(
        [[
          local session = require("twintree.session")
          vim.api.nvim_set_current_win(session.tree_win(session.get(...)))
        ]],
        tab
      )
      press("]<C-f>")
      local panes = settle_panes(function(p)
        return p.after.file == repo .. "/a.txt" and p.after.line == 150 and p.before.line == 150
      end)
      assert.equals("changed", panes.after.text)
      assert.equals("line 150", panes.before.text)
      assert.is_false(panes.after.current)
      assert.is_false(panes.before.current)
      local tree = tree_state()
      assert.is_true(tree.in_tree)
      assert.equals("a.txt", tree.selected)

      local shown
      assert(vim.wait(5000, function()
        shown = lua(
          [[
            local state = require("twintree.session").get(...)
            local function lines(win)
              return vim.api.nvim_win_call(win, function()
                return { vim.fn.line("w0"), vim.fn.line("w$") }
              end)
            end
            return { before = lines(state.wins.before), after = lines(state.wins.after) }
          ]],
          tab
        )
        return shown.after[1] > 1 and vim.deep_equal(shown.after, shown.before)
      end, 50), "the panes do not show the same lines: " .. vim.inspect(shown))
      assert.is_true(shown.after[1] <= 150 and shown.after[2] >= 150)
    end)

    pty_it("asks about a swap file of the first file and opens without it on Abort", function()
      stop()
      local swap_dir = h.tmpdir()
      owner = h.swap_owner(repo .. "/0.txt", swap_dir, true)
      assert(launch({
        "-c",
        "set swapfile directory=" .. swap_dir .. "//",
        "-c",
        "lua local s = require('twintree.swap'); local ask = s.ask; "
          .. "s.ask = function(t, l) vim.g.asked = t; return ask(t, l) end",
        "-c",
        setup_arg(h.tmpdir()),
        "-c",
        "Twintree",
      }))
      -- The prompt blocks requests, so the answer goes to the terminal.
      vim.wait(1500)
      vim.fn.chansend(job, "a")
      dismiss_messages()
      connect()
      tab = lua("return vim.api.nvim_get_current_tabpage()")

      local last
      local ok = vim.wait(5000, function()
        last = tree_state()
        return last.messages:find("0.txt was not opened", 1, true) ~= nil
      end, 50)
      assert(ok, vim.inspect(last))
      assert.truthy(last.asked:find("E325: ATTENTION", 1, true))
      assert.is_nil(last.messages:find("stack traceback", 1, true))
      assert.equals(vim.NIL, last.selected)
      assert.is_true(last.in_tree)
      assert.equals(3, #last.lines)
      local panes = lua(PANES, tab)
      assert.truthy(vim.endswith(panes.before.file, "twintree://empty"))
      assert.truthy(vim.endswith(panes.after.file, "twintree://empty"))
      assert.is_false(panes.after.diff)
    end)
  end)
end)
