local config = require("twintree.config")
local git = require("twintree.git")
local icons = require("twintree.icons")
local session = require("twintree.session")
local tree = require("twintree.tree")

local M = {}

local ns = vim.api.nvim_create_namespace("twintree")

M.NAME_PREFIX = "twintree://tree/"

local hl_links = {
  TwintreeAdded = "Added",
  TwintreeModified = "Changed",
  TwintreeDeleted = "Removed",
  TwintreeRenamed = "Special",
  TwintreeDirectory = "Directory",
  TwintreeSelected = "Visual",
  TwintreeGuide = "NonText",
  TwintreeOrigin = "Comment",
}

local function define_highlights()
  for group, target in pairs(hl_links) do
    vim.api.nvim_set_hl(0, group, { link = target, default = true })
  end
end

---@return integer buf
function M.create_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  -- Kept when its window closes, so the tree can be hidden and shown again.
  -- `sweep` deletes it when its tab is closed.
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_set_name(buf, M.NAME_PREFIX .. buf)

  -- Callbacks require the module at call time to pick up reloaded code.
  vim.keymap.set("n", "<CR>", function()
    require("twintree.treeview").activate()
  end, { buffer = buf, desc = "Twintree: open file or toggle directory" })
  vim.keymap.set("n", "R", function()
    require("twintree.treeview").refresh()
  end, { buffer = buf, desc = "Twintree: refresh changed files" })
  vim.keymap.set("n", "<2-LeftMouse>", function()
    local mouse = vim.fn.getmousepos()
    -- The mapping also fires for a click on the status line, the separator,
    -- the tab line and the command line; those stay Neovim's.
    if mouse.winid ~= vim.api.nvim_get_current_win() or mouse.line == 0 then
      return "<2-LeftMouse>"
    end
    return "<Cmd>lua require('twintree.treeview').activate()<CR>"
  end, { buffer = buf, expr = true, desc = "Twintree: open file or toggle directory" })
  -- Last: a FileType autocommand of the user can then replace these keys.
  vim.bo[buf].filetype = "twintree"
  return buf
end

---Whether a buffer is a working tree buffer. `:bdelete` leaves the buffer
---valid but unloaded, without its filetype, mappings and entries.
---@param buf integer
---@return boolean
function M.is_tree_buf(buf)
  return vim.api.nvim_buf_is_valid(buf)
    and vim.api.nvim_buf_is_loaded(buf)
    and vim.bo[buf].filetype == "twintree"
end

---@param buf integer
---@return twintree.Entry[]
local function entries_of(buf)
  return vim.b[buf].twintree_entries or {}
end

---Cells available for a line of the tree: the text area of the window that
---shows it, since lines are padded to put the status letters at its edge.
---@param state twintree.Session
---@return integer
function M.text_width(state)
  local win = session.tree_win(state)
  if not win and vim.api.nvim_buf_is_valid(state.tree_buf) then
    -- The user may show the tree in a window of their own.
    win = vim.fn.win_findbuf(state.tree_buf)[1]
  end
  if not win then
    return config.options.tree_width
  end
  local textoff = vim.fn.getwininfo(win)[1].textoff
  return math.max(vim.api.nvim_win_get_width(win) - textoff, 1)
end

---@param state twintree.Session
---@param width? integer
---@return twintree.Line[]
local function lines_of(state, width)
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
  return tree.lines(entries_of(state.tree_buf), {
    collapsed = state.collapsed,
    selected = state.selected,
    dir_status = dir_status,
    width = width or M.text_width(state),
    icon = icons.source(),
  })
end

---Redraw the tree buffer from the session state.
---@param tab? integer
function M.draw(tab)
  local state = session.get(tab)
  if not state or not M.is_tree_buf(state.tree_buf) then
    return
  end
  define_highlights()

  local buf = state.tree_buf
  local width = M.text_width(state)
  local lines = lines_of(state, width)
  vim.b[buf].twintree_width = width
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

---Draw the tree again when the width of its window is not the one it was
---drawn for.
---@param tab? integer
function M.redraw_if_resized(tab)
  local state = session.get(tab)
  if not state or not M.is_tree_buf(state.tree_buf) then
    return
  end
  if vim.b[state.tree_buf].twintree_width ~= M.text_width(state) then
    M.draw(tab)
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

---The changed files of a session in the order of its tree.
---@param tab integer
---@return { entry: twintree.Entry, visible: boolean }[]
function M.files(tab)
  local state = session.get(tab)
  if not state or not vim.api.nvim_buf_is_valid(state.tree_buf) then
    return {}
  end
  return tree.files(entries_of(state.tree_buf), state.collapsed)
end

---The file on the first file line of the tree.
---@param tab integer
---@return twintree.Entry?
function M.first_file(tab)
  for _, file in ipairs(M.files(tab)) do
    if file.visible then
      return file.entry
    end
  end
end

---The line of the tree of `state` at the cursor of the current window.
---@param state twintree.Session
---@return twintree.Line?
function M.cursor_line(state)
  return lines_of(state)[vim.api.nvim_win_get_cursor(0)[1]]
end

---Open the file or toggle the directory under the cursor.
function M.activate()
  local tab = vim.api.nvim_get_current_tabpage()
  local state = session.get(tab)
  if not state then
    return
  end
  local line = M.cursor_line(state)
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
    end
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

  vim.b[state.tree_buf].twintree_entries = entries
  -- The panes keep their files; only the mark depends on the new list.
  state.selected = state.pair and session.entry_path(state, state.pair)
  state.last_entry = state.selected or state.last_entry
  session.save(tab, state)
  M.draw(tab)
end

---The tree buffer of a session, rebuilt when the user deleted it.
---@param tab integer
---@return integer? buf
---@return string? err
function M.ensure_buf(tab)
  local state = session.get(tab)
  if not state then
    return nil, session.NO_SESSION
  end
  if M.is_tree_buf(state.tree_buf) then
    return state.tree_buf
  end
  local entries, err =
    git.changed_files(state.repo, state.before.commit, state.after.commit)
  if not entries then
    return nil, err
  end
  if vim.api.nvim_buf_is_valid(state.tree_buf) then
    -- What `:bdelete` left behind.
    vim.api.nvim_buf_delete(state.tree_buf, { force = true })
  end
  state.tree_buf = M.create_buf()
  session.save(tab, state)
  M.set_entries(tab, entries)
  return state.tree_buf
end

---Put the cursor of a tree window on the selected file.
---@param tab integer
---@param win integer
function M.focus_selected(tab, win)
  local state = session.get(tab)
  -- The window can be closed by an autocommand since the caller found it.
  if not state or not vim.api.nvim_win_is_valid(win) then
    return
  end
  for row, line in ipairs(lines_of(state)) do
    if line.selected then
      vim.api.nvim_win_set_cursor(win, { row, 0 })
      return
    end
  end
end

---Delete tree buffers whose diff tab is gone.
function M.sweep()
  local live = {}
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local state = session.get(tab)
    if state then
      live[state.tree_buf] = true
    end
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    -- By name: a tree buffer unloaded with `:bdelete` has no filetype.
    if
      not live[buf]
      and vim.api.nvim_buf_is_valid(buf)
      and vim.startswith(vim.api.nvim_buf_get_name(buf), M.NAME_PREFIX)
    then
      -- Not nvim_buf_delete(): an error of a user's BufWipeout autocommand
      -- escapes its pcall and reaches the `:tabclose` of the user.
      pcall(vim.cmd.bwipeout, { buf, bang = true })
    end
  end
end

return M
