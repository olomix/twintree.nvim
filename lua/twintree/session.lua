local config = require("twintree.config")
local swap = require("twintree.swap")
local worktree = require("twintree.worktree")

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
---@field selected? string path of the tree entry the panes compare
---@field last_entry? string path of the last tree entry the panes
---  compared; kept while they show a file that is not in the tree
---@field pair? twintree.Pair files the panes compare
---@field bufs? { before: integer, after: integer } buffers of that pair
---@field declined? { before?: integer, after?: integer } buffer a pane was
---  taken to whose counterpart was not opened; not followed again while the
---  pane shows it
---@field viewed table<string, boolean> numbers of the file buffers the
---  panes have shown, as strings: a tab variable has no integer keys
---@field collapsed table<string, boolean>
---@field layout twintree.Layout

---Absolute paths of the two files under comparison. A side without a file
---shows the placeholder. Paths, not buffers: a buffer can be deleted while
---the comparison has to survive a layout reset.
---@class twintree.Pair
---@field before? string
---@field after? string

---What the window sizes of the tab are meant to be.
---@class twintree.Layout
---@field ratio number before width divided by before plus after width
---@field tree_width integer width the tree returns to
---@field columns integer terminal width at the last synchronization
---@field tree_shown boolean whether the tree was visible at that time
---@field zoomed boolean whether a window was maximized at that time
---@field seen? { tree?: integer, before: integer, after: integer } widths
---  at that time

local PANES = { "before", "after" }

M.NO_SESSION = "no diff session in this tab"
M.BROKEN_LAYOUT = "a pane of this diff is missing; run :TwintreeResetLayout"
M.TAB_GONE = "the diff tab was closed while a file was shown"

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
  -- Sessions opened by an older version of the plugin have none.
  state.viewed = state.viewed or {}
  -- Sessions opened by an older version of the plugin have no layout.
  state.layout = state.layout or M.default_layout()
  -- Nor do they have a pair.
  if state.selected and not state.pair then
    state.pair = M.entry_pair(state, M.find_entry(state, state.selected) or {
      path = state.selected,
    })
  end
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
  -- Jumps made from the tree open in a pane instead of replacing the tree.
  vim.wo[win].winfixbuf = true
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

---Fill the current tab, a new one, with the three-column layout and
---register the session in it.
---@param repo string
---@param before twintree.Side
---@param after twintree.Side
---@param tree_buf integer
---@return integer tab
local function fill_tab(repo, before, after, tree_buf)
  local tab = vim.api.nvim_get_current_tabpage()
  local tree_win = vim.api.nvim_get_current_win()
  vim.bo[vim.api.nvim_get_current_buf()].bufhidden = "wipe"
  vim.api.nvim_win_set_buf(tree_win, tree_buf)

  M.setup_tree_window(tree_win)
  local before_win, after_win = M.open_panes(tree_win)
  -- Give the tree a previous window. Neovim before 0.13 runs `:windo`
  -- from the previous window when the current one has 'winfixbuf', and
  -- splits the current one when there is none; netrw runs `:windo` for
  -- VimEnter, so `nvim +Twintree` got a second tree window.
  vim.cmd(("noautocmd call win_gotoid(%d)"):format(after_win))
  vim.cmd(("noautocmd call win_gotoid(%d)"):format(tree_win))

  M.save(tab, {
    repo = repo,
    before = before,
    after = after,
    wins = { tree = tree_win, before = before_win, after = after_win },
    tree_buf = tree_buf,
    viewed = {},
    collapsed = {},
    layout = M.default_layout(),
  })
  -- Not `sync`: in a terminal too narrow for the tree the panes come out
  -- squeezed, which `sync` would read as a zoom made by the user.
  -- Required here, not at the top: the layout module requires this one.
  require("twintree.layout").reapply(tab)
  return tab
end

---Open a tab with the three-column layout and register the session in it.
---Always a new tab: a diff in the only tab could not be closed.
---@param repo string
---@param before twintree.Side
---@param after twintree.Side
---@param tree_buf integer
---@return integer? tab
---@return string? err when the layout could not be made; the tab is gone,
---  the tree buffer is left to the caller
function M.create(repo, before, after, tree_buf)
  local origin = vim.api.nvim_get_current_tabpage()
  local existed, shown = {}, {}
  for _, existing in ipairs(vim.api.nvim_list_tabpages()) do
    existed[existing] = true
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    shown[win] = vim.api.nvim_win_get_buf(win)
  end
  -- An autocommand of the user can fail in `:tabnew`, or close the new tab.
  local ok, result = pcall(vim.cmd.tabnew)
  local tab = vim.api.nvim_get_current_tabpage()
  if existed[tab] then
    -- The new tab is gone and a tab of the user is current, the one of the
    -- command or its neighbour: never fill or close it. `:tabnew` puts its
    -- empty buffer into the window that is current when the tab is closed
    -- under it: give that window its buffer back.
    local win = vim.api.nvim_get_current_win()
    local stray, buf = vim.api.nvim_win_get_buf(win), shown[win]
    if buf and stray ~= buf and vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_win_set_buf, win, buf)
      pcall(vim.api.nvim_buf_delete, stray, {})
    end
    if vim.api.nvim_tabpage_is_valid(origin) then
      pcall(vim.api.nvim_set_current_tabpage, origin)
    end
    return nil, "could not open a tab for the diff"
      .. (ok and "" or ": " .. tostring(result))
  end
  if ok then
    ok, result = pcall(fill_tab, repo, before, after, tree_buf)
    if ok then
      return result
    end
  end

  if vim.api.nvim_tabpage_is_valid(tab) then
    pcall(vim.cmd, "tabclose! " .. vim.api.nvim_tabpage_get_number(tab))
  end
  -- Which tab Neovim makes current after a close is the user's setting.
  if vim.api.nvim_tabpage_is_valid(origin) then
    pcall(vim.api.nvim_set_current_tabpage, origin)
  end
  return nil, "could not create the windows of the diff: " .. tostring(result)
end

---@param win integer
---@param enable boolean
---@param pair? twintree.Pair files the panes compare, when enabling
local function set_diff(win, enable, pair)
  if vim.wo[win].diff == enable then
    return
  end
  vim.api.nvim_win_call(win, function()
    vim.cmd(enable and "diffthis" or "diffoff")
    if enable then
      -- Diff mode folds unchanged lines; both sides must stay fully readable.
      vim.wo.foldenable = false
      -- The placeholder has nothing to scroll with: bound to it, the
      -- file in the other pane is scrolled to its end.
      if pair and not (pair.before and pair.after) then
        vim.wo.scrollbind = false
      end
    end
  end)
end

---@param path string
---@return boolean
local function is_file(path)
  local stat = vim.uv.fs_stat(path)
  -- A file can be replaced by a directory of the same name, and vice versa.
  return stat ~= nil and stat.type == "file"
end

---@param state twintree.Session
---@return twintree.Entry[]
local function entries_of(state)
  if not vim.api.nvim_buf_is_valid(state.tree_buf) then
    return {}
  end
  return vim.b[state.tree_buf].twintree_entries or {}
end

---The changed file of a session with the given path.
---@param state twintree.Session
---@param path string
---@return twintree.Entry?
function M.find_entry(state, path)
  for _, entry in ipairs(entries_of(state)) do
    if entry.path == path then
      return entry
    end
  end
  return nil
end

---@param state twintree.Session
---@param entry twintree.Entry
---@return twintree.Pair
function M.entry_pair(state, entry)
  local before = vim.fs.joinpath(state.before.root, entry.old_path or entry.path)
  local after = vim.fs.joinpath(state.after.root, entry.path)
  return {
    before = is_file(before) and before or nil,
    after = is_file(after) and after or nil,
  }
end

---Whether a buffer can have a counterpart on the other side.
---@param buf integer
---@return boolean
function M.is_file_buf(buf)
  return vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= ""
end

---The side a file belongs to, and its path inside that side.
---@param state twintree.Session
---@param path string
---@param prefer? "before"|"after" side that wins when both have one root
---@return ("before"|"after")? side nil for a file outside both sides
---@return string? rel
function M.side_of(state, path, prefer)
  local function match(candidate)
    local side
    for _, pane in ipairs(PANES) do
      local root = state[pane].root
      if vim.startswith(candidate, root .. "/") then
        local longer = side and #root > #state[side].root
        local tie = side and #root == #state[side].root and pane == prefer
        if not side or longer or tie then
          side = pane
        end
      end
    end
    if side then
      return side, candidate:sub(#state[side].root + 2)
    end
  end
  local side, rel = match(vim.fs.normalize(path))
  if not side then
    -- The roots are resolved paths; the name of a buffer need not be.
    side, rel = match(worktree.resolve(path))
  end
  return side, rel
end

---The pair a file belongs to: itself and its counterpart on the other side.
---@param state twintree.Session
---@param path string absolute path of a file
---@param prefer? "before"|"after"
---@return twintree.Pair
function M.pair_of(state, path, prefer)
  local side, rel = M.side_of(state, path, prefer)
  if not side then
    return { before = path, after = path }
  end
  local other_rel = rel
  local entries = entries_of(state)
  if side == "before" then
    for _, entry in ipairs(entries) do
      if entry.old_path == rel then
        other_rel = entry.path
        break
      end
    end
  else
    for _, entry in ipairs(entries) do
      if entry.path == rel then
        other_rel = entry.old_path or rel
        break
      end
    end
  end
  local other = side == "before" and "after" or "before"
  local counterpart = vim.fs.joinpath(state[other].root, other_rel)
  return {
    [side] = path,
    [other] = is_file(counterpart) and counterpart or nil,
  }
end

---Path of the tree entry a pair is the comparison of, if it has one.
---@param state twintree.Session
---@param pair twintree.Pair
---@return string?
function M.entry_path(state, pair)
  local rel = {}
  for _, pane in ipairs(PANES) do
    if pair[pane] then
      local side, path = M.side_of(state, pair[pane], pane)
      rel[pane] = side == pane and path or nil
    end
  end
  local entries = entries_of(state)
  -- In this order: a file can be renamed while a new one takes its old
  -- path, and then two entries share that path.
  local matches = {
    function(entry)
      return rel.after and entry.path == rel.after
    end,
    function(entry)
      return rel.before and entry.old_path == rel.before
    end,
    function(entry)
      return rel.before and not entry.old_path and entry.path == rel.before
    end,
  }
  for _, match in ipairs(matches) do
    for _, entry in ipairs(entries) do
      if match(entry) then
        return entry.path
      end
    end
  end
  return nil
end

---@param state twintree.Session
---@param win integer
---@return ("before"|"after")?
local function pane_of(state, win)
  for _, pane in ipairs(PANES) do
    if state.wins[pane] == win then
      return pane
    end
  end
  return nil
end

---Take a buffer out of the diff of a tab, unless a diff window there still
---shows it. Neovim keeps a buffer that left a diff window as a participant,
---which would make the next pair a three-way diff.
---@param tab integer
---@param buf integer
local function leave_diff(tab, buf)
  if not vim.api.nvim_buf_is_loaded(buf) then
    return
  end
  local wins = vim.api.nvim_tabpage_list_wins(tab)
  for _, win in ipairs(wins) do
    if vim.wo[win].diff and vim.api.nvim_win_get_buf(win) == buf then
      return
    end
  end
  -- The diff belongs to a tab; run the command in this one.
  vim.api.nvim_win_call(wins[1], function()
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("diffoff")
    end)
  end)
end

---@param path? string
---@return integer
local function pair_buf(path)
  if not path then
    return M.placeholder()
  end
  local buf = vim.fn.bufadd(path)
  vim.bo[buf].buflisted = true
  return buf
end

---What an attempt to show a pair needs to be taken back.
---@class twintree.Attempt
---@field previous? { pair?: twintree.Pair, selected?: string, bufs?: table }
---  what the session recorded before; nil while there is nothing to take
---  back
---@field changed table<string, { win: integer, buf: integer }> per pane,
---  the window that was changed and the buffer it showed
---@field bufs? { before: integer, after: integer } buffers of the pair
---  that was attempted

---Take back an attempt to show a pair: the session records the previous
---pair again and the panes changed for it show what they showed before.
---@param tab integer
---@param attempt twintree.Attempt
local function take_back(tab, attempt)
  -- Read again: the tab may be gone, and then nothing is left to restore.
  local state = M.get(tab)
  if not state then
    return
  end
  local previous = attempt.previous
  state.pair, state.selected, state.bufs = previous.pair, previous.selected, previous.bufs
  -- Saved first: the events fired below must find the previous pair.
  M.save(tab, state)
  for pane, change in pairs(attempt.changed) do
    -- Only the window the attempt changed: a layout reset run by an
    -- autocommand in between leaves new panes it never touched.
    if state.wins[pane] == change.win and vim.api.nvim_win_is_valid(change.win) then
      -- While it still shows the attempted file: switched off later, diff
      -- mode would leave that file behind as a third side of the diff.
      set_diff(change.win, false)
      -- A loaded buffer: no swap file is consulted, so the API call is safe.
      local back = vim.api.nvim_buf_is_valid(change.buf) and change.buf or M.placeholder()
      pcall(vim.api.nvim_win_set_buf, change.win, back)
    end
  end
  -- Also the file of a pane that was closed with diff mode on.
  for _, pane in ipairs(PANES) do
    local buf = attempt.bufs and attempt.bufs[pane]
    if buf and vim.api.nvim_buf_is_valid(buf) then
      leave_diff(tab, buf)
    end
  end
  -- A pane without a partner is a plain window.
  local paired = M.has_panes(state)
  for _, pane in ipairs(PANES) do
    local win = state.wins[pane]
    if vim.api.nvim_win_is_valid(win) then
      local recorded = state.bufs and state.bufs[pane]
      local enable = paired and recorded ~= nil and vim.api.nvim_win_get_buf(win) == recorded
      set_diff(win, enable, state.pair)
    end
  end
  require("twintree.treeview").draw(tab)
end

---What `M.show_pair` does, without its guard.
---@param attempt twintree.Attempt filled in for the guard
local function show_pair(tab, pair, opts, attempt)
  local state = M.get(tab)
  if not state then
    return false, M.NO_SESSION
  end
  if not M.has_panes(state) then
    return false, M.BROKEN_LAYOUT
  end

  attempt.previous = { pair = state.pair, selected = state.selected, bufs = state.bufs }
  local replaced = state.bufs or {}
  state.pair = pair
  state.selected = M.entry_path(state, pair)
  state.bufs = { before = pair_buf(pair.before), after = pair_buf(pair.after) }
  attempt.bufs = state.bufs
  -- Saved before any window changes: the events fired below find the
  -- buffers recorded and do not follow them again.
  M.save(tab, state)

  local keepalt = opts and opts.keepalt
  -- The pane that keeps its alternate file comes last: the buffer leaving
  -- it is then already shown in the other pane and is never hidden.
  local order = keepalt == "before" and { "after", "before" } or PANES
  for _, pane in ipairs(order) do
    local win, buf = state.wins[pane], state.bufs[pane]
    set_diff(win, false)
    local shown = vim.api.nvim_win_get_buf(win)
    if shown ~= buf then
      -- Before the attempt: a failed one can still leave the buffer in
      -- the window.
      attempt.changed[pane] = { win = win, buf = shown }
      local ok, reason = swap.open(win, buf, keepalt == pane)
      if not ok then
        -- A window closed while it loaded its file also ends here, and
        -- then the file is not what went wrong.
        local problem = M.layout_problem(tab)
        if problem then
          return false, problem
        end
        local name = vim.fs.basename(vim.api.nvim_buf_get_name(buf))
        return false, ("%s was not opened: %s"):format(name, reason)
      end
    end
  end
  for _, pane in ipairs(PANES) do
    leave_diff(tab, replaced[pane] or state.bufs[pane])
  end
  for _, pane in ipairs(PANES) do
    set_diff(state.wins[pane], true, pair)
  end
  -- The last event above can close a pane without anything raising.
  local problem = M.layout_problem(tab)
  if problem then
    return false, problem
  end

  -- Only now does the file count as shown: an attempt that is taken back
  -- leaves no position and no cursor rule behind. Read again, because
  -- the events above may have changed the record.
  local previous = attempt.previous
  state = assert(M.get(tab))
  state.declined = nil
  -- The previous selection stands in for a session that has no last entry.
  state.last_entry = state.selected or state.last_entry or previous.selected
  for _, pane in ipairs(PANES) do
    if pair[pane] then
      state.viewed[tostring(state.bufs[pane])] = true
    end
  end
  M.save(tab, state)
  attempt.previous = nil

  -- Required here, not at the top: the tree view requires this module.
  local treeview = require("twintree.treeview")
  treeview.draw(tab)
  -- Every window that shows the tree, also one the user made for it.
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if vim.api.nvim_win_get_buf(win) == state.tree_buf then
      treeview.focus_selected(tab, win)
    end
  end
  return true
end

-- Whether a pair is being put into the panes right now.
local showing = false

---Why a tab cannot show a pair, when its layout is the reason.
---@param tab integer
---@return string? problem nil for a tab with a session and both panes
function M.layout_problem(tab)
  local state = M.get(tab)
  if not state then
    return M.TAB_GONE
  end
  if not M.has_panes(state) then
    return M.BROKEN_LAYOUT
  end
  return nil
end

---Show a pair of files in the panes, diffed against each other, and mark
---its entry in the tree. When that does not work out, because a file is
---not opened or because a pane or the tab goes away on the way, the
---session and the panes that are left are as before the call.
---@param tab integer
---@param pair twintree.Pair
---@param opts? { keepalt?: "before"|"after" } pane whose alternate file
---  must not change
---@return boolean ok
---@return string? err
function M.show_pair(tab, pair, opts)
  -- A declined swap file makes Neovim put a pane back to its old buffer;
  -- following that would move the other pane in the middle of the attempt.
  showing = true
  local attempt = { changed = {} }
  local ran, ok, err = pcall(show_pair, tab, pair, opts, attempt)
  if not ran then
    -- Loading a file runs autocommands, which can close a pane or the
    -- tab; every later use of what is gone raises. Anything else is a bug.
    local problem = M.layout_problem(tab)
    if not problem then
      showing = false
      error(ok, 0)
    end
    ok, err = false, problem
  end
  if not ok and attempt.previous then
    local undone, undo_err = pcall(take_back, tab, attempt)
    -- The same rule as above: with the layout intact, an error is a bug.
    if not undone and not M.layout_problem(tab) then
      showing = false
      error(undo_err, 0)
    end
  end
  showing = false
  return ok, err
end

---Put the cursor of a diff window on the first change of its file. The
---other diff window follows, because the two are bound.
---@param win integer
local function goto_first_change(win)
  -- An autocommand of the user can close it once both files are shown.
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  -- A jump that fails leaves the cursor where it is; the file is shown.
  pcall(vim.api.nvim_win_call, win, function()
    vim.cmd("keepjumps normal! gg")
    vim.cmd("keepjumps normal! ]c")
    -- `]c` skips a change on the first line, or one made of lines missing
    -- above it. `[c` goes back to it and stays put when there is none.
    if vim.fn.line(".") > 1 then
      vim.cmd("keepjumps normal! [c")
    end
  end)
end

---Show a changed file in both panes, diffed against each other. A file
---the session has not shown before gets the cursor on its first change;
---one it has shown keeps the position it was left on.
---@param tab integer
---@param entry twintree.Entry
---@param opts? { keep_focus?: boolean } leave the current window current
---  instead of going to the after pane
---@return boolean ok
---@return string? err
function M.show(tab, entry, opts)
  local state = M.get(tab)
  if not state then
    return false, M.NO_SESSION
  end
  local viewed = state.viewed
  local pair = M.entry_pair(state, entry)
  local ok, err = M.show_pair(tab, pair)
  if not ok then
    return false, err
  end
  state = M.get(tab)
  if not state then
    return false, M.TAB_GONE
  end
  -- In one pane only: a jump in the other pane as well would drag this
  -- one past a block of lines that exists on one side.
  local pane = pair.after and "after" or "before"
  if pair[pane] and not viewed[tostring(state.bufs[pane])] then
    goto_first_change(state.wins[pane])
  end
  local keep_focus = opts and opts.keep_focus
  if not keep_focus and vim.api.nvim_win_is_valid(state.wins.after) then
    vim.api.nvim_set_current_win(state.wins.after)
  end
  return true
end

---Forget the compared files and leave diff mode in both panes.
---@param tab integer
function M.clear_selection(tab)
  local state = M.get(tab)
  if not state then
    return
  end
  state.selected = nil
  state.pair = nil
  state.bufs = nil
  M.save(tab, state)
  for _, pane in ipairs(PANES) do
    if vim.api.nvim_win_is_valid(state.wins[pane]) then
      set_diff(state.wins[pane], false)
    end
  end
end

---Take a new window of a diff tab out of diff mode, unless it is a pane.
---A window split off a pane copies its diff mode and would join the
---comparison as a third participant.
function M.undiff_new_window()
  local win = vim.api.nvim_get_current_win()
  local state = M.get(vim.api.nvim_win_get_tabpage(win))
  if state and not pane_of(state, win) then
    set_diff(win, false)
  end
end

---Put a file that landed in the pane of the other side into its own pane,
---with the view it had, and show its counterpart where it landed.
---@param tab integer
---@param win integer window the file landed in
---@param buf integer
local function move_to_own_pane(tab, win, buf)
  if not vim.api.nvim_tabpage_is_valid(tab) then
    return
  end
  local state = M.get(tab)
  if
    not state
    or not M.has_panes(state)
    -- A layout reset in between closes it and leaves valid new panes.
    or not vim.api.nvim_win_is_valid(win)
    or not vim.api.nvim_buf_is_valid(buf)
    or vim.api.nvim_win_get_buf(win) ~= buf
  then
    return
  end
  local landing = pane_of(state, win)
  local path = vim.api.nvim_buf_get_name(buf)
  local side = M.side_of(state, path, landing)
  if not landing or not side or side == landing then
    return
  end
  -- One jump queues this move more than once. After a declined swap file
  -- the file is still in the landing pane, and every further call would
  -- ask again.
  if state.declined and state.declined[landing] == buf then
    return
  end

  local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
  local was_current = vim.api.nvim_get_current_win() == win
  local own = state.wins[side]
  local ok, err = M.show_pair(tab, M.pair_of(state, path, landing), { keepalt = landing })
  if not ok then
    M.decline(tab, landing, buf, err)
    return
  end
  -- The file is shown; its pane can still be closed while the tree is drawn.
  if not vim.api.nvim_win_is_valid(own) then
    return
  end
  vim.api.nvim_win_call(own, function()
    vim.fn.winrestview(view)
  end)
  if was_current then
    vim.api.nvim_set_current_win(own)
  end
end

---Report a file whose counterpart was not opened, and stop following it:
---the events that brought it fire more than once, and each would ask again.
---@param tab integer
---@param pane string pane the user took to the file
---@param buf integer
---@param err string
function M.decline(tab, pane, buf, err)
  local state = M.get(tab)
  if state then
    state.declined = state.declined or {}
    state.declined[pane] = buf
    M.save(tab, state)
  end
  vim.notify("twintree: " .. err, vim.log.levels.ERROR)
end

---Keep the panes comparing whatever file one of them is taken to: the
---other pane shows the same file from its side. Buffers that are not files
---get a plain window.
function M.follow()
  if showing then
    return
  end
  local win = vim.api.nvim_get_current_win()
  local tab = vim.api.nvim_win_get_tabpage(win)
  local state = M.get(tab)
  local pane = state and pane_of(state, win)
  if not state or not pane then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  if state.declined and state.declined[pane] then
    if state.declined[pane] == buf then
      set_diff(win, false)
      return
    end
    -- The pane moved on; coming back to that file asks again.
    state.declined[pane] = nil
    M.save(tab, state)
  end
  if state.bufs and state.bufs[pane] == buf then
    -- Not without the other pane: alone, a pane is a plain window.
    set_diff(win, M.has_panes(state), state.pair)
    return
  end
  if not M.is_file_buf(buf) or not M.has_panes(state) then
    set_diff(win, false)
    return
  end

  local path = vim.api.nvim_buf_get_name(buf)
  local side = M.side_of(state, path, pane)
  if side and side ~= pane then
    set_diff(win, false)
    -- The command that brought the file places the cursor after this event,
    -- so the move has to wait. SafeState comes before the screen is drawn
    -- and spares a flash of the file in the wrong pane; it does not fire
    -- for a jump made by a mapping or a callback, which the scheduled call
    -- covers. Whichever runs second finds the file moved, or its
    -- counterpart declined, and does nothing.
    local function move()
      move_to_own_pane(tab, win, buf)
    end
    vim.api.nvim_create_autocmd("SafeState", { once = true, callback = move })
    vim.schedule(move)
    return
  end
  local ok, err = M.show_pair(tab, M.pair_of(state, path, pane))
  if not ok then
    M.decline(tab, pane, buf, err)
  end
end

---Roots of both panes of every open session, the working directory included.
---@return string[]
function M.pane_roots()
  local roots = {}
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    local state = M.get(tab)
    if state then
      for _, pane in ipairs(PANES) do
        table.insert(roots, state[pane].root)
      end
    end
  end
  return roots
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
