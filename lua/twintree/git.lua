local changes = require("twintree.changes")

local M = {}

---Run git in `cwd`.
---@param cwd string
---@param args string[]
---@return string? stdout
---@return string? err git's error output when the command failed
function M.run(cwd, args)
  local cmd = vim.list_extend({ "git" }, args)
  local ok, proc = pcall(vim.system, cmd, { cwd = cwd })
  if not ok then
    return nil, tostring(proc)
  end
  local res = proc:wait()
  if res.code ~= 0 then
    local msg = vim.trim(res.stderr or "")
    if msg == "" then
      msg = vim.trim(res.stdout or "")
    end
    return nil, msg
  end
  return res.stdout or ""
end

local function run_line(cwd, args)
  local out, err = M.run(cwd, args)
  if not out then
    return nil, err
  end
  return vim.trim(out)
end

---@param dir string
---@return string? toplevel
---@return string? err
function M.toplevel(dir)
  local top = run_line(dir, { "rev-parse", "--show-toplevel" })
  if not top or top == "" then
    return nil, "not a git repository: " .. dir
  end
  return top
end

---Git directory shared by a checkout and all of its linked worktrees.
---@param dir string
---@return string? common_dir
---@return string? err
function M.common_dir(dir)
  local out, err = run_line(dir, {
    "rev-parse",
    "--path-format=absolute",
    "--git-common-dir",
  })
  if not out then
    return nil, err
  end
  return vim.uv.fs_realpath(out) or out
end

---@param dir string
---@param rev string
---@return string? sha
---@return string? err
function M.resolve(dir, rev)
  -- A leading dash would be parsed by git as an option.
  if rev:sub(1, 1) ~= "-" then
    local sha = run_line(dir, {
      "rev-parse",
      "--verify",
      "--quiet",
      rev .. "^{commit}",
    })
    if sha and sha ~= "" then
      return sha
    end
  end
  return nil, "cannot resolve revision: " .. rev
end

---@param dir string
---@param a string
---@param b string
---@return string? sha
---@return string? err
function M.merge_base(dir, a, b)
  local sha = run_line(dir, { "merge-base", a, b })
  if not sha or sha == "" then
    return nil, ("no common ancestor of %s and %s"):format(a, b)
  end
  return sha
end

---Resolve `:Twintree` arguments to the commits of both sides.
---`after == nil` means the working tree.
---@param dir string
---@param revs string[]
---@return { before: string, after?: string }? range
---@return string? err
function M.resolve_range(dir, revs)
  if #revs > 2 then
    return nil, "expected at most two revisions"
  end

  local after
  if #revs == 2 then
    local sha, err = M.resolve(dir, revs[2])
    if not sha then
      return nil, err
    end
    after = sha
  end

  local head, err = M.resolve(dir, "HEAD")
  if not head then
    return nil, err
  end
  if #revs == 0 then
    return { before = head }
  end

  local base
  base, err = M.resolve(dir, revs[1])
  if not base then
    return nil, err
  end
  local before
  before, err = M.merge_base(dir, base, after or head)
  if not before then
    return nil, ("no common ancestor of %s and %s"):format(revs[1], revs[2] or "HEAD")
  end
  return { before = before, after = after }
end

---List files that differ between `before` and `after`.
---@param repo string repository toplevel
---@param before string commit
---@param after? string commit; nil compares against the working tree
---@return twintree.Entry[]? entries
---@return string? err
function M.changed_files(repo, before, after)
  local args = { "diff", "--name-status", "-z", "-M", before }
  if after then
    table.insert(args, after)
  end
  table.insert(args, "--")
  local out, err = M.run(repo, args)
  if not out then
    return nil, err
  end
  local entries = changes.parse_name_status(out)
  if after then
    return changes.sorted(entries)
  end

  out, err = M.run(repo, { "ls-files", "--others", "--exclude-standard", "-z" })
  if not out then
    return nil, err
  end
  return changes.merge_untracked(entries, changes.parse_paths(out))
end

---Branch, tag and remote names for command completion.
---@param dir string
---@return string[]
function M.ref_names(dir)
  local out = M.run(dir, {
    "for-each-ref",
    "--format=%(refname:short)",
    "refs/heads",
    "refs/tags",
    "refs/remotes",
  })
  if not out then
    return {}
  end
  return vim.split(vim.trim(out), "\n", { trimempty = true })
end

return M
