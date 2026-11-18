local config = require("twintree.config")
local git = require("twintree.git")

local M = {}

local function real(path)
  return vim.uv.fs_realpath(path) or vim.fs.normalize(path)
end

---Stable identifier of a repository, shared by all of its checkouts.
---@param repo string any directory inside the repository
---@return string? id
---@return string? err
function M.repo_id(repo)
  local common, err = git.common_dir(repo)
  if not common then
    return nil, err
  end
  local name = vim.fs.basename(common)
  if name == ".git" then
    name = vim.fs.basename(vim.fs.dirname(common))
  end
  return name .. "-" .. vim.fn.sha256(common):sub(1, 12)
end

---Directory holding all cached worktrees of a repository.
---@param repo string
---@return string? dir
---@return string? err
function M.repo_dir(repo)
  local id, err = M.repo_id(repo)
  if not id then
    return nil, err
  end
  return vim.fs.joinpath(config.cache_dir(), id)
end

---@param repo string
---@param sha string full commit hash
---@return string? path
---@return string? err
function M.path(repo, sha)
  local dir, err = M.repo_dir(repo)
  if not dir then
    return nil, err
  end
  return vim.fs.joinpath(dir, sha)
end

local function is_worktree_at(path, sha)
  if not vim.uv.fs_stat(path) then
    return false
  end
  local out = git.run(path, { "rev-parse", "--show-toplevel", "HEAD" })
  if not out then
    return false
  end
  local lines = vim.split(vim.trim(out), "\n")
  return real(lines[1]) == real(path) and lines[2] == sha
end

---Remove a cached worktree from disk and from the repository's registry.
---@param repo string
---@param path string
function M.remove(repo, path)
  git.run(repo, { "worktree", "remove", "--force", path })
  if vim.uv.fs_stat(path) then
    vim.fs.rm(path, { recursive = true, force = true })
  end
  git.run(repo, { "worktree", "prune" })
  -- Fails while other worktrees of the repository remain, as intended.
  vim.uv.fs_rmdir(vim.fs.dirname(path))
end

---@param repo string
---@param sha string
---@return boolean ready whether a usable worktree for `sha` is cached
function M.is_ready(repo, sha)
  local path = M.path(repo, sha)
  return path ~= nil and is_worktree_at(path, sha)
end

---Return a worktree checked out at `sha`, creating it when needed.
---@param repo string repository toplevel
---@param sha string full commit hash
---@return string? path
---@return string? err
function M.ensure(repo, sha)
  local path, err = M.path(repo, sha)
  if not path then
    return nil, err
  end
  if is_worktree_at(path, sha) then
    return real(path)
  end

  M.remove(repo, path)
  vim.fn.mkdir(vim.fs.dirname(path), "p")

  vim.notify(("twintree: checking out %s"):format(sha:sub(1, 10)))
  local _, add_err = git.run(repo, { "worktree", "add", "--detach", path, sha })
  if add_err then
    -- git keeps the worktree registered when a post-checkout hook fails.
    M.remove(repo, path)
    return nil, add_err
  end
  return real(path)
end

---@param repo string
---@return string[] paths of cached worktrees
function M.list(repo)
  local dir = M.repo_dir(repo)
  if not dir or not vim.uv.fs_stat(dir) then
    return {}
  end
  local paths = {}
  for name, kind in vim.fs.dir(dir) do
    if kind == "directory" then
      table.insert(paths, real(vim.fs.joinpath(dir, name)))
    end
  end
  table.sort(paths)
  return paths
end

---Remove cached worktrees of `repo`, except those listed in `in_use`.
---@param repo string
---@param in_use? string[] worktree roots to keep
---@return integer removed
function M.clean(repo, in_use)
  local keep = {}
  for _, root in ipairs(in_use or {}) do
    keep[real(root)] = true
  end
  local removed = 0
  for _, path in ipairs(M.list(repo)) do
    if not keep[path] then
      M.remove(repo, path)
      removed = removed + 1
    end
  end
  return removed
end

---Path with symbolic links resolved, also for a file that does not exist.
---@param path string
---@return string
function M.resolve(path)
  local resolved = vim.uv.fs_realpath(path)
  if resolved then
    return resolved
  end
  -- A new file does not exist yet; resolve its directory instead.
  local dir = vim.uv.fs_realpath(vim.fs.dirname(path))
  return dir and vim.fs.joinpath(dir, vim.fs.basename(path))
    or vim.fs.normalize(path)
end

---@param path string
---@return boolean
function M.is_cached(path)
  if path == "" then
    return false
  end
  local cache = vim.uv.fs_realpath(config.cache_dir())
  if not cache then
    return false
  end
  return vim.startswith(M.resolve(path), cache .. "/")
end

---Root of the cached worktree that holds `path`: the directory of a commit,
---two levels below the cache directory.
---@param path string
---@return string? root
function M.root_of(path)
  if path == "" then
    return nil
  end
  local cache = vim.uv.fs_realpath(config.cache_dir())
  if not cache then
    return nil
  end
  local resolved = M.resolve(path)
  if not vim.startswith(resolved, cache .. "/") then
    return nil
  end
  local parts = vim.split(resolved:sub(#cache + 2), "/", { plain = true })
  -- By name, not by what is on disk: the root of a removed worktree counts,
  -- a file next to the commit directories does not.
  if #parts < 2 or not parts[2]:match("^%x+$") or #parts[2] < 40 then
    return nil
  end
  return vim.fs.joinpath(cache, parts[1], parts[2])
end

---Buffers that an entry of a quickfix or location list points at.
---@return table<integer, true>
local function buffers_in_lists()
  local found = {}
  local function collect(get)
    for nr = 1, get({ nr = "$" }).nr do
      for _, item in ipairs(get({ nr = nr, items = 1 }).items) do
        found[item.bufnr] = true
      end
    end
  end
  collect(vim.fn.getqflist)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    collect(function(what)
      return vim.fn.getloclist(win, what)
    end)
  end
  return found
end

---@param client vim.lsp.Client
---@return string[] folders the client works on
local function client_folders(client)
  local folders = {}
  for _, folder in ipairs(client.workspace_folders or {}) do
    table.insert(folders, vim.uri_to_fname(folder.uri))
  end
  if #folders == 0 and client.root_dir then
    table.insert(folders, client.root_dir)
  end
  return folders
end

---Wipe out the hidden buffers of cached worktrees that are not in use, and
---stop the LSP clients that worked on nothing else. Never raises.
---@param in_use string[] roots of the panes of all open sessions
function M.release(in_use)
  local keep = {}
  for _, root in ipairs(in_use) do
    keep[real(root)] = true
  end
  local function unused(path)
    local root = M.root_of(path)
    return root ~= nil and not keep[root]
  end

  local in_lists = buffers_in_lists()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if
      vim.api.nvim_buf_is_valid(buf)
      and vim.bo[buf].buftype == ""
      and not vim.bo[buf].modified
      and not in_lists[buf]
      and #vim.fn.win_findbuf(buf) == 0
      and unused(vim.api.nvim_buf_get_name(buf))
    then
      -- Not nvim_buf_delete(): an error of a user's BufWipeout autocommand
      -- escapes its pcall and stops the remaining wipes.
      pcall(vim.cmd.bwipeout, buf)
    end
  end

  for _, client in ipairs(vim.lsp.get_clients()) do
    pcall(function()
      if next(client.attached_buffers) ~= nil or client:is_stopped() then
        return
      end
      local folders = client_folders(client)
      if #folders == 0 then
        return
      end
      for _, folder in ipairs(folders) do
        if not unused(folder) then
          return
        end
      end
      -- An explicit false: no argument means a forced stop after a timeout.
      client:stop(false)
    end)
  end
end

---Keep a cached worktree file from using a swap file. The cache is shared
---by all Neovim instances, and a second one would stop on E325 otherwise.
---@param buf integer
function M.disable_swap(buf)
  if vim.bo[buf].buftype == "" and M.is_cached(vim.api.nvim_buf_get_name(buf)) then
    vim.bo[buf].swapfile = false
  end
end

---Make a buffer read-only when its file belongs to a cached worktree.
---@param buf integer
function M.protect(buf)
  if vim.bo[buf].buftype ~= "" then
    return
  end
  if M.is_cached(vim.api.nvim_buf_get_name(buf)) then
    vim.bo[buf].readonly = true
    vim.bo[buf].modifiable = false
  end
end

return M
