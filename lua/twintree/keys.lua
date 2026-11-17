local config = require("twintree.config")
local session = require("twintree.session")

local M = {}

-- Also what tells a mapping of the plugin from one of the user.
local DESC = {
  next_file = "Twintree: next changed file",
  prev_file = "Twintree: previous changed file",
}

local NAV = { next_file = "next", prev_file = "prev" }

local ACTIONS = { "next_file", "prev_file" }

---What the plugin did to the key of an action. Kept in a global variable,
---so that a reload of the modules does not forget the user's mappings.
---@class twintree.KeyRecord
---@field lhs? string the key the plugin's mapping is on
---@field saved? table the mapping the user had on it, as nvim_get_keymap
---  gives it
---@field given_up? boolean someone else mapped the key; hands off until
---  the next setup()

---@return table<string, twintree.KeyRecord>
local function load()
  return vim.g.twintree_keys or {}
end

---@param records table<string, twintree.KeyRecord>
local function store(records)
  vim.g.twintree_keys = records
end

---The global normal-mode mapping on a key. Not `maparg()`: that returns
---a buffer-local mapping of the current buffer first.
---@param lhs string
---@return table?
local function global_mapping(lhs)
  -- The stored form, not `vim.keycode()`: a mapping on `<Tab>` is not one
  -- on `<C-I>`.
  local raw = config.raw_key(lhs)
  for _, mapping in ipairs(vim.api.nvim_get_keymap("n")) do
    if mapping.lhsraw == raw then
      return mapping
    end
  end
  return nil
end

---@param mapping? table
---@return boolean
local function is_ours(mapping)
  if not mapping then
    return false
  end
  for _, desc in pairs(DESC) do
    if mapping.desc == desc then
      return true
    end
  end
  return false
end

---Give up every action whose key no longer carries the plugin's mapping:
---the user, or another plugin, mapped or unmapped it in the meantime.
---@param records table<string, twintree.KeyRecord>
local function mark_given_up(records)
  for _, action in ipairs(ACTIONS) do
    local record = records[action]
    if record and record.lhs then
      local mapping = global_mapping(record.lhs)
      if not mapping or mapping.desc ~= DESC[action] then
        -- The saved mapping is dropped: it is older than what is there.
        records[action] = { given_up = true }
      end
    end
  end
end

---@param records table<string, twintree.KeyRecord>
---@param action string
local function release(records, action)
  local record = records[action]
  pcall(vim.keymap.del, "n", record.lhs)
  if record.saved then
    -- Normal mode only: what the user has in other modes was never
    -- touched and may have changed since.
    pcall(vim.fn.mapset, "n", false, record.saved)
  end
  records[action] = nil
end

---@param records table<string, twintree.KeyRecord>
---@param action string
---@param lhs string
local function bind(records, action, lhs)
  local saved = global_mapping(lhs)
  -- Left behind by a failure; it must never be restored as the user's.
  if is_ours(saved) then
    saved = nil
  end
  -- The callback requires the module when pressed, so that a mapping set
  -- before a reload runs the reloaded code.
  vim.keymap.set("n", lhs, function()
    require("twintree.keys").press(action)
  end, { desc = DESC[action] })
  records[action] = { lhs = lhs, saved = saved }
end

---Bind the keys when the current tab is a diff tab and release them when
---it is not. Safe to call at any time and any number of times.
function M.sync()
  local records = load()
  local wanted = session.get() and config.options.keys or {}
  mark_given_up(records)
  -- Everything is released before anything is bound: when two actions
  -- exchange their keys, no key is read while it still carries the
  -- mapping of the other action.
  for _, action in ipairs(ACTIONS) do
    local record = records[action]
    local lhs = wanted[action]
    if record and record.lhs then
      if not (lhs and config.raw_key(lhs) == config.raw_key(record.lhs)) then
        release(records, action)
      end
    end
  end
  for _, action in ipairs(ACTIONS) do
    local lhs = wanted[action]
    if lhs and not records[action] then
      -- A key Neovim refuses must not keep the record from being stored.
      pcall(bind, records, action, lhs)
    end
  end
  store(records)
end

---Apply a changed configuration: take back keys that were given up and
---bind the configured ones anew.
function M.reconfigure()
  local records = load()
  -- First, so that a key mapped a moment ago is not released as ours.
  mark_given_up(records)
  for _, action in ipairs(ACTIONS) do
    if records[action] and records[action].lhs then
      release(records, action)
    end
  end
  store({})
  M.sync()
end

---What a key of the plugin does.
---@param action string
function M.press(action)
  local count = vim.v.count1
  if not session.get() then
    -- A tab change fired no event and left the mapping behind. Releasing
    -- it is all that happens: the key press itself is not passed on.
    M.sync()
    return
  end
  require("twintree.nav").run(NAV[action], count)
end

return M
