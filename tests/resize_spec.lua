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

  before_each(function()
    local long = {}
    for i = 1, 200 do
      long[i] = "line " .. i
    end
    local text = table.concat(long, "\n") .. "\n"
    repo = h.repo({ ["a.txt"] = "one\n", ["long.txt"] = text })
    h.write(repo, "a.txt", "two\n")
    h.write(repo, "long.txt", ("added\n"):rep(10) .. text)
    local socket = vim.fn.tempname()

    local ok, id = pcall(vim.fn.jobstart, {
      vim.v.progpath,
      "-u",
      root .. "/tests/minimal_init.lua",
      "--listen",
      socket,
    }, {
      pty = true,
      width = 160,
      height = 40,
      cwd = repo,
      env = { TERM = "xterm-256color" },
    })
    if not ok or id <= 0 then
      job = nil
      return
    end
    job = id
    assert(vim.wait(5000, function()
      return vim.uv.fs_stat(socket) ~= nil
    end, 50), "child Neovim did not start")
    chan = vim.fn.sockconnect("pipe", socket, { rpc = true })
    -- The socket accepts requests before the init file has been read.
    assert(vim.wait(5000, function()
      local ready, entered = pcall(lua, "return vim.v.vim_did_enter")
      return ready and entered == 1
    end, 50), "child Neovim did not finish starting")

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
end)
