local M = {}

---@class twintree.Entry
---@field status "A"|"M"|"D"|"R"
---@field path string path relative to the repository root
---@field old_path? string previous path of a renamed file
---@field added? integer lines added; nil when not known, as for a binary file
---@field deleted? integer lines deleted

---Parse the output of `git diff --name-status -z`.
---@param out string
---@return twintree.Entry[]
function M.parse_name_status(out)
  local fields = vim.split(out, "\0", { plain = true })
  local entries = {}
  local i = 1
  while fields[i] and fields[i] ~= "" do
    local letter = fields[i]:sub(1, 1)
    if letter == "R" then
      table.insert(entries, {
        status = "R",
        old_path = fields[i + 1],
        path = fields[i + 2],
      })
      i = i + 3
    elseif letter == "C" then
      -- The copy source still exists, so the copy is simply a new file.
      table.insert(entries, { status = "A", path = fields[i + 2] })
      i = i + 3
    else
      local status = (letter == "A" or letter == "D") and letter or "M"
      table.insert(entries, { status = status, path = fields[i + 1] })
      i = i + 2
    end
  end
  return entries
end

---Parse the output of `git diff --numstat -z -M`.
---@param out string
---@return table<string, { added: integer, deleted: integer }> counts by path;
---  a binary file has no entry
function M.parse_numstat(out)
  local fields = vim.split(out, "\0", { plain = true })
  local counts = {}
  local i = 1
  while fields[i] and fields[i] ~= "" do
    local added, deleted, path = fields[i]:match("^([^\t]+)\t([^\t]+)\t(.*)$")
    if not added then
      break
    end
    if path == "" then
      -- A rename: the old and the new path follow as separate fields.
      path = fields[i + 2]
      i = i + 3
    else
      i = i + 1
    end
    if path and added ~= "-" then
      counts[path] = { added = tonumber(added), deleted = tonumber(deleted) }
    end
  end
  return counts
end

---Put line counts onto entries.
---@param entries twintree.Entry[]
---@param counts table<string, { added: integer, deleted: integer }>
---@return twintree.Entry[]
function M.with_counts(entries, counts)
  for _, entry in ipairs(entries) do
    local count = counts[entry.path]
    if count then
      entry.added, entry.deleted = count.added, count.deleted
    end
  end
  return entries
end

---Parse NUL-separated file paths, as printed by `git ls-files -z`.
---@param out string
---@return string[]
function M.parse_paths(out)
  local paths = vim.split(out, "\0", { plain = true, trimempty = true })
  -- git lists an untracked nested repository as a directory, `inner/`.
  return vim.tbl_filter(function(path)
    return path:sub(-1) ~= "/"
  end, paths)
end

---@param entries twintree.Entry[]
---@return twintree.Entry[]
function M.sorted(entries)
  table.sort(entries, function(a, b)
    return a.path < b.path
  end)
  return entries
end

---Add untracked files to a diff against the working tree.
---@param entries twintree.Entry[]
---@param untracked string[]
---@param line_count? fun(path: string): integer? lines of an untracked
---  file, nil when they cannot be counted
---@return twintree.Entry[]
function M.merge_untracked(entries, untracked, line_count)
  line_count = line_count or function() end
  local by_path = {}
  for _, entry in ipairs(entries) do
    by_path[entry.path] = entry
  end
  for _, path in ipairs(untracked) do
    local lines = line_count(path)
    local known = by_path[path]
    if known then
      -- Removed from the index but still on disk (`git rm --cached`). Git
      -- reports every line as deleted, which is not the difference the
      -- panes show, so the entry carries no counts.
      known.status = "M"
      known.added, known.deleted = nil, nil
    else
      table.insert(entries, {
        status = "A",
        path = path,
        added = lines,
        deleted = lines and 0 or nil,
      })
    end
  end
  return M.sorted(entries)
end

return M
