local M = {}

local function real(path)
  return vim.uv.fs_realpath(path) or path
end

function M.tmpdir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return real(dir)
end

function M.git(dir, ...)
  local res = vim.system({ "git", ... }, { cwd = dir }):wait()
  assert(res.code == 0, ("git %s failed: %s"):format(table.concat({ ... }, " "), res.stderr))
  return vim.trim(res.stdout)
end

function M.write(dir, path, text)
  local full = vim.fs.joinpath(dir, path)
  vim.fn.mkdir(vim.fs.dirname(full), "p")
  local f = assert(io.open(full, "w"))
  f:write(text)
  f:close()
end

function M.commit(dir, message)
  M.git(dir, "add", "-A")
  M.git(dir, "commit", "-q", "-m", message)
  return M.git(dir, "rev-parse", "HEAD")
end

---Create a repository with one commit containing `files` (path -> text).
function M.repo(files)
  local dir = M.tmpdir()
  M.git(dir, "init", "-q", "-b", "main")
  for path, text in pairs(files or { ["a.txt"] = "a\n" }) do
    M.write(dir, path, text)
  end
  local sha = M.commit(dir, "initial")
  return dir, sha
end

---Reset editor state and point the plugin at a fresh cache directory.
function M.reset()
  vim.cmd("silent! tabonly!")
  vim.cmd("silent! only!")
  -- Left set when the remaining window was the tree of a diff.
  vim.wo.winfixbuf = false
  vim.cmd("silent! %bwipeout!")
  vim.t.twintree = nil
  local cache = M.tmpdir()
  require("twintree").setup({ cache_dir = cache })
  return cache
end

function M.keys(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), "mx", false)
end

function M.buf_lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

---Start a second Neovim that edits `path` and so holds its swap file in
---`swap_dir`. With `kill` the process is killed, which leaves the swap file
---behind as after a crash.
---@return integer job
function M.swap_owner(path, swap_dir, kill)
  local job = vim.fn.jobstart({
    vim.v.progpath,
    "--headless",
    "-u",
    "NONE",
    "--cmd",
    "set swapfile directory=" .. swap_dir .. "//",
    path,
    "-c",
    "normal! ix",
    "-c",
    "preserve",
  })
  assert(job > 0, "could not start a second Neovim")
  assert(vim.wait(5000, function()
    return #vim.fn.glob(swap_dir .. "/*", true, true) > 0
  end, 20), "the second Neovim wrote no swap file")
  if kill then
    vim.uv.kill(vim.fn.jobpid(job), "sigkill")
    assert(vim.wait(5000, function()
      return vim.fn.jobwait({ job }, 0)[1] ~= -1
    end, 20), "the second Neovim did not die")
  end
  return job
end

---A tree line without its padding: runs of spaces become one space.
function M.squeeze(line)
  return (line:gsub("  +", " "))
end

---The lines of a tree buffer without their padding.
function M.tree_lines(buf)
  return vim.tbl_map(M.squeeze, M.buf_lines(buf))
end

---Move the cursor of `win` to the first line containing `text`.
function M.goto_line(win, text)
  local buf = vim.api.nvim_win_get_buf(win)
  for row, line in ipairs(M.buf_lines(buf)) do
    if line:find(text, 1, true) then
      vim.api.nvim_set_current_win(win)
      vim.api.nvim_win_set_cursor(win, { row, 0 })
      return row
    end
  end
  error("line not found: " .. text)
end

return M
