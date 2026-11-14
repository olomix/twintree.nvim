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

  local before = { commit = range.before }
  before.root, err = worktree.ensure(repo, range.before)
  if not before.root then
    return nil, err
  end
  local after = { root = repo, commit = range.after }
  if range.after then
    after.root, err = worktree.ensure(repo, range.after)
    if not after.root then
      return nil, err
    end
  end

  local entries
  entries, err = git.changed_files(repo, range.before, range.after)
  if not entries then
    return nil, err
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

return M
