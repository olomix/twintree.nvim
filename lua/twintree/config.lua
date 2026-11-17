local M = {}

---@class twintree.Keys
---@field next_file string|false Key for the next changed file.
---@field prev_file string|false Key for the previous changed file.

---@class twintree.Config
---@field tree_width integer Width of the changed-files tree window.
---@field cache_dir? string Directory for cached worktrees.
---@field icons boolean Show icons when an icon plugin is installed.
---@field keys twintree.Keys Normal-mode keys bound while a diff tab is
---  current; `false` leaves an action without a key.
local defaults = {
  tree_width = 35,
  cache_dir = nil,
  icons = true,
  keys = {
    next_file = "]<C-f>",
    prev_file = "[<C-f>",
  },
}

M.options = vim.deepcopy(defaults)

local raw_keys = {}

---The form in which Neovim stores a key as the left-hand side of a
---mapping. `vim.keycode()` is not that form: it makes `<C-I>` and `<Tab>`
---one key, which Neovim maps separately.
---The form depends on the leader keys of the moment for a key written
---with `<Leader>`, so it must not be remembered across a change of them.
---@param key string
---@return string? raw nil when Neovim cannot map the key
---@return string? err
function M.raw_key(key)
  local cached = ("%s\n%s\n%s"):format(
    key,
    tostring(vim.g.mapleader),
    tostring(vim.g.maplocalleader)
  )
  if raw_keys[cached] then
    return raw_keys[cached]
  end
  -- Asking Neovim is the only complete rule: map the key where it
  -- disturbs nothing and read it back.
  local buf = vim.api.nvim_create_buf(false, true)
  local ok, err = pcall(vim.api.nvim_buf_set_keymap, buf, "n", key, "", {})
  local mapping = ok and vim.api.nvim_buf_get_keymap(buf, "n")[1]
  vim.api.nvim_buf_delete(buf, { force = true })
  if not mapping then
    return nil, tostring(err):match("[^\n]+")
  end
  raw_keys[cached] = mapping.lhsraw
  return mapping.lhsraw
end

---Why the `keys` of a call to `setup()` cannot be used, if they cannot.
---@param keys any
---@return string?
local function keys_problem(keys)
  if keys == nil then
    return nil
  end
  if type(keys) ~= "table" then
    return "keys has to be a table"
  end
  for action, key in pairs(keys) do
    if defaults.keys[action] == nil then
      return ("keys has no action %s"):format(vim.inspect(action))
    end
    if key ~= false and (type(key) ~= "string" or key == "") then
      return ("keys.%s has to be a key or false"):format(action)
    end
    if key then
      local _, err = M.raw_key(key)
      if err then
        return ("keys.%s cannot be mapped: %s"):format(action, err)
      end
    end
  end
  -- As they would be in use: a key of the call can collide with a default.
  local merged = vim.tbl_extend("force", defaults.keys, keys)
  local taken = {}
  local actions = vim.tbl_keys(merged)
  table.sort(actions)
  for _, action in ipairs(actions) do
    local key = merged[action]
    if key then
      -- `]<C-f>` and `]<c-f>` are one key.
      local raw = M.raw_key(key)
      if taken[raw] then
        return ("keys.%s and keys.%s are the same key"):format(taken[raw], action)
      end
      taken[raw] = action
    end
  end
  return nil
end

---Take the options of a call to `setup()`. A call with a value that
---cannot be used changes nothing.
---@param opts? twintree.Config
---@return boolean ok
---@return string? err
function M.setup(opts)
  opts = opts or {}
  local problem = keys_problem(opts.keys)
  if problem then
    return false, problem
  end
  M.options = vim.tbl_deep_extend("force", defaults, opts)
  return true
end

---@return string
function M.cache_dir()
  local dir = M.options.cache_dir
    or vim.fs.joinpath(vim.fn.stdpath("cache"), "twintree")
  return vim.fs.normalize(dir)
end

return M
