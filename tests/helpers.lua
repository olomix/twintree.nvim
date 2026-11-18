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
  -- Written by the child after its edit is in the swap file: the swap file
  -- itself exists before that, as soon as the file is loaded.
  local preserved = vim.fn.tempname()
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
    "-c",
    ("call writefile([], '%s')"):format(preserved),
  })
  assert(job > 0, "could not start a second Neovim")
  assert(vim.wait(5000, function()
    return vim.uv.fs_stat(preserved) ~= nil
      and #vim.fn.glob(swap_dir .. "/*", true, true) > 0
  end, 20), "the second Neovim wrote no swap file")
  if kill then
    vim.uv.kill(vim.fn.jobpid(job), "sigkill")
    assert(vim.wait(5000, function()
      return vim.fn.jobwait({ job }, 0)[1] ~= -1
    end, 20), "the second Neovim did not die")
  end
  return job
end

local lsp_count = 0

---Start an LSP client whose server runs inside Neovim. The returned record
---tells what the server received: `shutdown`, `exit`, `terminate`.
---@param opts { root_dir?: string, workspace_folders?: string[],
---  delay_shutdown?: boolean, fail_shutdown?: boolean, exit_timeout?: integer }
---@return vim.lsp.Client client
---@return table server
function M.lsp(opts)
  local server = {}
  local function cmd(dispatchers)
    local closing = false
    local function close()
      if not closing then
        closing = true
        dispatchers.on_exit(0, 0)
      end
    end
    return {
      request = function(method, _, callback)
        if method == "initialize" then
          callback(nil, { capabilities = {} })
        elseif method == "shutdown" then
          if opts.fail_shutdown then
            error("the server refuses to shut down")
          end
          server.shutdown = true
          if opts.delay_shutdown then
            server.answer_shutdown = function()
              callback(nil, nil)
            end
          else
            callback(nil, nil)
          end
        end
        return true, 1
      end,
      notify = function(method)
        if method == "exit" then
          server.exit = true
          close()
        end
        return true
      end,
      is_closing = function()
        return closing
      end,
      terminate = function()
        server.terminate = true
        close()
      end,
    }
  end
  local folders
  if opts.workspace_folders then
    folders = vim.tbl_map(function(dir)
      return { uri = vim.uri_from_fname(dir), name = dir }
    end, opts.workspace_folders)
  end
  lsp_count = lsp_count + 1
  local id = assert(vim.lsp.start({
    -- A name of its own: vim.lsp.start reuses a client by name and root.
    name = "fake" .. lsp_count,
    cmd = cmd,
    root_dir = opts.root_dir,
    workspace_folders = folders,
    exit_timeout = opts.exit_timeout,
  }, { attach = false }))
  assert(vim.wait(2000, function()
    local client = vim.lsp.get_client_by_id(id)
    return client ~= nil and client.initialized == true
  end, 10), "the LSP client did not initialize")
  return vim.lsp.get_client_by_id(id), server
end

---Whether `client` left the list of running clients.
function M.lsp_gone(client)
  return vim.wait(2000, function()
    return vim.lsp.get_client_by_id(client.id) == nil
  end, 10)
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
