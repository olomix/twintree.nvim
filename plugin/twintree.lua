-- No `loaded` guard: this file is sourced again on `:Lazy reload`.

local function report(err)
  vim.notify("twintree: " .. err, vim.log.levels.ERROR)
end

vim.api.nvim_create_user_command("Twintree", function(cmd)
  local _, err = require("twintree").open(cmd.fargs)
  if err then
    report(err)
  end
end, {
  nargs = "*",
  desc = "Open a diff with browsable before and after sides",
  complete = function(arg_lead)
    local refs = require("twintree.git").ref_names(vim.fn.getcwd())
    return vim.tbl_filter(function(ref)
      return vim.startswith(ref, arg_lead)
    end, refs)
  end,
})

vim.api.nvim_create_user_command("TwintreeClean", function()
  local removed, err = require("twintree").clean()
  if not removed then
    report(err)
    return
  end
  vim.notify(("twintree: removed %d cached worktree(s)"):format(removed))
end, { desc = "Remove cached twintree worktrees of this repository" })

local group = vim.api.nvim_create_augroup("twintree", { clear = true })

-- BufNew, not BufReadPre: an existing swap file is checked before reading.
vim.api.nvim_create_autocmd("BufNew", {
  group = group,
  desc = "Open files of cached worktrees without a swap file",
  callback = function(args)
    require("twintree.worktree").disable_swap(args.buf)
  end,
})

vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
  group = group,
  desc = "Make files of cached worktrees read-only",
  callback = function(args)
    require("twintree.worktree").protect(args.buf)
  end,
})

vim.api.nvim_create_autocmd({ "BufWinEnter", "BufEnter" }, {
  group = group,
  desc = "Diff a pane only while it shows the selected file",
  callback = function()
    require("twintree.session").sync_diff()
  end,
})
