local git = require("twintree.git")
local session = require("twintree.session")
local tree = require("twintree.tree")

local M = {}

local ns = vim.api.nvim_create_namespace("twintree")

local hl_links = {
  TwintreeAdded = "Added",
  TwintreeModified = "Changed",
  TwintreeDeleted = "Removed",
  TwintreeRenamed = "Special",
  TwintreeDirectory = "Directory",
  TwintreeSelected = "Visual",
}

local function define_highlights()
  for group, target in pairs(hl_links) do
    vim.api.nvim_set_hl(0, group, { link = target, default = true })
  end
end

---@return integer buf
function M.create_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "twintree"
  vim.api.nvim_buf_set_name(buf, "twintree://tree/" .. buf)

  -- Callbacks require the module at call time to pick up reloaded code.
  vim.keymap.set("n", "<CR>", function()
    require("twintree.treeview").activate()
  end, { buffer = buf, desc = "Twintree: open file or toggle directory" })
  vim.keymap.set("n", "R", function()
    require("twintree.treeview").refresh()
  end, { buffer = buf, desc = "Twintree: refresh changed files" })
  return buf
end

---@param buf integer
---@return twintree.Entry[]
local function entries_of(buf)
  return vim.b[buf].twintree_entries or {}
end

---@param state twintree.Session
---@return twintree.Line[]
local function lines_of(state)
  local function exists(side, path)
    local stat = vim.uv.fs_stat(vim.fs.joinpath(side.root, path))
    return stat ~= nil and stat.type == "directory"
  end
  local function dir_status(path)
    local before, after = exists(state.before, path), exists(state.after, path)
    if after and not before then
      return "A"
    elseif before and not after then
      return "D"
    end
  end
  return tree.lines(
    entries_of(state.tree_buf),
    state.collapsed,
    state.selected,
    dir_status
  )
end

---Redraw the tree buffer from the session state.
---@param tab? integer
function M.draw(tab)
  local state = session.get(tab)
  if not state or not vim.api.nvim_buf_is_valid(state.tree_buf) then
    return
  end
  define_highlights()

  local buf = state.tree_buf
  local lines = lines_of(state)
  local text = vim.tbl_map(function(line)
    return line.text
  end, lines)

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)
  vim.bo[buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for row, line in ipairs(lines) do
    for _, hl in ipairs(line.highlights) do
      vim.api.nvim_buf_set_extmark(buf, ns, row - 1, hl[1], {
        end_col = hl[2],
        hl_group = hl[3],
      })
    end
    if line.selected then
      vim.api.nvim_buf_set_extmark(buf, ns, row - 1, 0, {
        line_hl_group = "TwintreeSelected",
      })
    end
  end
end

---Store the changed files of a session and draw them.
---@param tab integer
---@param entries twintree.Entry[]
function M.set_entries(tab, entries)
  local state = session.get(tab)
  if not state then
    return
  end
  vim.b[state.tree_buf].twintree_entries = entries
  M.draw(tab)
end

---Open the file or toggle the directory under the cursor.
function M.activate()
  local tab = vim.api.nvim_get_current_tabpage()
  local state = session.get(tab)
  if not state then
    return
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line = lines_of(state)[row]
  if not line then
    return
  end

  if line.type == "dir" then
    state.collapsed[line.path] = not state.collapsed[line.path] or nil
    session.save(tab, state)
    M.draw(tab)
  elseif line.type == "file" then
    local ok, err = session.show(tab, line.entry)
    if not ok then
      vim.notify("twintree: " .. err, vim.log.levels.ERROR)
      return
    end
    M.draw(tab)
  end
end

---Recompute the changed files, keeping folds and the selection.
function M.refresh()
  local tab = vim.api.nvim_get_current_tabpage()
  local state = session.get(tab)
  if not state then
    return
  end
  local entries, err =
    git.changed_files(state.repo, state.before.commit, state.after.commit)
  if not entries then
    vim.notify("twintree: " .. err, vim.log.levels.ERROR)
    return
  end

  local still_listed = false
  for _, entry in ipairs(entries) do
    if entry.path == state.selected then
      still_listed = true
    end
  end
  if state.selected and not still_listed then
    session.clear_selection(tab)
  end
  M.set_entries(tab, entries)
end

return M
