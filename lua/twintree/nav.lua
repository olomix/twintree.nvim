local session = require("twintree.session")

local M = {}

M.NO_MORE = "no more changed files"
M.NONE = "no changed files"
M.ALL_COLLAPSED = "every changed file is in a collapsed directory"

local INFO, ERROR = vim.log.levels.INFO, vim.log.levels.ERROR

---@alias twintree.NavAction "next"|"prev"|"first"|"last"

---Index of the changed file the panes show, or showed last.
---@param state twintree.Session
---@param files { entry: twintree.Entry, visible: boolean }[]
---@return integer? index nil when no file of the list was shown
local function position(state, files)
  -- `selected` first, but it can name a file that left the list.
  for _, path in ipairs({ state.selected or false, state.last_entry or false }) do
    for index, file in ipairs(files) do
      if file.entry.path == path then
        return index
      end
    end
  end
  return nil
end

---The file an action leads to.
---@param state twintree.Session
---@param files { entry: twintree.Entry, visible: boolean }[]
---@param action twintree.NavAction
---@param count integer
---@return twintree.Entry? entry
---@return string? reason why there is none
local function target(state, files, action, count)
  if #files == 0 then
    return nil, M.NONE
  end
  local visible = {}
  for index, file in ipairs(files) do
    if file.visible then
      table.insert(visible, index)
    end
  end
  if #visible == 0 then
    return nil, M.ALL_COLLAPSED
  end

  if action == "first" then
    return files[visible[1]].entry
  elseif action == "last" then
    return files[visible[#visible]].entry
  end

  local current = position(state, files)
  local candidates = {}
  if action == "next" then
    for _, index in ipairs(visible) do
      if not current or index > current then
        table.insert(candidates, index)
      end
    end
  else
    for i = #visible, 1, -1 do
      if not current or visible[i] < current then
        table.insert(candidates, visible[i])
      end
    end
  end
  if #candidates == 0 then
    return nil, M.NO_MORE
  end
  return files[candidates[math.min(count, #candidates)]].entry
end

---@param action twintree.NavAction
---@param count integer
---@return boolean shown
---@return string? message
---@return integer? level
local function move(action, count)
  local treeview = require("twintree.treeview")
  local tab = vim.api.nvim_get_current_tabpage()
  -- Before the entries are read: the user may have deleted the tree buffer.
  local _, err = treeview.ensure_buf(tab)
  if err then
    return false, err, ERROR
  end
  local state = assert(session.get(tab))

  local entry, reason = target(state, treeview.files(tab), action, count)
  if not entry then
    -- Nothing went wrong: the list has an end.
    return false, reason, INFO
  end
  local ok, show_err = session.show(tab, entry, { keep_focus = true })
  if not ok then
    return false, show_err, ERROR
  end
  return true
end

---Show another changed file of the current diff tab and report why when
---none is shown. The current window stays current.
---@param action twintree.NavAction
---@param count? integer how many files to move for "next" and "prev"
---@return boolean shown
function M.run(action, count)
  local shown, message, level = move(action, math.max(count or 1, 1))
  if message then
    vim.notify("twintree: " .. message, level)
  end
  return shown
end

return M
