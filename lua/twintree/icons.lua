local config = require("twintree.config")

local M = {}

-- Nerd Font folder glyphs. Fixed, so that an open and a folded directory
-- differ with either icon plugin; nvim-web-devicons has no folder icons.
M.FOLDER_OPEN = "\u{f07c}"
M.FOLDER_CLOSED = "\u{f07b}"

---@return (fun(name: string): string?, string?)?
local function file_icons()
  local ok, mini = pcall(require, "mini.icons")
  if ok and type(mini) == "table" and type(mini.get) == "function" then
    return function(name)
      local found, glyph, hl = pcall(mini.get, "file", name)
      if found then
        return glyph, hl
      end
    end
  end

  local devicons
  ok, devicons = pcall(require, "nvim-web-devicons")
  if ok and type(devicons) == "table" and type(devicons.get_icon) == "function" then
    return function(name)
      local ext = name:match("%.([^.]+)$")
      local found, glyph, hl = pcall(devicons.get_icon, name, ext, { default = true })
      if found then
        return glyph, hl
      end
    end
  end
  return nil
end

---The icon function for the tree, or nil when icons are switched off or no
---icon plugin is installed. Looked up at each call, so that installing a
---plugin needs no restart.
---@return (fun(name: string, kind: "file"|"dir_open"|"dir_closed"): string?, string?)?
function M.source()
  if not config.options.icons then
    return nil
  end
  local file_icon = file_icons()
  if not file_icon then
    return nil
  end
  return function(name, kind)
    if kind == "file" then
      return file_icon(name)
    elseif kind == "dir_open" then
      return M.FOLDER_OPEN, "TwintreeDirectory"
    end
    return M.FOLDER_CLOSED, "TwintreeDirectory"
  end
end

return M
