local M = {}

local SEPARATOR = "-twintree-"
local ITEMS = {
  { name = "Copy relative path", form = "relative" },
  { name = "Copy absolute path", form = "absolute" },
  { name = "Copy file name", form = "name" },
}

local function escaped(name)
  return (name:gsub(" ", "\\ "))
end

---Normal-mode items of the menu of the right mouse button, by name.
---@return table<string, string> rhs
local function popup_items()
  -- menu_get() raises when the user removed the menu.
  local ok, menus = pcall(vim.fn.menu_get, "PopUp", "n")
  local items = {}
  if ok and menus[1] then
    for _, item in ipairs(menus[1].submenus or {}) do
      local mapping = item.mappings and item.mappings.n
      items[item.name] = mapping and mapping.rhs or ""
    end
  end
  return items
end

---Whether an item of the menu is one this plugin defined.
local function is_own(name, rhs)
  return name == SEPARATOR or rhs:find("TwintreeCopyPath", 1, true) ~= nil
end

---Take the plugin's items out of the menu of the right mouse button.
function M.remove()
  local items = popup_items()
  local names = { SEPARATOR }
  for _, item in ipairs(ITEMS) do
    table.insert(names, item.name)
  end
  for _, name in ipairs(names) do
    if items[name] and is_own(name, items[name]) then
      pcall(vim.cmd, "nunmenu PopUp." .. escaped(name))
    end
  end
end

local function add()
  local items = popup_items()
  for i, item in ipairs(ITEMS) do
    -- An item of the user with the same name stays theirs.
    if not items[item.name] then
      vim.cmd(
        ("nnoremenu 500.%d PopUp.%s <Cmd>TwintreeCopyPath %s<CR>"):format(
          9 + i,
          escaped(item.name),
          item.form
        )
      )
    end
  end
  vim.cmd(("nnoremenu 500.%d PopUp.%s <Nop>"):format(10 + #ITEMS, SEPARATOR))
end

---Put the copy items into the menu when it opens on a file or directory
---line of a tree, and take them out everywhere else.
function M.refresh()
  local ok, err = pcall(function()
    M.remove()
    -- With 'mousemodel' "popup" the click can be in another window; on the
    -- separator of the window it is on no line.
    local mouse = vim.fn.getmousepos()
    if
      mouse.winid == vim.api.nvim_get_current_win()
      and mouse.line > 0
      and require("twintree.path").on_tree_line()
    then
      add()
    end
  end)
  if not ok then
    vim.notify("twintree: " .. tostring(err), vim.log.levels.ERROR)
  end
end

return M
