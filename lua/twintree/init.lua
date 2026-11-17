local config = require("twintree.config")

local M = {}

---Configure the plugin. Optional; safe to call more than once. A call
---with a value that cannot be used is reported and changes nothing.
---@param opts? twintree.Config
function M.setup(opts)
  local ok, err = config.setup(opts)
  if not ok then
    vim.notify("twintree: " .. err, vim.log.levels.ERROR)
    return
  end
  require("twintree.keys").reconfigure()
end

---Open a diff session for the repository of the current directory.
---
---No revisions: HEAD against the working tree. One: its merge-base with HEAD
---against the working tree. Two: their merge-base against the second.
---
---The first file of the tree is shown in both panes, with the cursor in the
---after pane. When it is not opened, the session is open all the same: the
---tab is returned together with the reason, which the caller should report.
---@param revs? string[]
---@return integer? tab tabpage of the session, nil when it did not open
---@return string? err why it did not open or, with a tab, why the first
---  file is not shown
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
  -- No TabEnter fires for a diff that opens in the tab Neovim started with.
  require("twintree.keys").sync()
  treeview.set_entries(tab, entries)

  local first = treeview.first_file(tab)
  if first then
    local ok, show_err = session.show(tab, first)
    if not ok then
      if not session.get(tab) then
        -- An autocommand closed the tab on the way: nothing was opened.
        return fail(show_err)
      end
      -- The session stays open: the tree is still of use without the file.
      return tab, show_err
    end
    -- Entering a pane in a narrow terminal resizes the windows, which the
    -- next synchronization would read as a zoom made by the user.
    require("twintree.layout").reapply(tab)
  end
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
  treeview.redraw_if_resized(tab)
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

  local GONE = "the diff tab was closed while its layout was reset"
  local function tab_is_current()
    return vim.api.nvim_tabpage_is_valid(tab)
      and vim.api.nvim_get_current_tabpage() == tab
  end

  -- Close windows until one is left: a tab filled with splits has no room
  -- for another one. The list is read again each time, because closing a
  -- window can make an autocommand of the user close others, and closing
  -- the last window of a tab would close the tab.
  for _ = 1, #session.layout_wins(tab) do
    local wins = session.layout_wins(tab)
    if #wins <= 1 then
      break
    end
    close_keeping_buffer(wins[1])
    if not tab_is_current() then
      return nil, GONE
    end
  end

  -- A new window, not the remaining old one: that belongs to the user.
  buf, err = treeview.ensure_buf(tab)
  if not buf then
    return nil, err
  end
  local tree_win
  tree_win, err = open_tree(buf)
  if not tree_win then
    return nil, err
  end
  for _, win in ipairs(session.layout_wins(tab)) do
    if win ~= tree_win then
      close_keeping_buffer(win)
    end
  end
  if not tab_is_current() or not vim.api.nvim_win_is_valid(tree_win) then
    return nil, GONE
  end
  local ok, before_win, after_win = pcall(session.open_panes, tree_win)
  if not ok then
    return nil, "no room for the panes: " .. tostring(before_win)
  end

  local state = session.get(tab)
  if not state then
    return nil, GONE
  end
  local pair = state.pair
  state.wins = { tree = tree_win, before = before_win, after = after_win }
  state.layout = session.default_layout()
  -- The new panes are empty. Recorded as such, so that a pair that cannot
  -- be shown again leaves no pair and no mark in the tree behind.
  state.pair, state.selected, state.bufs = nil, nil, nil
  session.save(tab, state)

  local shown, show_err = false, nil
  if pair then
    shown, show_err = session.show_pair(tab, pair)
    if not tab_is_current() then
      return nil, GONE
    end
    if not shown then
      -- The windows were rebuilt. The file was not opened, or an
      -- autocommand closed a new pane while it was shown.
      vim.notify("twintree: " .. show_err, vim.log.levels.ERROR)
    end
  end
  if shown and vim.api.nvim_win_is_valid(after_win) then
    vim.api.nvim_set_current_win(after_win)
  else
    if not shown then
      session.clear_selection(tab)
    end
    if vim.api.nvim_win_is_valid(tree_win) then
      vim.api.nvim_set_current_win(tree_win)
    end
  end
  treeview.draw(tab)
  treeview.focus_selected(tab, tree_win)
  layout.reapply(tab)
  treeview.redraw_if_resized(tab)
  return true
end

return M
