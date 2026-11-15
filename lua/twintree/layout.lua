local session = require("twintree.session")

local M = {}

---@class twintree.LayoutInput
---@field columns integer current width of the terminal
---@field layout twintree.Layout what was stored at the last synchronization
---@field tree? integer width of the tree window, nil when it is hidden
---@field before integer
---@field after integer
---@field tree_fixed boolean whether the tree window has 'winfixwidth'
---@field min integer width a squeezed window ends up with

---@class twintree.LayoutAction
---@field kind "none"|"apply"|"restore"|"unfix"|"learn"
---@field zoomed boolean whether a window is maximized after the action
---@field ratio? number for "learn"
---@field tree_width? integer for "learn"

---Width of the before pane for a ratio.
---@param avail integer combined width of both panes
---@param ratio number
---@return integer
function M.before_width(avail, ratio)
  local width = math.floor(avail * ratio + 0.5)
  return math.max(1, math.min(width, avail - 1))
end

---Decide what a change of window sizes means. Pure; see design decision 2
---of the add-layout-management change for the rules.
---@param input twintree.LayoutInput
---@return twintree.LayoutAction
function M.decide(input)
  local stored = input.layout
  local tree_shown = input.tree ~= nil
  local function squeezed(width)
    return width <= input.min
  end
  local tree_squeezed = tree_shown and squeezed(input.tree)
  local panes_squeezed = squeezed(input.before) and squeezed(input.after)
  local zoomed = tree_squeezed or squeezed(input.before) or squeezed(input.after)

  if input.columns ~= stored.columns then
    -- A shrinking terminal can squeeze a pane just like a zoom does, so
    -- only what was stored before the resize tells the two apart.
    if stored.zoomed then
      return { kind = "none", zoomed = true }
    end
    return { kind = "apply", zoomed = false }
  end
  if tree_shown ~= stored.tree_shown then
    return { kind = "apply", zoomed = false }
  end
  -- What `<C-w>=` leaves after a pane was maximized: the fixed-width tree
  -- stays squeezed while the panes are equalized.
  if tree_squeezed and not squeezed(input.before) and not squeezed(input.after) then
    return { kind = "restore", zoomed = false }
  end
  -- The tree itself is maximized. Without this `<C-w>=` would change
  -- nothing, and there would be no event to restore the layout on.
  if tree_shown and not tree_squeezed and panes_squeezed then
    return { kind = "unfix", zoomed = true }
  end
  if zoomed then
    return { kind = "none", zoomed = true }
  end
  if tree_shown and not input.tree_fixed then
    return { kind = "restore", zoomed = false }
  end

  local avail = input.before + input.after
  local ratio = stored.ratio
  if math.abs(input.before - input.after) <= 1 then
    -- Equal panes mean one half, whichever pane got the odd column.
    ratio = 0.5
  elseif M.before_width(avail, ratio) ~= input.before then
    -- Keep the stored ratio when it already gives this width, so that our
    -- own rounding never drifts it.
    ratio = input.before / avail
  end
  return {
    kind = "learn",
    zoomed = false,
    ratio = ratio,
    tree_width = tree_shown and input.tree or stored.tree_width,
  }
end

local function apply(state, tree_win)
  local layout = state.layout
  if tree_win then
    vim.wo[tree_win].winfixwidth = true
    vim.api.nvim_win_set_width(tree_win, layout.tree_width)
  end
  local before, after = state.wins.before, state.wins.after
  local avail = vim.api.nvim_win_get_width(before) + vim.api.nvim_win_get_width(after)
  vim.api.nvim_win_set_width(before, M.before_width(avail, layout.ratio))
end

local syncing = false

---Bring the window sizes of a diff tab in line with the stored layout, or
---learn from them, after anything changed the sizes.
---@param tab? integer
---@return string? kind the action taken, nil when there was nothing to do
function M.sync(tab)
  tab = tab or vim.api.nvim_get_current_tabpage()
  if syncing then
    return nil
  end
  local state = session.get(tab)
  if not state or not session.has_panes(state) then
    return nil
  end

  local tree_win = session.tree_win(state)
  local action = M.decide({
    columns = vim.o.columns,
    layout = state.layout,
    tree = tree_win and vim.api.nvim_win_get_width(tree_win) or nil,
    before = vim.api.nvim_win_get_width(state.wins.before),
    after = vim.api.nvim_win_get_width(state.wins.after),
    tree_fixed = tree_win ~= nil and vim.wo[tree_win].winfixwidth,
    min = math.max(1, vim.o.winminwidth),
  })

  syncing = true
  local ok, err = pcall(function()
    if action.kind == "learn" then
      state.layout.ratio = action.ratio
      state.layout.tree_width = action.tree_width
    elseif action.kind == "unfix" then
      vim.wo[tree_win].winfixwidth = false
    elseif action.kind == "restore" then
      state.layout.ratio = 0.5
      apply(state, tree_win)
    elseif action.kind == "apply" then
      apply(state, tree_win)
    end
  end)
  syncing = false

  state.layout.columns = vim.o.columns
  state.layout.tree_shown = tree_win ~= nil
  state.layout.zoomed = action.zoomed
  session.save(tab, state)
  if not ok then
    error(err, 0)
  end
  return action.kind
end

return M
