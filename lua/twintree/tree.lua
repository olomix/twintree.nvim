local M = {}

---@class twintree.Node
---@field name string
---@field path string
---@field type "dir"|"file"
---@field children? twintree.Node[]
---@field entry? twintree.Entry

---@class twintree.Line
---@field text string
---@field type "dir"|"file"|"message"
---@field path? string
---@field entry? twintree.Entry
---@field status? "A"|"D" set on a directory that exists on one side only
---@field selected? boolean
---@field highlights { [1]: integer, [2]: integer, [3]: string }[] byte ranges

M.EMPTY_MESSAGE = "No changes"

local status_hl = {
  A = "TwintreeAdded",
  M = "TwintreeModified",
  D = "TwintreeDeleted",
  R = "TwintreeRenamed",
}

local function sort_nodes(nodes)
  table.sort(nodes, function(a, b)
    if a.type ~= b.type then
      return a.type == "dir"
    end
    return a.name < b.name
  end)
end

---Merge a directory with its only child while that child is a directory.
local function collapse_chain(node)
  while #node.children == 1 and node.children[1].type == "dir" do
    local child = node.children[1]
    node.name = node.name .. "/" .. child.name
    node.path = child.path
    node.children = child.children
  end
end

local function finish(node, is_root)
  if not is_root then
    collapse_chain(node)
  end
  for _, child in ipairs(node.children) do
    if child.type == "dir" then
      finish(child, false)
    end
  end
  sort_nodes(node.children)
end

---@param entries twintree.Entry[]
---@return twintree.Node root
function M.build(entries)
  local root = { name = "", path = "", type = "dir", children = {} }
  local dirs = { [""] = root }

  for _, entry in ipairs(entries) do
    local parts = vim.split(entry.path, "/", { plain = true })
    local parent = root
    for i = 1, #parts - 1 do
      local path = table.concat(parts, "/", 1, i)
      local dir = dirs[path]
      if not dir then
        dir = { name = parts[i], path = path, type = "dir", children = {} }
        dirs[path] = dir
        table.insert(parent.children, dir)
      end
      parent = dir
    end
    table.insert(parent.children, {
      name = parts[#parts],
      path = entry.path,
      type = "file",
      entry = entry,
    })
  end

  finish(root, true)
  return root
end

local function dir_line(node, depth, is_collapsed, status)
  local indent = ("  "):rep(depth)
  local text = indent .. (is_collapsed and "▸ " or "▾ ") .. node.name .. "/"
  local highlights = { { #indent, #text, "TwintreeDirectory" } }
  if status then
    text = text .. " " .. status
    table.insert(highlights, { #text - 1, #text, status_hl[status] })
  end
  return {
    text = text,
    type = "dir",
    path = node.path,
    status = status,
    highlights = highlights,
  }
end

local function file_line(node, depth, selected)
  local indent = ("  "):rep(depth)
  local entry = node.entry
  local text = indent .. entry.status .. " " .. node.name
  if entry.old_path then
    text = text .. " ← " .. entry.old_path
  end
  return {
    text = text,
    type = "file",
    path = node.path,
    entry = entry,
    selected = node.path == selected or nil,
    highlights = { { #indent, #indent + 1, status_hl[entry.status] } },
  }
end

---Flatten the tree into display lines.
---@param entries twintree.Entry[]
---@param collapsed? table<string, boolean> directory paths that are folded
---@param selected? string path of the selected file
---@param dir_status? fun(path: string): "A"|"D"|nil "A" when the directory
---  exists only on the after side, "D" when only on the before side
---@return twintree.Line[]
function M.lines(entries, collapsed, selected, dir_status)
  if #entries == 0 then
    return { { text = M.EMPTY_MESSAGE, type = "message", highlights = {} } }
  end
  collapsed = collapsed or {}

  local lines = {}
  local function walk(node, depth)
    for _, child in ipairs(node.children) do
      if child.type == "dir" then
        local is_collapsed = collapsed[child.path] == true
        local status = dir_status and dir_status(child.path)
        table.insert(lines, dir_line(child, depth, is_collapsed, status))
        if not is_collapsed then
          walk(child, depth + 1)
        end
      else
        table.insert(lines, file_line(child, depth, selected))
      end
    end
  end
  walk(M.build(entries), 0)
  return lines
end

return M
