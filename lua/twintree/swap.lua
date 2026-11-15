local M = {}

M.DECLINED = "the swap file question was declined"

-- Labels as in Neovim's own dialog, with the letter `v:swapchoice` expects.
local CHOICES = {
  { "&Open Read-Only", "o" },
  { "&Edit anyway", "e" },
  { "&Recover", "r" },
  { "&Delete it", "d" },
  { "&Quit", "q" },
  { "&Abort", "a" },
}

local function date(seconds)
  return os.date("%a %b %d %H:%M:%S %Y", seconds)
end

---The text of the prompt, in the layout of Neovim's ATTENTION message.
---@param swapname string
---@param info table what `swapinfo()` returned for the swap file
---@param path string file that is being opened
---@param file_mtime? integer modification time of that file
---@return string
function M.describe(swapname, info, path, file_mtime)
  local lines = {
    "E325: ATTENTION",
    ('Found a swap file by the name "%s"'):format(swapname),
  }
  if info.error then
    table.insert(lines, ("        %s"):format(info.error))
  else
    local running = (info.pid or 0) > 0
    vim.list_extend(lines, {
      ("          owned by: %s   dated: %s"):format(info.user, date(info.mtime)),
      ("         file name: %s"):format(info.fname),
      ("          modified: %s"):format(info.dirty == 1 and "YES" or "no"),
      ("         user name: %s   host name: %s"):format(info.user, info.host),
      -- `swapinfo()` gives no process id once the process is gone.
      running and ("        process ID: %d (STILL RUNNING)"):format(info.pid)
        or "        process ID: no longer running",
    })
  end
  table.insert(lines, ('While opening file "%s"'):format(path))
  if file_mtime then
    table.insert(lines, ("             dated: %s"):format(date(file_mtime)))
  end
  return table.concat(lines, "\n")
end

---The choices of the prompt.
---@param running boolean whether the process that owns the swap file runs
---@return string[] labels
---@return string[] letters for `v:swapchoice`, in the same order
function M.choices(running)
  local labels, letters = {}, {}
  for _, choice in ipairs(CHOICES) do
    -- Neovim does not offer to delete the swap file of a running process.
    if not (running and choice[2] == "d") then
      table.insert(labels, choice[1])
      table.insert(letters, choice[2])
    end
  end
  return labels, letters
end

---The letter for an answer of the prompt. No answer means Abort.
---@param letters string[]
---@param answer integer index of the chosen label, 0 when dismissed
---@return string
function M.letter(letters, answer)
  return letters[answer] or "a"
end

---Ask what to do with a swap file. A field, so that tests can replace it.
---@param text string
---@param labels string[]
---@return integer answer index of the chosen label, 0 when dismissed
function M.ask(text, labels)
  return vim.fn.confirm(text, table.concat(labels, "\n"), 1, "Question")
end

-- Whether the plugin itself is putting a file into a pane right now.
local opening = false
local chosen

---@return boolean
function M.is_opening()
  return opening
end

---Decide about a swap file found while the plugin opens a file. Files the
---user opens, and swap files an earlier handler decided about, are left to
---Neovim.
function M.on_swap_exists()
  if not opening or vim.v.swapchoice ~= "" then
    return
  end
  -- Nobody can answer; Neovim's error then reports the file as not opened.
  if #vim.api.nvim_list_uis() == 0 then
    return
  end
  local swapname = vim.v.swapname
  local info = vim.fn.swapinfo(swapname)
  local path = vim.fn.expand("<afile>:p")
  local stat = vim.uv.fs_stat(path)
  local labels, letters = M.choices(not info.error and (info.pid or 0) > 0)
  local text = M.describe(swapname, info, path, stat and stat.mtime.sec)
  chosen = M.letter(letters, M.ask(text, labels))
  vim.v.swapchoice = chosen
end

---One line saying why a buffer was not opened.
local function reason(err)
  if chosen == "q" or chosen == "a" then
    return M.DECLINED
  end
  local text = tostring(err or "")
  return text:match("E%d+: [^\n]*") or text:match("[^\n]+") or "it could not be loaded"
end

---Put a buffer into a window the way `:buffer` does, so that Neovim's swap
---file handling applies; the API call would end in E325 for any swap file.
---@param win integer
---@param buf integer
---@param keepalt? boolean keep the alternate file of the window
---@return boolean ok
---@return string? reason one line, when the buffer was not opened
function M.open(win, buf, keepalt)
  if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf) then
    return false, "its window or buffer is gone"
  end
  opening, chosen = true, nil
  local ok, err = pcall(vim.api.nvim_win_call, win, function()
    vim.cmd((keepalt and "keepalt " or "") .. "buffer " .. buf)
  end)
  opening = false
  -- Quit leaves the buffer unloaded without raising.
  local shown = ok
    and vim.api.nvim_win_is_valid(win)
    and vim.api.nvim_win_get_buf(win) == buf
    and vim.api.nvim_buf_is_loaded(buf)
  if shown then
    return true
  end
  return false, reason(err)
end

return M
