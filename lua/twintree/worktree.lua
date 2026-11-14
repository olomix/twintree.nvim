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

local function remove(repo, path)
  git.run(repo, { "worktree", "remove", "--force", path })
  if vim.uv.fs_stat(path) then
    vim.fs.rm(path, { recursive = true, force = true })
  end
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

  remove(repo, path)
  git.run(repo, { "worktree", "prune" })
  vim.fn.mkdir(vim.fs.dirname(path), "p")

  vim.notify(("twintree: checking out %s"):format(sha:sub(1, 10)))
  local _, add_err = git.run(repo, { "worktree", "add", "--detach", path, sha })
  if add_err then
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
      remove(repo, path)
      removed = removed + 1
    end
  end
  git.run(repo, { "worktree", "prune" })
  local dir = M.repo_dir(repo)
  if dir then
    -- Fails when worktrees in use remain, which is what we want.
    vim.uv.fs_rmdir(dir)
  end
  return removed
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
  local resolved = vim.uv.fs_realpath(path)
  if not resolved then
    -- A new file does not exist yet; resolve its directory instead.
    local dir = vim.uv.fs_realpath(vim.fs.dirname(path))
    resolved = dir and vim.fs.joinpath(dir, vim.fs.basename(path))
      or vim.fs.normalize(path)
  end
  return vim.startswith(resolved, cache .. "/")
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
