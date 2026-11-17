-- Starts a second, headless Neovim: what happens between the commands of
-- the command line and VimEnter cannot be reached from a running one.

local h = require("tests.helpers")

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

describe("a diff opened from the command line", function()
  ---Run `nvim +Twintree` in `repo` and return what the tab looks like once
  ---startup is over.
  local function start(repo)
    local out = vim.fn.tempname()
    local setup = ("lua require('twintree').setup({ cache_dir = '%s' })"):format(h.tmpdir())
    -- Scheduled, so that it runs after every VimEnter autocommand.
    local report = ([[lua vim.api.nvim_create_autocmd("VimEnter", { callback = function()
      vim.schedule(function()
        local session = require("twintree.session")
        local state = session.get()
        local wins = {}
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
          local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
          table.insert(wins, vim.startswith(name, "twintree://tree/") and "tree" or vim.fs.basename(name))
        end
        local current = vim.api.nvim_get_current_win()
        vim.fn.writefile({ vim.json.encode({
          tabs = #vim.api.nvim_list_tabpages(),
          wins = wins,
          in_tree = current == session.tree_win(state),
          in_after = current == state.wins.after,
          fixed = vim.wo[state.wins.tree].winfixbuf,
        }) }, "%s")
        vim.cmd("qa!")
      end)
    end })]]):format(out):gsub("\n%s*", " ")
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

  it("has three windows and the cursor in the tree when nothing changed", function()
    local tab = start(h.repo({ ["a.txt"] = "a\n" }))
    assert.same({ "tree", "empty", "empty" }, tab.wins)
    assert.equals(1, tab.tabs)
    assert.is_true(tab.in_tree)
    assert.is_true(tab.fixed)
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
    local tab = start(repo)
    assert.same({ "tree", "a.txt", "a.txt" }, tab.wins)
    assert.is_true(tab.in_after)
    assert.is_true(tab.fixed)
  end)
end)
