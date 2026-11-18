-- Starts a second, headless Neovim: what happens between the commands of
-- the command line and VimEnter cannot be reached from a running one.

local h = require("tests.helpers")

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

describe("a diff opened from the command line", function()
  ---Run `nvim +Twintree` in `repo` and return what Neovim looks like once
  ---startup is over. With `ending`, the diff tab is then closed, after its
  ---layout was changed when `ending` is "changed", and `closed` tells what
  ---is left.
  local function start(repo, ending)
    local out = vim.fn.tempname()
    local setup = ("lua require('twintree').setup({ cache_dir = '%s' })"):format(h.tmpdir())
    -- Scheduled, so that it runs after every VimEnter autocommand.
    local report = ([[lua vim.api.nvim_create_autocmd("VimEnter", { callback = function()
      vim.schedule(function()
        local api = vim.api
        local session = require("twintree.session")
        local state = session.get()
        local function tree_bufs()
          return #vim.tbl_filter(function(buf)
            return vim.startswith(api.nvim_buf_get_name(buf), "twintree://tree/")
          end, api.nvim_list_bufs())
        end
        local function first_tab()
          local wins = api.nvim_tabpage_list_wins(api.nvim_list_tabpages()[1])
          local buf = api.nvim_win_get_buf(wins[1])
          return {
            wins = #wins,
            buf = buf,
            name = api.nvim_buf_get_name(buf),
            listed = vim.bo[buf].buflisted,
            bufhidden = vim.bo[buf].bufhidden,
          }
        end
        local wins = {}
        for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
          local name = api.nvim_buf_get_name(api.nvim_win_get_buf(win))
          table.insert(wins, vim.startswith(name, "twintree://tree/") and "tree" or vim.fs.basename(name))
        end
        local current = api.nvim_get_current_win()
        local result = {
          tabs = #api.nvim_list_tabpages(),
          tab = api.nvim_tabpage_get_number(0),
          wins = wins,
          in_tree = current == session.tree_win(state),
          in_after = current == state.wins.after,
          fixed = vim.wo[state.wins.tree].winfixbuf,
          first = first_tab(),
        }
        local ending = "%s"
        if ending ~= "" then
          if ending == "changed" then
            api.nvim_win_close(state.wins.before, true)
            vim.cmd("botright new")
          end
          local ok, err = pcall(vim.cmd.tabclose)
          result.closed = {
            ok = ok,
            err = ok and vim.NIL or tostring(err),
            tabs = #api.nvim_list_tabpages(),
            tab = api.nvim_tabpage_get_number(0),
            session = session.get() ~= nil,
            tree_bufs = tree_bufs(),
            first = first_tab(),
          }
        end
        vim.fn.writefile({ vim.json.encode(result) }, "%s")
        vim.cmd("qa!")
      end)
    end })]]):format(ending or "", out):gsub("\n%s*", " ")
    local child = vim
      .system({
        vim.v.progpath,
        "--headless",
        "-u",
        root .. "/tests/minimal_init.lua",
        "-c",
        setup,
        "-c",
        report,
        "-c",
        "Twintree",
      }, { cwd = repo })
      :wait(20000)
    assert.equals(0, child.code, child.stderr)
    return vim.json.decode(table.concat(vim.fn.readfile(out), "\n"))
  end

  ---The tab Neovim started with: one window with its empty buffer.
  local UNTOUCHED = { wins = 1, buf = 1, name = "", listed = true, bufhidden = "" }

  it("has three windows and the cursor in the tree when nothing changed", function()
    local diff = start(h.repo({ ["a.txt"] = "a\n" }))
    assert.same({ "tree", "empty", "empty" }, diff.wins)
    assert.equals(2, diff.tabs)
    assert.equals(2, diff.tab)
    assert.same(UNTOUCHED, diff.first)
    assert.is_true(diff.in_tree)
    assert.is_true(diff.fixed)
  end)

  it("has three windows after a `:windo` with the cursor in the tree", function()
    local h_repo = h.repo({ ["a.txt"] = "a\n" })
    h.reset()
    vim.api.nvim_set_current_dir(h_repo)
    local session = require("twintree.session")
    local state = session.get(assert(require("twintree").open()))
    assert.equals(state.wins.tree, vim.api.nvim_get_current_win())
    -- What `:windo` falls back to on Neovim before 0.13.
    assert.equals(state.wins.after, vim.fn.win_getid(vim.fn.winnr("#")))

    vim.cmd("windo let w:visited = 1")
    assert.equals(3, #vim.api.nvim_tabpage_list_wins(0))
    assert.is_true(vim.wo[state.wins.tree].winfixbuf)
    h.reset()
  end)

  it("has three windows and the cursor in the after pane with a changed file", function()
    local repo = h.repo({ ["a.txt"] = "a\n" })
    h.write(repo, "a.txt", "changed\n")
    local diff = start(repo)
    assert.same({ "tree", "a.txt", "a.txt" }, diff.wins)
    assert.equals(2, diff.tabs)
    assert.equals(2, diff.tab)
    assert.same(UNTOUCHED, diff.first)
    assert.is_true(diff.in_after)
    assert.is_true(diff.fixed)
  end)

  it("ends with `:tabclose` in the tab Neovim started with", function()
    for _, ending in ipairs({ "intact", "changed" }) do
      local repo = h.repo({ ["a.txt"] = "a\n" })
      h.write(repo, "a.txt", "changed\n")
      local closed = start(repo, ending).closed
      assert.same({
        ok = true,
        err = vim.NIL,
        tabs = 1,
        tab = 1,
        session = false,
        tree_bufs = 0,
        first = UNTOUCHED,
      }, closed, ending)
    end
  end)
end)
