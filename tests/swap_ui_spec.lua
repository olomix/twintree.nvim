local h = require("tests.helpers")
local session = require("twintree.session")
local swap = require("twintree.swap")
local twintree = require("twintree")

local api = vim.api

describe("swap files", function()
  local repo, tab, swap_dir
  local jobs, asked, answer, messages
  local original = {}

  local function state()
    return assert(session.get(tab))
  end

  local function name(win)
    return api.nvim_buf_get_name(api.nvim_win_get_buf(win))
  end

  local function tree()
    local win = session.tree_win(state())
    assert.truthy(win)
    return win
  end

  local function select(text)
    h.goto_line(tree(), text)
    h.keys("<CR>")
  end

  ---A swap file for a file of the checkout: left behind by a killed
  ---Neovim, or held by one that is still running.
  local function swap_file(file, running)
    table.insert(jobs, h.swap_owner(repo .. "/" .. file, swap_dir, not running))
  end

  ---Pretend a user interface is attached; the specs run without one.
  local function with_ui()
    api.nvim_list_uis = function()
      return { {} }
    end
  end

  local function errors()
    return vim.tbl_filter(function(message)
      return message.level == vim.log.levels.ERROR
    end, messages)
  end

  local function assert_pair(file)
    local s = state()
    assert.equals(s.before.root .. "/" .. file, name(s.wins.before))
    assert.equals(repo .. "/" .. file, name(s.wins.after))
    assert.is_true(vim.wo[s.wins.before].diff)
    assert.is_true(vim.wo[s.wins.after].diff)
    assert.equals(file, s.selected)
    return s
  end

  before_each(function()
    h.reset()
    vim.o.columns = 160
    repo = h.repo({ ["a.txt"] = "one\n", ["b.txt"] = "b\n", ["c.txt"] = "c\n" })
    h.write(repo, "a.txt", "two\n")
    h.write(repo, "b.txt", "B\n")
    api.nvim_set_current_dir(repo)

    swap_dir = h.tmpdir()
    vim.o.swapfile = true
    vim.o.directory = swap_dir .. "//"

    jobs, asked, answer, messages = {}, {}, 0, {}
    original.ask, original.notify, original.list_uis = swap.ask, vim.notify, api.nvim_list_uis
    swap.ask = function(text, labels)
      table.insert(asked, { text = text, labels = labels })
      return answer
    end
    vim.notify = function(msg, level)
      table.insert(messages, { msg = msg, level = level })
    end

    tab = assert(twintree.open())
  end)

  after_each(function()
    swap.ask, vim.notify, api.nvim_list_uis = original.ask, original.notify, original.list_uis
    for _, job in ipairs(jobs) do
      pcall(vim.fn.jobstop, job)
    end
    vim.o.swapfile = false
    vim.o.columns = 80
  end)

  describe("swap.open", function()
    it("puts a file and a placeholder into a window", function()
      local win = state().wins.after
      local buf = vim.fn.bufadd(repo .. "/c.txt")
      assert.is_true(swap.open(win, buf))
      assert.equals(buf, api.nvim_win_get_buf(win))
      assert.is_true(api.nvim_buf_is_loaded(buf))

      assert.is_true(swap.open(win, session.placeholder()))
      assert.equals("twintree://empty", name(win))
    end)

    it("keeps the alternate file when asked to", function()
      local win = state().wins.after
      api.nvim_set_current_win(win)
      vim.cmd.edit(repo .. "/a.txt")
      vim.cmd.edit(repo .. "/b.txt")
      assert.is_true(swap.open(win, vim.fn.bufadd(repo .. "/c.txt"), true))
      assert.equals(repo .. "/a.txt", vim.fn.fnamemodify(vim.fn.bufname("#"), ":p"))
    end)

    it("reports a window or buffer that is gone", function()
      local ok, reason = swap.open(state().wins.after, 99999)
      assert.is_false(ok)
      assert.equals("its window or buffer is gone", reason)
      assert.is_false(swap.is_opening())
    end)

    it("is over after a failure", function()
      swap_file("a.txt")
      local ok = swap.open(state().wins.after, vim.fn.bufadd(repo .. "/a.txt"))
      assert.is_false(ok)
      assert.is_false(swap.is_opening())
    end)
  end)

  describe("of a killed Neovim", function()
    before_each(function()
      swap_file("a.txt")
      with_ui()
    end)

    it("are reported by swapinfo() as not running", function()
      local info = vim.fn.swapinfo(vim.fn.glob(swap_dir .. "/*", true, true)[1])
      assert.is_nil(info.error)
      assert.equals(0, info.pid)
    end)

    it("ask with Neovim's facts and choices", function()
      answer = 2
      select("a.txt")
      assert.equals(1, #asked)
      assert.same({
        "&Open Read-Only",
        "&Edit anyway",
        "&Recover",
        "&Delete it",
        "&Quit",
        "&Abort",
      }, asked[1].labels)
      local text = asked[1].text
      assert.truthy(text:find("E325: ATTENTION", 1, true))
      assert.truthy(text:find("process ID: no longer running", 1, true))
      assert.truthy(text:find(('While opening file "%s/a.txt"'):format(repo), 1, true))
      assert.truthy(text:find(swap_dir, 1, true))
      local swapname = vim.fn.glob(swap_dir .. "/*.swp", true, true)[1]
      local swap_date = os.date("%a %b %d %H:%M:%S %Y", vim.uv.fs_stat(swapname).mtime.sec)
      assert.truthy(text:find("owned by: [^\n]* dated: " .. vim.pesc(swap_date)))
    end)

    it("open read-only on Open Read-Only", function()
      answer = 1
      select("a.txt")
      local s = assert_pair("a.txt")
      assert.is_true(vim.bo[s.bufs.after].readonly)
      assert.same({}, errors())
    end)

    it("open editable on Edit anyway", function()
      answer = 2
      select("a.txt")
      local s = assert_pair("a.txt")
      assert.is_false(vim.bo[s.bufs.after].readonly)
      assert.is_true(vim.bo[s.bufs.after].modifiable)
      assert.same({ "two" }, h.buf_lines(s.bufs.after))
    end)

    it("show the recovered text on Recover", function()
      answer = 3
      select("a.txt")
      local s = assert_pair("a.txt")
      assert.same({ "xtwo" }, h.buf_lines(s.bufs.after))
    end)

    it("are deleted on Delete it", function()
      answer = 4
      select("a.txt")
      local s = assert_pair("a.txt")
      assert.is_false(vim.bo[s.bufs.after].readonly)
      assert.same({ "two" }, h.buf_lines(s.bufs.after))
      -- What is left is this instance's own swap file for the buffer.
      for _, file in ipairs(vim.fn.glob(swap_dir .. "/*", true, true)) do
        assert.equals(vim.fn.getpid(), vim.fn.swapinfo(file).pid)
      end
    end)

    for label, choice in pairs({ Quit = 5, Abort = 6, ["a dismissed prompt"] = 0 }) do
      it("leave empty panes on " .. label, function()
        answer = choice
        select("a.txt")

        local s = state()
        assert.equals("twintree://empty", name(s.wins.before))
        assert.equals("twintree://empty", name(s.wins.after))
        assert.is_false(vim.wo[s.wins.before].diff)
        assert.is_false(vim.wo[s.wins.after].diff)
        assert.is_nil(s.selected)
        assert.is_nil(s.pair)
        assert.is_nil(s.bufs)
        assert.same({
          {
            msg = "twintree: a.txt was not opened: the swap file question was declined",
            level = vim.log.levels.ERROR,
          },
        }, errors())
      end)
    end

    it("keep the previous pair when the next file is declined", function()
      select("b.txt")
      local lines = h.tree_lines(state().tree_buf)
      answer = 6
      select("a.txt")

      local s = assert_pair("b.txt")
      assert.equals("b.txt", s.pair.after:match("[^/]+$"))
      assert.same(lines, h.tree_lines(s.tree_buf))
      assert.equals(1, #errors())
      assert.equals(1, #asked)
    end)

    it("ask again when the file is selected again", function()
      answer = 6
      select("a.txt")
      answer = 2
      select("a.txt")
      assert.equals(2, #asked)
      assert_pair("a.txt")
    end)

    it("are left to Neovim for a file the user opens", function()
      api.nvim_set_current_win(state().wins.after)
      -- Without a prompt of its own Neovim raises E325 here.
      pcall(vim.cmd.edit, repo .. "/a.txt")
      assert.equals(0, #asked)
    end)

    it("are not asked about when an earlier handler decided", function()
      local id = api.nvim_create_autocmd("SwapExists", {
        callback = function()
          vim.v.swapchoice = "o"
        end,
      })
      -- Sourced again, the plugin's handler is defined after this one.
      vim.cmd.runtime("plugin/twintree.lua")
      select("a.txt")
      api.nvim_del_autocmd(id)

      assert.equals(0, #asked)
      assert.is_true(vim.bo[assert_pair("a.txt").bufs.after].readonly)
      assert.equals(1, #api.nvim_get_autocmds({ group = "twintree", event = "SwapExists" }))
    end)

    describe("after a jump in a pane", function()
      for label, choice in pairs({ Quit = 5, Abort = 6, ["a dismissed prompt"] = 0 }) do
        it("keep the file the user went to on " .. label, function()
          select("b.txt")
          local s = state()
          answer = choice
          api.nvim_set_current_win(s.wins.before)
          vim.cmd.edit(s.before.root .. "/a.txt")

          s = state()
          assert.equals(s.before.root .. "/a.txt", name(s.wins.before))
          assert.is_false(vim.wo[s.wins.before].diff)
          assert.equals(repo .. "/b.txt", name(s.wins.after))
          assert.equals("b.txt", s.selected)
          assert.equals(repo .. "/b.txt", s.pair.after)
          assert.equals(1, #asked)
          assert.same({
            {
              msg = "twintree: a.txt was not opened: the swap file question was declined",
              level = vim.log.levels.ERROR,
            },
          }, errors())

          vim.cmd.buffer(s.bufs.before)
          assert_pair("b.txt")
          assert.equals(1, #asked)
        end)
      end

      it("ask again when the user comes back to that file", function()
        select("b.txt")
        local s = state()
        answer = 5
        api.nvim_set_current_win(s.wins.before)
        vim.cmd.edit(s.before.root .. "/a.txt")
        vim.cmd.buffer(s.bufs.before)

        answer = 2
        vim.cmd.edit(s.before.root .. "/a.txt")
        assert.equals(2, #asked)
        assert_pair("a.txt")
      end)

      it("ask once when the file landed in the pane of the other side", function()
        select("b.txt")
        local s = state()
        answer = 5
        -- A file of the before side in the after pane: the plugin moves it
        -- to its own pane, from callbacks that one jump queues repeatedly.
        api.nvim_set_current_win(s.wins.after)
        vim.cmd.edit(s.before.root .. "/a.txt")
        vim.wait(100)

        assert.equals(1, #asked)
        assert.equals(1, #errors())
        s = state()
        assert.equals(s.before.root .. "/a.txt", name(s.wins.after))
        assert.equals(s.before.root .. "/b.txt", name(s.wins.before))
        assert.equals("b.txt", s.selected)
      end)

      it("show the counterpart on Edit anyway", function()
        select("b.txt")
        answer = 2
        api.nvim_set_current_win(state().wins.before)
        vim.cmd.edit(state().before.root .. "/a.txt")
        assert_pair("a.txt")
        assert.same({}, errors())
      end)
    end)

    it("are reported when the layout is reset and the file is declined", function()
      api.nvim_buf_delete(vim.fn.bufadd(repo .. "/a.txt"), { force = true })
      answer = 2
      select("a.txt")
      local buf = state().bufs.after
      api.nvim_set_current_win(tree())
      -- Unloaded, so that the reset has to open it again.
      api.nvim_buf_delete(buf, { force = true })
      swap_file("a.txt")
      asked, answer = {}, 6

      local ok, result = pcall(twintree.reset_layout)
      assert.is_true(ok, tostring(result))
      assert.is_true(result)
      local s = state()
      assert.same({ tree(), s.wins.before, s.wins.after }, api.nvim_tabpage_list_wins(tab))
      assert.equals(1, #asked)
      assert.equals(1, #errors())
      assert.truthy(errors()[1].msg:find("a.txt was not opened", 1, true))

      -- Nothing is shown, so nothing is recorded or marked as shown.
      assert.is_nil(s.pair)
      assert.is_nil(s.selected)
      assert.is_nil(s.bufs)
      assert.equals("twintree://empty", name(s.wins.before))
      assert.equals("twintree://empty", name(s.wins.after))
      assert.is_false(vim.wo[s.wins.after].diff)
      assert.equals(tree(), api.nvim_get_current_win())
      local ns = api.nvim_get_namespaces().twintree
      for _, mark in ipairs(api.nvim_buf_get_extmarks(s.tree_buf, ns, 0, -1, { details = true })) do
        assert.is_nil(mark[4].line_hl_group)
      end
      -- A refresh must not bring the mark back either.
      api.nvim_set_current_win(tree())
      h.keys("R")
      assert.is_nil(state().selected)
    end)
  end)

  describe("of a running Neovim", function()
    before_each(function()
      swap_file("a.txt", true)
      with_ui()
    end)

    it("are reported by swapinfo() with the process id", function()
      local info = vim.fn.swapinfo(vim.fn.glob(swap_dir .. "/*", true, true)[1])
      assert.equals(vim.fn.jobpid(jobs[1]), info.pid)
    end)

    it("open the file editable without a question", function()
      select("a.txt")
      local s = assert_pair("a.txt")
      assert.equals(0, #asked)
      assert.is_false(vim.bo[s.bufs.after].readonly)
      assert.same({}, errors())
      local warnings = vim.tbl_filter(function(message)
        return message.msg:find("W325", 1, true) ~= nil
      end, messages)
      assert.equals(1, #warnings)
      assert.equals(vim.log.levels.WARN, warnings[1].level)
    end)

    it("open the counterpart of a jump without a question", function()
      select("b.txt")
      api.nvim_set_current_win(state().wins.before)
      vim.cmd.edit(state().before.root .. "/a.txt")
      assert_pair("a.txt")
      assert.equals(0, #asked)
      assert.same({}, errors())
    end)

    it("are asked about when nothing else decided, without Delete it", function()
      api.nvim_clear_autocmds({ group = "nvim.swapfile" })
      answer = 2
      select("a.txt")
      assert.equals(1, #asked)
      assert.same(
        { "&Open Read-Only", "&Edit anyway", "&Recover", "&Quit", "&Abort" },
        asked[1].labels
      )
      assert.truthy(asked[1].text:find("(STILL RUNNING)", 1, true))
      assert_pair("a.txt")
    end)
  end)

  it("are not involved for a file of a cached worktree", function()
    with_ui()
    local s = state()
    api.nvim_set_current_win(s.wins.before)
    vim.cmd.edit(s.before.root .. "/c.txt")
    assert.equals(0, #asked)
    assert.is_false(vim.bo.swapfile)
    assert.equals(repo .. "/c.txt", name(state().wins.after))
  end)

  it("give no question and no file without a user interface", function()
    swap_file("a.txt")
    select("b.txt")
    select("a.txt")

    assert.equals(0, #asked)
    assert_pair("b.txt")
    assert.equals(1, #errors())
    assert.truthy(errors()[1].msg:find("^twintree: a.txt was not opened: E325"))
  end)
end)
