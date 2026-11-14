local M = {}

---@class twintree.Entry
---@field status "A"|"M"|"D"|"R"
---@field path string path relative to the repository root
---@field old_path? string previous path of a renamed file

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

---Parse NUL-separated paths, as printed by `git ls-files -z`.
---@param out string
---@return string[]
function M.parse_paths(out)
  return vim.split(out, "\0", { plain = true, trimempty = true })
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
---@return twintree.Entry[]
function M.merge_untracked(entries, untracked)
  local by_path = {}
  for _, entry in ipairs(entries) do
    by_path[entry.path] = entry
  end
  for _, path in ipairs(untracked) do
    local known = by_path[path]
    if known then
      -- Removed from the index but still on disk (`git rm --cached`).
      known.status = "M"
    else
      table.insert(entries, { status = "A", path = path })
    end
  end
  return M.sorted(entries)
end

return M
