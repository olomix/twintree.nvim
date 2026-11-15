local config = require("twintree.config")

local M = {}

---Configure the plugin. Optional; safe to call more than once.
---@param opts? twintree.Config
function M.setup(opts)
  config.setup(opts)
end

---Open a diff session for the repository of the current directory.
---
---No revisions: HEAD against the working tree. One: its merge-base with HEAD
---against the working tree. Two: their merge-base against the second.
---@param revs? string[]
---@return integer? tab tabpage of the session
---@return string? err
function M.open(revs)
  local git = require("twintree.git")
  local session = require("twintree.session")
  local treeview = require("twintree.treeview")
  local worktree = require("twintree.worktree")

  local repo, err = git.toplevel(vim.fn.getcwd())
  if not repo then
    return nil, err
  end
  local range
  range, err = git.resolve_range(repo, revs or {})
  if not range then
    return nil, err
  end

  -- A failed open must not leave behind worktrees it created.
  local created = {}
  local function checkout(sha)
    local cached = worktree.is_ready(repo, sha)
    local root, checkout_err = worktree.ensure(repo, sha)
    if root and not cached then
      table.insert(created, root)
    end
    return root, checkout_err
  end
  local function fail(message)
    for _, root in ipairs(created) do
      worktree.remove(repo, root)
    end
    return nil, message
  end

  local before = { commit = range.before }
  before.root, err = checkout(range.before)
  if not before.root then
    return fail(err)
  end
  local after = { root = repo, commit = range.after }
  if range.after then
    after.root, err = checkout(range.after)
    if not after.root then
      return fail(err)
    end
  end

  local entries
  entries, err = git.changed_files(repo, range.before, range.after)
  if not entries then
    return fail(err)
  end

  local tab = session.create(repo, before, after, treeview.create_buf())
  treeview.set_entries(tab, entries)
  return tab
end

---Remove cached worktrees of the current repository that no session uses.
---@return integer? removed
---@return string? err
function M.clean()
  local git = require("twintree.git")
  local repo, err = git.toplevel(vim.fn.getcwd())
  if not repo then
    return nil, err
  end
  local in_use = require("twintree.session").roots_in_use()
  return require("twintree.worktree").clean(repo, in_use)
end

---Close a window without losing its buffer: a buffer set to be removed
---when hidden is kept hidden this once.
---@param win integer
local function close_keeping_buffer(win)
  -- An autocommand of the user may have closed it while we closed others.
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  local policy = vim.bo[buf].bufhidden
  vim.bo[buf].bufhidden = "hide"
  -- Forced, so that a modified buffer is hidden instead of blocking.
  pcall(vim.api.nvim_win_close, win, true)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.bo[buf].bufhidden = policy
  end
end

---Open the tree window, reporting a tab that has no room for it.
---@param buf integer
---@return integer? win
---@return string? err
local function open_tree(buf)
  local session = require("twintree.session")
  local ok, win = pcall(session.open_tree_window, buf)
  if not ok then
    return nil, "no room for the tree window: " .. tostring(win)
  end
  return win
end

---Hide the tree of the current diff tab, or show it again.
---@return boolean? ok
---@return string? err
function M.toggle_tree()
  local layout = require("twintree.layout")
  local session = require("twintree.session")
  local treeview = require("twintree.treeview")

  local tab = vim.api.nvim_get_current_tabpage()
  local state = session.get(tab)
  if not state then
    return nil, session.NO_SESSION
  end

  local win = session.tree_win(state)
  if win then
    if #session.layout_wins(tab) <= 1 then
      -- Closing the last window would close the tab and end the diff.
      return nil, "the tree is the only window here; run :TwintreeResetLayout"
    end
    vim.api.nvim_win_close(win, false)
  else
    local buf, err = treeview.ensure_buf(tab)
    if not buf then
      return nil, err
    end
    win, err = open_tree(buf)
    if not win then
      return nil, err
    end
    state = assert(session.get(tab))
    state.wins.tree = win
    session.save(tab, state)
    treeview.focus_selected(tab, win)
  end
  -- Not `sync`: the sizes Neovim gave the windows here mean nothing.
  layout.reapply(tab)
  return true
end

---Return the current diff tab to its original view: tree, before and after
---window only, tree at the configured width, panes equally wide. Every
---other window of the tab is closed; their buffers are kept.
---@return boolean? ok
---@return string? err
function M.reset_layout()
  local layout = require("twintree.layout")
  local session = require("twintree.session")
  local treeview = require("twintree.treeview")

  local tab = vim.api.nvim_get_current_tabpage()
  if not session.get(tab) then
    return nil, session.NO_SESSION
  end
  local buf, err = treeview.ensure_buf(tab)
  if not buf then
    return nil, err
  end

  -- Close all but one window first: a tab filled with splits has no room
  -- for another one. The last one goes once the tree window exists.
  local old_wins = session.layout_wins(tab)
  local last = table.remove(old_wins)
  for _, win in ipairs(old_wins) do
    close_keeping_buffer(win)
  end
  -- A new window, not the remaining old one: that belongs to the user.
  local tree_win
  tree_win, err = open_tree(buf)
  if not tree_win then
    return nil, err
  end
  close_keeping_buffer(last)
  local ok, before_win, after_win = pcall(session.open_panes, tree_win)
  if not ok then
    return nil, "no room for the panes: " .. tostring(before_win)
  end

  local state = assert(session.get(tab))
  state.wins = { tree = tree_win, before = before_win, after = after_win }
  state.layout = session.default_layout()
  state.bufs = nil
  session.save(tab, state)

  local entry = state.selected and treeview.entry(tab, state.selected)
  if entry then
    session.show(tab, entry)
  else
    session.clear_selection(tab)
    vim.api.nvim_set_current_win(tree_win)
  end
  treeview.draw(tab)
  treeview.focus_selected(tab, tree_win)
  layout.reapply(tab)
  return true
end

return M
