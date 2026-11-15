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

describe("in a real terminal", function()
  local job, chan, tab

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
    local repo = h.repo({ ["a.txt"] = "one\n" })
    h.write(repo, "a.txt", "two\n")
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
end)
