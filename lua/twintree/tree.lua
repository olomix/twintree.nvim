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

---@class twintree.LineOpts
---@field collapsed? table<string, boolean> directory paths that are folded
---@field selected? string path of the selected file
---@field dir_status? fun(path: string): "A"|"D"|nil "A" when the directory
---  exists only on the after side, "D" when only on the before side
---@field width? integer display cells available for a line
---@field icon? fun(name: string, kind: "file"|"dir_open"|"dir_closed"): string?, string?
---  glyph and highlight group; nil gives a file no icon and a directory an
---  arrow

M.EMPTY_MESSAGE = "No changes"

M.DEFAULT_WIDTH = 35
-- A cut name keeps at least this many cells before the counts give way.
M.MIN_NAME = 10

local GUIDE = "│ "
local ELLIPSIS = "…"
local ORIGIN = " ← "

local status_hl = {
  A = "TwintreeAdded",
  M = "TwintreeModified",
  D = "TwintreeDeleted",
  R = "TwintreeRenamed",
}

local function cells(text)
  return vim.fn.strdisplaywidth(text)
end

local function chars(text)
  return vim.fn.split(text, [[\zs]])
end

---The longest beginning of `text` that is at most `room` cells wide.
local function head(text, room)
  local out, used = {}, 0
  for _, char in ipairs(chars(text)) do
    local width = cells(char)
    if used + width > room then
      break
    end
    table.insert(out, char)
    used = used + width
  end
  return table.concat(out)
end

---The longest end of `text` that is at most `room` cells wide.
local function tail(text, room)
  local list = chars(text)
  local out, used = {}, 0
  for i = #list, 1, -1 do
    local width = cells(list[i])
    if used + width > room then
      break
    end
    table.insert(out, 1, list[i])
    used = used + width
  end
  return table.concat(out)
end

---Cut a name in the middle so that it fits into `room` cells and its
---extension stays visible. The result can be up to two cells short of
---`room`: one for a wide character that does not fit at each side of the cut.
---@param name string
---@param room integer
---@return string
function M.cut(name, room)
  if cells(name) <= room then
    return name
  end
  -- Measured, not assumed: the ellipsis is two cells with 'ambiwidth' double.
  local ellipsis_cells = cells(ELLIPSIS)
  if room < ellipsis_cells then
    return head(name, room)
  end
  if room == ellipsis_cells then
    return ELLIPSIS
  end

  local keep = room - ellipsis_cells
  local tail_room = math.floor(keep / 2)
  local ext = name:match("%.[^./]*$")
  if ext and ext ~= name then
    local ext_cells = cells(ext)
    if ext_cells > tail_room and ext_cells < keep then
      tail_room = ext_cells
    end
  end
  return head(name, keep - tail_room) .. ELLIPSIS .. tail(name, tail_room)
end

---Make a name safe to show on one buffer line.
local function display(name)
  return (name:gsub("%c", function(char)
    return char == "\n" and "\\n" or ("\\x%02x"):format(char:byte())
  end))
end

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

---Join pieces `{ text, highlight? }` into a line text and its highlights.
local function join(pieces)
  local text, highlights = "", {}
  for _, piece in ipairs(pieces) do
    if piece[1] ~= "" then
      if piece[2] then
        table.insert(highlights, { #text, #text + #piece[1], piece[2] })
      end
      text = text .. piece[1]
    end
  end
  return text, highlights
end

---Pieces of the right-hand block: line counts and the status letter.
local function right_block(status, added, deleted)
  local pieces = {}
  if added then
    table.insert(pieces, { " " })
    table.insert(pieces, { "+" .. added, "TwintreeAdded" })
    table.insert(pieces, { " " })
    table.insert(pieces, { "-" .. (deleted or 0), "TwintreeDeleted" })
  end
  if status then
    table.insert(pieces, { " " })
    table.insert(pieces, { status, status_hl[status] })
  end
  return pieces
end

local function width_of(pieces)
  local total = 0
  for _, piece in ipairs(pieces) do
    total = total + cells(piece[1])
  end
  return total
end

---Put a left part and a right-hand block on one line of `width` cells.
local function assemble(left, right, width)
  local pieces = vim.list_extend({}, left)
  if #right > 0 then
    local pad = width - width_of(left) - width_of(right)
    table.insert(pieces, { (" "):rep(math.max(pad, 0)) })
    vim.list_extend(pieces, right)
  end
  return join(pieces)
end

---The beginning of `pieces` that is at most `room` cells wide, each piece
---keeping its highlight.
local function head_of(pieces, room)
  local out = {}
  for _, piece in ipairs(pieces) do
    local text = head(piece[1], room)
    table.insert(out, { text, piece[2] })
    room = room - cells(text)
    if text ~= piece[1] then
      break
    end
  end
  return out
end

---A line for a window too narrow for anything but the status letter.
local function squeezed(prefix, status, width)
  if not status then
    return join(head_of(prefix, width))
  end
  if width < 2 then
    return status, { { 0, #status, status_hl[status] } }
  end
  local right = { { " " }, { status, status_hl[status] } }
  return assemble(head_of(prefix, width - 2), right, width)
end

---Where a renamed file came from: the old file name when it stayed in its
---directory, the old path otherwise.
local function origin_of(entry)
  if not entry.old_path then
    return nil
  end
  local function dirname(path)
    return path:match("^(.*)/[^/]*$") or ""
  end
  if dirname(entry.old_path) == dirname(entry.path) then
    return display(entry.old_path:match("[^/]*$"))
  end
  return display(entry.old_path)
end

local function file_line(node, depth, opts)
  local entry = node.entry
  local width = opts.width
  local prefix = { { GUIDE:rep(depth), "TwintreeGuide" } }
  local glyph, glyph_hl
  if opts.icon then
    glyph, glyph_hl = opts.icon(node.name, "file")
  end
  if glyph then
    table.insert(prefix, { glyph, glyph_hl })
    table.insert(prefix, { " " })
  end

  local name = display(node.name)
  local origin = origin_of(entry)
  local full = right_block(entry.status, entry.added, entry.deleted)
  local bare = right_block(entry.status)
  local prefix_width = width_of(prefix)
  local room_full = width - prefix_width - width_of(full)
  local room_bare = width - prefix_width - width_of(bare)
  local name_cells = cells(name)

  local left, right
  if origin and name_cells + cells(ORIGIN .. origin) <= room_full then
    left = { { name }, { ORIGIN .. origin, "TwintreeOrigin" } }
    right = full
  elseif name_cells <= room_full then
    left, right = { { name } }, full
  elseif entry.added and room_full >= math.min(M.MIN_NAME, name_cells) then
    left, right = { { M.cut(name, room_full) } }, full
  elseif room_bare >= 1 then
    left, right = { { M.cut(name, room_bare) } }, bare
  end

  local text, highlights
  if left then
    text, highlights = assemble(vim.list_extend(prefix, left), right, width)
  else
    text, highlights = squeezed(prefix, entry.status, width)
  end
  return {
    text = text,
    type = "file",
    path = node.path,
    entry = entry,
    selected = node.path == opts.selected or nil,
    highlights = highlights,
  }
end

local function dir_line(node, depth, is_collapsed, status, opts)
  local width = opts.width
  local kind = is_collapsed and "dir_closed" or "dir_open"
  local glyph, glyph_hl
  if opts.icon then
    glyph, glyph_hl = opts.icon(node.name, kind)
  end
  if not glyph then
    glyph, glyph_hl = is_collapsed and "▸" or "▾", "TwintreeDirectory"
  end
  local prefix = {
    { GUIDE:rep(depth), "TwintreeGuide" },
    { glyph, glyph_hl },
    { " " },
  }
  local right = right_block(status)
  local room = width - width_of(prefix) - width_of(right)

  local text, highlights
  if room >= 2 then
    -- The slash is not part of what gets cut.
    local name = M.cut(display(node.name), room - 1) .. "/"
    table.insert(prefix, { name, "TwintreeDirectory" })
    text, highlights = assemble(prefix, right, width)
  else
    text, highlights = squeezed(prefix, status, width)
  end
  return {
    text = text,
    type = "dir",
    path = node.path,
    status = status,
    highlights = highlights,
  }
end

---The changed files in the order the tree lists them.
---@param entries twintree.Entry[]
---@param collapsed? table<string, boolean> directory paths that are folded
---@return { entry: twintree.Entry, visible: boolean }[] visible is false
---  for a file inside a folded directory
function M.files(entries, collapsed)
  collapsed = collapsed or {}
  local files = {}
  local function walk(node, visible)
    for _, child in ipairs(node.children) do
      if child.type == "dir" then
        walk(child, visible and collapsed[child.path] ~= true)
      else
        table.insert(files, { entry = child.entry, visible = visible })
      end
    end
  end
  walk(M.build(entries), true)
  return files
end

---Flatten the tree into display lines.
---@param entries twintree.Entry[]
---@param opts? twintree.LineOpts
---@return twintree.Line[]
function M.lines(entries, opts)
  if #entries == 0 then
    return { { text = M.EMPTY_MESSAGE, type = "message", highlights = {} } }
  end
  opts = vim.tbl_extend("keep", opts or {}, {
    collapsed = {},
    width = M.DEFAULT_WIDTH,
  })
  opts.width = math.max(opts.width, 1)

  local lines = {}
  local function walk(node, depth)
    for _, child in ipairs(node.children) do
      if child.type == "dir" then
        local is_collapsed = opts.collapsed[child.path] == true
        local status = opts.dir_status and opts.dir_status(child.path)
        table.insert(lines, dir_line(child, depth, is_collapsed, status, opts))
        if not is_collapsed then
          walk(child, depth + 1)
        end
      else
        table.insert(lines, file_line(child, depth, opts))
      end
    end
  end
  walk(M.build(entries), 0)
  return lines
end

return M
