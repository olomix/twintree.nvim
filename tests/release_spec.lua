local h = require("tests.helpers")
local session = require("twintree.session")
local twintree = require("twintree")
local worktree = require("twintree.worktree")

local api = vim.api

local EMPTY = "twintree://empty"

local function find(path)
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_get_name(buf) == path then
      return buf
    end
  end
end

---A buffer of `path` that no window shows.
local function hidden(path)
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  return buf
end

local function stop_clients()
  for _, client in ipairs(vim.lsp.get_clients()) do
    client:stop(true)
  end
  assert(vim.wait(2000, function()
    return #vim.lsp.get_clients() == 0
  end, 10), "an LSP client of an earlier spec still runs")
end

describe("releasing unused worktrees", function()
  local cache, repo, base

  ---Open a diff of the working tree against HEAD, or against `revs`.
  ---@return integer tab
  ---@return string root worktree of the before side
  local function open(revs)
    local tab = assert(twintree.open(revs))
    return tab, session.get(tab).before.root
  end

  local function close(tab)
    api.nvim_set_current_tabpage(tab)
    vim.cmd.tabclose()
  end

  ---Close a tab that has no session.
  local function close_plain_tab()
    vim.cmd.tabnew()
    vim.cmd.tabclose()
  end

  before_each(function()
    stop_clients()
    cache = h.reset()
    vim.fn.setqflist({}, "f")
    repo = h.repo({
      ["a.txt"] = "a\n",
      ["b.txt"] = "b\n",
      ["same.txt"] = "same\n",
      ["gone.txt"] = "gone\n",
    })
    h.write(repo, "a.txt", "a changed\n")
    h.write(repo, "b.txt", "b changed\n")
    vim.fn.delete(repo .. "/gone.txt")
    vim.cmd.cd(repo)
    -- A file of its own for the first tab, to tell its buffer from others.
    vim.cmd.edit(h.tmpdir() .. "/unrelated.txt")
    base = api.nvim_get_current_tabpage()
  end)

  after_each(stop_clients)

  describe("buffers", function()
    it("wipes out the buffers of the worktree when its diff tab is closed", function()
      local tab, root = open()
      local s = session.get(tab)
      assert.equals(root .. "/a.txt", api.nvim_buf_get_name(api.nvim_win_get_buf(s.wins.before)))
      local first = api.nvim_win_get_buf(s.wins.before)
      -- Reached by navigation: an unchanged file opened in the before pane.
      api.nvim_set_current_win(s.wins.before)
      vim.cmd.edit(root .. "/same.txt")
      require("twintree.nav").run("last")
      vim.cmd.bunload(first)
      assert.is_false(api.nvim_buf_is_loaded(first))
      assert.truthy(find(root .. "/same.txt"))

      close(tab)

      for _, buf in ipairs(api.nvim_list_bufs()) do
        assert.is_nil(worktree.root_of(api.nvim_buf_get_name(buf)))
      end
      assert.is_false(api.nvim_buf_is_valid(first))
    end)

    it("fires the buffer events, so that diagnostics go with the buffer", function()
      local tab, root = open()
      local buf = find(root .. "/a.txt")
      local wiped = {}
      api.nvim_create_autocmd("BufWipeout", {
        buffer = buf,
        callback = function(ev)
          table.insert(wiped, ev.buf)
        end,
      })
      vim.diagnostic.set(api.nvim_create_namespace("release_spec"), buf, {
        { lnum = 0, col = 0, message = "old" },
      })
      assert.equals(1, #vim.diagnostic.get())

      close(tab)

      assert.same({ buf }, wiped)
      assert.same({}, vim.diagnostic.get())
    end)

    it("keeps the files of the working directory and the placeholder", function()
      local tab = open()
      require("twintree.nav").run("last")
      local mine = hidden(repo .. "/same.txt")
      local loaded = assert(find(repo .. "/a.txt"))
      local empty = assert(find(EMPTY))

      close(tab)

      for _, buf in ipairs({ mine, loaded }) do
        assert.is_true(api.nvim_buf_is_valid(buf))
      end
      assert.is_true(vim.bo[loaded].buflisted)
      assert.is_true(api.nvim_buf_is_valid(empty))
    end)

    it("keeps a file of the cache directory that is in no worktree", function()
      local tab, root = open()
      h.write(cache, "notes.txt", "x\n")
      h.write(vim.fs.dirname(root), "notes.txt", "x\n")
      local top = hidden(cache .. "/notes.txt")
      local mid = hidden(vim.fs.dirname(root) .. "/notes.txt")

      close(tab)

      assert.is_true(api.nvim_buf_is_valid(top))
      assert.is_true(api.nvim_buf_is_valid(mid))
      assert.is_nil(find(root .. "/a.txt"))
    end)

    it("keeps a buffer that a window of another tab shows, until it is hidden", function()
      local tab, root = open()
      local other = hidden(root .. "/same.txt")
      api.nvim_set_current_tabpage(base)
      local shown = find(root .. "/a.txt")
      api.nvim_win_set_buf(0, shown)

      close(tab)

      assert.equals(shown, api.nvim_win_get_buf(api.nvim_tabpage_get_win(base)))
      assert.is_false(api.nvim_buf_is_valid(other))

      vim.cmd.enew()
      assert.is_true(api.nvim_buf_is_valid(shown))
      close_plain_tab()
      assert.is_false(api.nvim_buf_is_valid(shown))
    end)

    it("keeps a buffer with unsaved changes", function()
      local tab, root = open()
      local buf = hidden(root .. "/same.txt")
      vim.bo[buf].readonly = false
      vim.bo[buf].modifiable = true
      api.nvim_buf_set_lines(buf, 0, -1, false, { "edited" })

      close(tab)

      assert.same({ "edited" }, h.buf_lines(buf))
      assert.is_nil(find(root .. "/a.txt"))
    end)

    it("keeps a buffer that a quickfix or location list refers to", function()
      local tab, root = open()
      local current = hidden(root .. "/a.txt")
      local older = hidden(root .. "/b.txt")
      local located = hidden(root .. "/same.txt")
      local plain = hidden(root .. "/gone.txt")
      vim.fn.setqflist({ { bufnr = older, lnum = 1 } })
      vim.fn.setqflist({ { bufnr = current, lnum = 1 } })
      vim.fn.setloclist(api.nvim_tabpage_get_win(base), { { bufnr = located, lnum = 1 } })

      close(tab)

      for _, buf in ipairs({ current, older, located }) do
        assert.is_true(api.nvim_buf_is_valid(buf))
      end
      assert.is_false(api.nvim_buf_is_valid(plain))
      vim.cmd("cc 1")
      assert.equals(current, api.nvim_get_current_buf())
      api.nvim_set_current_win(api.nvim_tabpage_get_win(base))
      vim.cmd("ll 1")
      assert.equals(located, api.nvim_get_current_buf())
    end)

    it("does not fail on a BufWipeout autocommand that raises", function()
      local tab, root = open()
      local bad = hidden(root .. "/same.txt")
      local good = hidden(root .. "/gone.txt")
      api.nvim_create_autocmd("BufWipeout", {
        buffer = bad,
        callback = function()
          error("a broken autocommand")
        end,
      })

      close(tab)

      assert.is_false(api.nvim_tabpage_is_valid(tab))
      assert.is_false(api.nvim_buf_is_valid(good))
      assert.is_nil(find(root .. "/a.txt"))
    end)

    it("does not fail on a global BufWipeout autocommand that raises", function()
      local tab, root = open()
      local tree = session.get(tab).tree_buf
      local group = api.nvim_create_augroup("release_spec", {})
      api.nvim_create_autocmd("BufWipeout", {
        group = group,
        callback = function()
          error("a broken autocommand")
        end,
      })

      local closed, err = pcall(close, tab)
      api.nvim_del_augroup_by_id(group)

      assert.is_true(closed, err)
      assert.is_false(api.nvim_tabpage_is_valid(tab))
      -- Neovim keeps a buffer whose autocommand failed; the next tab takes it.
      close_plain_tab()
      assert.is_false(api.nvim_buf_is_valid(tree))
      assert.is_nil(find(root .. "/a.txt"))
    end)

    it("keeps the worktree on disk and shows its files again", function()
      local tab, root = open()
      local tree = session.get(tab).tree_buf
      close(tab)
      assert.is_false(api.nvim_buf_is_valid(tree))
      assert.equals(1, vim.fn.isdirectory(root))

      local again, same_root = open()
      assert.equals(root, same_root)
      local win = session.get(again).wins.before
      assert.same({ "a" }, h.buf_lines(api.nvim_win_get_buf(win)))
      assert.is_true(vim.wo[win].diff)
    end)
  end)

  describe("worktrees in use", function()
    it("lists the roots of both panes of every session", function()
      local _, root = open()
      assert.same({ root, repo }, session.pane_roots())
      h.commit(repo, "second")
      local _, older = open({ "HEAD~1", "HEAD" })
      local roots = session.pane_roots()
      assert.equals(4, #roots)
      assert.equals(older, roots[3])
      assert.truthy(worktree.root_of(roots[4]))
    end)

    it("keeps a hidden buffer of a worktree that another diff tab uses", function()
      local first, root = open()
      local second = open()
      local buf = hidden(root .. "/same.txt")

      close(first)

      assert.is_true(api.nvim_buf_is_valid(buf))
      local win = session.get(second).wins.before
      assert.equals(root .. "/a.txt", api.nvim_buf_get_name(api.nvim_win_get_buf(win)))

      close(second)
      assert.is_false(api.nvim_buf_is_valid(buf))
    end)

    it("keeps a hidden buffer of an open diff when another tab is closed", function()
      local _, root = open()
      local buf = hidden(root .. "/same.txt")
      close_plain_tab()
      assert.is_true(api.nvim_buf_is_valid(buf))
    end)

    it("keeps the buffers of a cached worktree that is a working directory", function()
      h.commit(repo, "second")
      local tab, root = open()
      close(tab)
      -- A diff opened from inside the cached worktree of HEAD.
      vim.cmd.cd(root)
      local inside = assert(twintree.open({ "HEAD~1" }))
      assert.equals(root, session.get(inside).after.root)
      local buf = hidden(root .. "/same.txt")

      close_plain_tab()

      assert.is_true(api.nvim_buf_is_valid(buf))
    end)

    it("removes only the buffers of the worktree of the closed tab", function()
      h.commit(repo, "second")
      local first, new_root = open()
      local second, old_root = open({ "HEAD~1" })
      assert.are_not.equal(new_root, old_root)
      local new_buf = hidden(new_root .. "/same.txt")
      local old_buf = hidden(old_root .. "/same.txt")

      close(first)

      assert.is_false(api.nvim_buf_is_valid(new_buf))
      assert.is_true(api.nvim_buf_is_valid(old_buf))
      assert.truthy(session.get(second))
    end)
  end)

  describe("a changed layout", function()
    it("releases the worktree after a pane was closed, replaced or split", function()
      for _, change in ipairs({
        function(win)
          api.nvim_win_close(win, true)
        end,
        function(win)
          api.nvim_win_set_buf(win, api.nvim_create_buf(true, false))
        end,
        function(win)
          api.nvim_set_current_win(win)
          vim.cmd.split()
        end,
      }) do
        local tab, root = open()
        change(session.get(tab).wins.before)

        close(tab)

        assert.is_false(api.nvim_tabpage_is_valid(tab))
        assert.is_nil(find(root .. "/a.txt"))
      end
    end)

    it("keeps the buffer of a pane that was moved to its own tab", function()
      local tab, root = open()
      api.nvim_set_current_win(session.get(tab).wins.before)
      vim.cmd.wincmd("T")
      local moved = api.nvim_get_current_tabpage()
      local other = hidden(root .. "/same.txt")

      close(tab)

      local buf = api.nvim_win_get_buf(api.nvim_tabpage_get_win(moved))
      assert.equals(root .. "/a.txt", api.nvim_buf_get_name(buf))
      assert.is_false(api.nvim_buf_is_valid(other))
    end)

    it("keeps the buffer of a closed pane while the diff stays open", function()
      local tab, root = open()
      api.nvim_win_close(session.get(tab).wins.before, true)
      local buf = assert(find(root .. "/a.txt"))
      assert.same({}, vim.fn.win_findbuf(buf))

      close_plain_tab()

      assert.is_true(api.nvim_buf_is_valid(buf))
    end)
  end)

  describe("language servers", function()
    ---A buffer of `path` attached to `client`, shown by no window.
    local function attached(client, path)
      local buf = hidden(path)
      assert.is_true(vim.lsp.buf_attach_client(buf, client.id))
      return buf
    end

    local function exited(server)
      return vim.wait(2000, function()
        return server.exit == true
      end, 10)
    end

    ---Give a stop that must not happen the time to happen.
    local function still_runs(client, server)
      vim.wait(100)
      return not server.shutdown
        and not server.terminate
        and vim.lsp.get_client_by_id(client.id) ~= nil
    end

    it("has a helper that runs a server inside Neovim", function()
      local client, server = h.lsp({ root_dir = repo })
      local buf = attached(client, repo .. "/same.txt")
      assert.truthy(client.attached_buffers[buf])

      client:stop(false)

      assert.is_true(exited(server))
      assert.is_true(server.shutdown)
      assert.is_nil(server.terminate)
      assert.is_true(h.lsp_gone(client))
    end)

    it("stops the server of the worktree when its diff tab is closed", function()
      local tab, root = open()
      vim.fn.mkdir(root .. "/sub")
      h.write(root, "sub/c.txt", "c\n")
      local at_root, root_server = h.lsp({ root_dir = root })
      local below, below_server = h.lsp({ workspace_folders = { root .. "/sub" } })
      attached(at_root, root .. "/a.txt")
      attached(below, root .. "/sub/c.txt")

      close(tab)

      for _, server in ipairs({ root_server, below_server }) do
        assert.is_true(exited(server))
        assert.is_nil(server.terminate)
      end
      assert.is_true(h.lsp_gone(at_root))
      assert.is_true(h.lsp_gone(below))
    end)

    it("keeps the server of the working directory", function()
      local tab = open()
      local idle, idle_server = h.lsp({ root_dir = repo })
      local busy, busy_server = h.lsp({ root_dir = repo })
      attached(busy, repo .. "/same.txt")

      close(tab)

      assert.is_true(still_runs(idle, idle_server))
      assert.is_true(still_runs(busy, busy_server))
    end)

    it("keeps an idle server of a worktree that another diff tab uses", function()
      local first, root = open()
      open()
      local by_root, root_server = h.lsp({ root_dir = root })
      local by_folder, folder_server = h.lsp({ workspace_folders = { root } })

      close(first)

      assert.is_true(still_runs(by_root, root_server))
      assert.is_true(still_runs(by_folder, folder_server))
    end)

    it("keeps a server that still has a buffer", function()
      local tab, root = open()
      local shown, shown_server = h.lsp({ root_dir = root })
      local changed, changed_server = h.lsp({ root_dir = root })
      local buf = attached(shown, root .. "/a.txt")
      api.nvim_win_set_buf(api.nvim_tabpage_get_win(base), buf)
      local edited = attached(changed, root .. "/same.txt")
      vim.bo[edited].readonly = false
      vim.bo[edited].modifiable = true
      api.nvim_buf_set_lines(edited, 0, -1, false, { "edited" })

      close(tab)

      assert.is_true(still_runs(shown, shown_server))
      assert.is_true(still_runs(changed, changed_server))
    end)

    it("keeps a server that works on more than unused worktrees", function()
      local tab, root = open()
      local shared, shared_server = h.lsp({ workspace_folders = { root, repo } })
      local rootless, rootless_server = h.lsp({})
      assert.is_nil(rootless.root_dir)

      close(tab)

      assert.is_true(still_runs(shared, shared_server))
      assert.is_true(still_runs(rootless, rootless_server))
    end)

    it("keeps a server above the worktrees while one of them is in use", function()
      h.commit(repo, "second")
      local first = open()
      local _, old_root = open({ "HEAD~1" })
      local above, above_server = h.lsp({ root_dir = vim.fs.dirname(old_root) })

      close(first)

      assert.is_true(still_runs(above, above_server))
    end)

    it("stops the server of a worktree that :TwintreeClean removed", function()
      local tab, root = open()
      local client, server = h.lsp({ root_dir = root })
      local buf = attached(client, root .. "/a.txt")
      api.nvim_win_set_buf(api.nvim_tabpage_get_win(base), buf)
      close(tab)
      assert.is_true(still_runs(client, server))
      twintree.clean()
      assert.equals(0, vim.fn.isdirectory(root))

      vim.cmd.enew()
      close_plain_tab()

      assert.is_false(api.nvim_buf_is_valid(buf))
      assert.is_true(exited(server))
      assert.is_true(h.lsp_gone(client))
    end)

    it("does not ask a stopping server again and does not force it", function()
      local tab, root = open()
      -- With a timeout, a stop that is not told otherwise forces the server.
      local client, server =
        h.lsp({ root_dir = root, delay_shutdown = true, exit_timeout = 20 })

      close(tab)
      assert.is_true(vim.wait(2000, function()
        return server.shutdown == true
      end, 10))
      close_plain_tab()
      vim.wait(100)

      assert.is_nil(server.terminate)
      assert.is_nil(server.exit)
      server.answer_shutdown()
      assert.is_true(h.lsp_gone(client))
    end)

    it("stops the other servers when one fails to stop", function()
      local tab, root = open()
      h.lsp({ root_dir = root, fail_shutdown = true })
      local good, good_server = h.lsp({ root_dir = root })
      h.lsp({ root_dir = root, fail_shutdown = true })

      close(tab)

      assert.is_false(api.nvim_tabpage_is_valid(tab))
      assert.is_true(exited(good_server))
      assert.is_true(h.lsp_gone(good))
    end)

    it("closes a tab when no language server runs", function()
      local tab, root = open()
      assert.same({}, vim.lsp.get_clients())
      close(tab)
      assert.is_nil(find(root .. "/a.txt"))
    end)
  end)
end)
