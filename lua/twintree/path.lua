local session = require("twintree.session")

local M = {}

M.FORMS = { "relative", "absolute", "name" }
M.NO_FILE = "no file to copy the path of"
M.NO_RELATIVE = "the file is not in the repository, it has no relative path"

---@class twintree.PathTarget
---@field relative? string path from the repository root; nil outside it
---@field absolute string

---The session whose tree is `buf`, in whatever tab `buf` is shown.
---@param buf integer
---@return twintree.Session?
local function tree_owner(buf)
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local state = session.get(tab)
    if state and state.tree_buf == buf then
      return state
    end
  end
end

---@param state twintree.Session
---@param line? twintree.Line
---@return twintree.PathTarget?
local function line_target(state, line)
  if not line then
    return nil
  end
  if line.type == "file" then
    local entry = line.entry
    local before =
      vim.fs.joinpath(state.before.root, entry.old_path or entry.path)
    return {
      relative = entry.path,
      absolute = session.entry_pair(state, entry).after or before,
    }
  elseif line.type == "dir" then
    local after = vim.fs.joinpath(state.after.root, line.path)
    local there = vim.fn.isdirectory(after) == 1
    return {
      relative = line.path,
      absolute = there and after or vim.fs.joinpath(state.before.root, line.path),
    }
  end
end

---What a path is copied of: the line of the cursor in a tree, otherwise the
---file the panes of the current tab show.
---@return twintree.PathTarget? target
---@return string? err
function M.target()
  local owner = tree_owner(vim.api.nvim_get_current_buf())
  if owner then
    local line = require("twintree.treeview").cursor_line(owner)
    local target = line_target(owner, line)
    if not target then
      return nil, M.NO_FILE
    end
    return target
  end

  local state = session.get()
  if not state then
    return nil, session.NO_SESSION
  end
  local file = state.pair and (state.pair.after or state.pair.before)
  if not file then
    return nil, M.NO_FILE
  end
  local relative = state.selected
  if not relative then
    -- A file the tree does not list, such as an unchanged one.
    relative = select(2, session.side_of(state, file))
  end
  return { relative = relative, absolute = file }
end

---Whether the cursor is on a file or directory line of a tree.
---@return boolean
function M.on_tree_line()
  local owner = tree_owner(vim.api.nvim_get_current_buf())
  if not owner then
    return false
  end
  local line = require("twintree.treeview").cursor_line(owner)
  return line_target(owner, line) ~= nil
end

---@param target twintree.PathTarget
---@param form "relative"|"absolute"|"name"
---@return string? text
---@return string? err
function M.text(target, form)
  if form == "absolute" then
    return target.absolute
  elseif form == "name" then
    return vim.fs.basename(target.relative or target.absolute)
  elseif not target.relative then
    return nil, M.NO_RELATIVE
  end
  return target.relative
end

return M
