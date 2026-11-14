local M = {}

---@class twintree.Config
---@field tree_width integer Width of the changed-files tree window.
---@field cache_dir? string Directory for cached worktrees.
local defaults = {
  tree_width = 35,
  cache_dir = nil,
}

M.options = vim.deepcopy(defaults)

---@param opts? twintree.Config
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", defaults, opts or {})
end

---@return string
function M.cache_dir()
  local dir = M.options.cache_dir
    or vim.fs.joinpath(vim.fn.stdpath("cache"), "twintree")
  return vim.fs.normalize(dir)
end

return M
