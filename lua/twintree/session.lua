local config = require("twintree.config")

local M = {}

---@class twintree.Side
---@field root string directory holding this version of the repository
---@field commit? string nil for the working tree

---State is plain data in a tab variable so that it survives a module reload.
---@class twintree.Session
---@field repo string repository toplevel
---@field before twintree.Side
---@field after twintree.Side
---@field wins { tree: integer, before: integer, after: integer }
---@field tree_buf integer
---@field selected? string path of the selected file
---@field bufs? { before: integer, after: integer } buffers of the selected file
---@field collapsed table<string, boolean>
---@field layout twintree.Layout

---What the window sizes of the tab are meant to be.
---@class twintree.Layout
---@field ratio number before width divided by before plus after width
---@field tree_width integer width the tree returns to
---@field columns integer terminal width at the last synchronization
---@field tree_shown boolean whether the tree was visible at that time
---@field zoomed boolean whether a window was maximized at that time

local PANES = { "before", "after" }

M.NO_SESSION = "no diff session in this tab"
M.BROKEN_LAYOUT = "a pane of this diff is missing; run :TwintreeResetLayout"

---@return twintree.Layout
function M.default_layout()
  return {
    ratio = 0.5,
    tree_width = config.options.tree_width,
    columns = vim.o.columns,
    tree_shown = true,
    zoomed = false,
  }
end

---@param tab? integer
---@return twintree.Session?
function M.get(tab)
  tab = tab or vim.api.nvim_get_current_tabpage()
  if not vim.api.nvim_tabpage_is_valid(tab) then
    return nil
  end
  local state = vim.t[tab].twintree
  if type(state) ~= "table" then
    return nil
  end
  state.collapsed = state.collapsed or {}
  -- Sessions opened by an older version of the plugin have no layout.
  state.layout = state.layout or M.default_layout()
  return state
end

---@param tab integer
---@param state twintree.Session
function M.save(tab, state)
  vim.t[tab].twintree = state
end

---@param state twintree.Session
---@return boolean
function M.has_panes(state)
  for _, pane in ipairs(PANES) do
    local win = state.wins[pane]
    if not win or not vim.api.nvim_win_is_valid(win) then
      return false
    end
  end
  return true
end

---The window of the tree, or nil when the tree is hidden. The user may
---have closed the window or put another buffer into it.
---@param state twintree.Session
---@return integer?
function M.tree_win(state)
  local win = state.wins.tree
  if
    win
    and vim.api.nvim_win_is_valid(win)
    and vim.api.nvim_win_get_buf(win) == state.tree_buf
  then
    return win
  end
  return nil
end

---Windows of a tab that take part in its layout.
---@param tab integer
---@return integer[]
function M.layout_wins(tab)
  return vim.tbl_filter(function(win)
    return vim.api.nvim_win_get_config(win).relative == ""
  end, vim.api.nvim_tabpage_list_wins(tab))
end

---Open the tree at the far left of the current tab, whatever else is there.
---@param tree_buf integer
---@return integer win
function M.open_tree_window(tree_buf)
  local win = vim.api.nvim_open_win(tree_buf, true, { split = "left", win = -1 })
  M.setup_tree_window(win)
  return win
end

---@param win integer
function M.setup_tree_window(win)
  local wo = vim.wo[win][0]
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = "no"
  wo.foldcolumn = "0"
  wo.wrap = false
  wo.cursorline = true
  vim.wo[win].winfixwidth = true
end

---Create the two pane windows to the right of the tree and size all three.
---@param tree_win integer
---@return integer before_win
---@return integer after_win
function M.open_panes(tree_win)
  local empty = M.placeholder()
  local before_win = vim.api.nvim_open_win(empty, false, {
    split = "right",
    win = tree_win,
  })
  local after_win = vim.api.nvim_open_win(empty, false, {
    split = "right",
    win = before_win,
  })
  vim.api.nvim_win_set_width(tree_win, config.options.tree_width)
  vim.api.nvim_win_call(tree_win, function()
    vim.cmd.wincmd("=")
  end)
  return before_win, after_win
end

---Empty buffer shown where a file does not exist on one side.
---@return integer
function M.placeholder()
  local buf = vim.g.twintree_placeholder
  if buf and vim.api.nvim_buf_is_valid(buf) then
    return buf
  end
  buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_set_name(buf, "twintree://empty")
  vim.g.twintree_placeholder = buf
  return buf
end

local function is_blank_tab()
  if #vim.api.nvim_list_tabpages() > 1 then
    return false
  end
  if #vim.api.nvim_tabpage_list_wins(0) > 1 then
    return false
  end
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  return vim.api.nvim_buf_get_name(buf) == ""
    and vim.bo[buf].buftype == ""
    and not vim.bo[buf].modified
    and #lines == 1
    and lines[1] == ""
end

---Create the three-column layout and register the session in its tab.
---@param repo string
---@param before twintree.Side
---@param after twintree.Side
---@param tree_buf integer
---@return integer tab
function M.create(repo, before, after, tree_buf)
  if not is_blank_tab() then
    vim.cmd.tabnew()
  end
  local tab = vim.api.nvim_get_current_tabpage()
  local tree_win = vim.api.nvim_get_current_win()
  vim.bo[vim.api.nvim_get_current_buf()].bufhidden = "wipe"
  vim.api.nvim_win_set_buf(tree_win, tree_buf)

  M.setup_tree_window(tree_win)
  local before_win, after_win = M.open_panes(tree_win)

  M.save(tab, {
    repo = repo,
    before = before,
    after = after,
    wins = { tree = tree_win, before = before_win, after = after_win },
    tree_buf = tree_buf,
    collapsed = {},
    layout = M.default_layout(),
  })
  -- Required here, not at the top: the layout module requires this one.
  require("twintree.layout").sync(tab)
  return tab
end

local function set_diff(win, enable)
  if vim.wo[win].diff == enable then
    return
  end
  vim.api.nvim_win_call(win, function()
    vim.cmd(enable and "diffthis" or "diffoff")
    if enable then
      -- Diff mode folds unchanged lines; both sides must stay fully readable.
      vim.wo.foldenable = false
    end
  end)
end

local function file_buf(root, path)
  local full = vim.fs.joinpath(root, path)
  local stat = vim.uv.fs_stat(full)
  -- A file can be replaced by a directory of the same name, and vice versa.
  if not stat or stat.type ~= "file" then
    return M.placeholder()
  end
  local buf = vim.fn.bufadd(full)
  vim.bo[buf].buflisted = true
  return buf
end

---Show a changed file in both panes, diffed against each other.
---@param tab integer
---@param entry twintree.Entry
---@return boolean ok
---@return string? err
function M.show(tab, entry)
  local state = M.get(tab)
  if not state then
    return false, M.NO_SESSION
  end
  if not M.has_panes(state) then
    return false, M.BROKEN_LAYOUT
  end

  state.selected = entry.path
  state.bufs = {
    before = file_buf(state.before.root, entry.old_path or entry.path),
    after = file_buf(state.after.root, entry.path),
  }
  M.save(tab, state)

  for _, pane in ipairs(PANES) do
    local win = state.wins[pane]
    set_diff(win, false)
    vim.api.nvim_win_set_buf(win, state.bufs[pane])
  end
  for _, pane in ipairs(PANES) do
    set_diff(state.wins[pane], true)
  end
  vim.api.nvim_set_current_win(state.wins.after)
  return true
end

---Forget the selected file and leave diff mode in both panes.
---@param tab integer
function M.clear_selection(tab)
  local state = M.get(tab)
  if not state then
    return
  end
  state.selected = nil
  state.bufs = nil
  M.save(tab, state)
  for _, pane in ipairs(PANES) do
    if vim.api.nvim_win_is_valid(state.wins[pane]) then
      set_diff(state.wins[pane], false)
    end
  end
end

---Keep diff mode on only while a pane shows its selected file, so that
---navigating elsewhere (go-to-definition) gives a plain window.
function M.sync_diff()
  local win = vim.api.nvim_get_current_win()
  local state = M.get(vim.api.nvim_win_get_tabpage(win))
  if not state then
    return
  end
  for _, pane in ipairs(PANES) do
    if state.wins[pane] == win then
      local selected = state.bufs and state.bufs[pane]
      set_diff(win, selected == vim.api.nvim_win_get_buf(win))
      return
    end
  end
end

---Worktree roots used by open sessions.
---@return string[]
function M.roots_in_use()
  local roots = {}
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local state = M.get(tab)
    if state then
      for _, pane in ipairs(PANES) do
        if state[pane].commit then
          table.insert(roots, state[pane].root)
        end
      end
    end
  end
  return roots
end

return M
