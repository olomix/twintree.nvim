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

vim.api.nvim_create_user_command("TwintreeToggleTree", function()
  local _, err = require("twintree").toggle_tree()
  if err then
    report(err)
  end
end, { desc = "Hide or show the tree of changed files" })

vim.api.nvim_create_user_command("TwintreeResetLayout", function()
  local _, err = require("twintree").reset_layout()
  if err then
    report(err)
  end
end, { desc = "Return the diff tab to tree, before and after windows" })

for name, action in pairs({ TwintreeNextFile = "next", TwintreePrevFile = "prev" }) do
  vim.api.nvim_create_user_command(name, function(cmd)
    require("twintree.nav").run(action, cmd.count)
  end, {
    count = 1,
    desc = ("Show the %s changed file of the diff"):format(action == "next" and "next" or "previous"),
  })
end

for name, action in pairs({ TwintreeFirstFile = "first", TwintreeLastFile = "last" }) do
  vim.api.nvim_create_user_command(name, function()
    require("twintree.nav").run(action)
  end, { desc = ("Show the %s changed file of the diff"):format(action) })
end

vim.api.nvim_create_user_command("TwintreeCopyPath", function(cmd)
  local text, err = require("twintree").copy_path(cmd.args ~= "" and cmd.args or nil)
  if not text then
    report(err)
    return
  end
  vim.notify("twintree: copied " .. require("twintree.tree").display(text))
end, {
  nargs = "?",
  desc = "Copy the path of a changed file: relative, absolute or name",
  complete = function(arg_lead)
    return vim.tbl_filter(function(form)
      return vim.startswith(form, arg_lead)
    end, require("twintree.path").FORMS)
  end,
})

local group = vim.api.nvim_create_augroup("twintree", { clear = true })

-- Items left in the global menu by the code that was loaded before.
require("twintree.menu").remove()

vim.api.nvim_create_autocmd("MenuPopup", {
  group = group,
  pattern = "n",
  desc = "Offer to copy the path of a tree line in the right-click menu",
  callback = function()
    require("twintree.menu").refresh()
  end,
})

-- `:popup` shows the menu without MenuPopup, so the items go with the tree.
vim.api.nvim_create_autocmd("BufLeave", {
  group = group,
  pattern = "twintree://tree/*",
  desc = "Take the copy items out of the right-click menu",
  callback = function()
    require("twintree.menu").remove()
  end,
})

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
  desc = "Show in both panes the file one of them is taken to",
  -- Nested, so that the file loaded into the other pane gets its filetype
  -- and the read-only protection of cached worktrees.
  nested = true,
  callback = function()
    require("twintree.session").follow()
  end,
})

vim.api.nvim_create_autocmd("WinNew", {
  group = group,
  desc = "Keep a window split off a pane out of the diff",
  callback = function()
    require("twintree.session").undiff_new_window()
  end,
})

-- TabEnter: a terminal resize while another tab was current is only
-- applied to this tab's windows when it is entered.
vim.api.nvim_create_autocmd({ "WinResized", "VimResized", "TabEnter" }, {
  group = group,
  desc = "Keep the layout of a diff tab",
  callback = function()
    require("twintree.layout").sync()
    -- Lines are padded to the width of the tree window.
    require("twintree.treeview").redraw_if_resized()
  end,
})

-- Also after a tab was closed: the tab that becomes current is entered.
vim.api.nvim_create_autocmd("TabEnter", {
  group = group,
  desc = "Bind the keys of the plugin in a diff tab, release them elsewhere",
  callback = function()
    require("twintree.keys").sync()
  end,
})

vim.api.nvim_create_autocmd("TabClosed", {
  group = group,
  desc = "Release what only a closed diff tab used",
  -- Without it Neovim fires no buffer events for the buffers wiped out here.
  nested = true,
  callback = function()
    require("twintree.treeview").sweep()
    require("twintree.worktree").release(require("twintree.session").pane_roots())
  end,
})

vim.api.nvim_create_autocmd("OptionSet", {
  group = group,
  pattern = { "number", "relativenumber", "numberwidth", "signcolumn", "foldcolumn" },
  desc = "Redraw the tree when its text area changes without a resize",
  callback = function()
    require("twintree.treeview").redraw_if_resized()
  end,
})

vim.api.nvim_create_autocmd("SwapExists", {
  group = group,
  desc = "Ask about a swap file of a file the plugin puts into a pane",
  callback = function()
    require("twintree.swap").on_swap_exists()
  end,
})
