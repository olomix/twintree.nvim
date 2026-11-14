local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local plenary = vim.env.PLENARY_DIR
  or vim.fs.joinpath(vim.fn.stdpath("data"), "lazy", "plenary.nvim")

vim.opt.runtimepath:prepend(plenary)
vim.opt.runtimepath:prepend(root)
-- Makes `require("tests.helpers")` resolvable.
package.path = root .. "/?.lua;" .. package.path

vim.o.swapfile = false

-- Keep the user's git config (signing, hooks, includes) out of test repos.
vim.env.GIT_CONFIG_GLOBAL = "/dev/null"
vim.env.GIT_CONFIG_NOSYSTEM = "1"
vim.env.GIT_AUTHOR_NAME = "Test"
vim.env.GIT_AUTHOR_EMAIL = "test@example.com"
vim.env.GIT_COMMITTER_NAME = "Test"
vim.env.GIT_COMMITTER_EMAIL = "test@example.com"

-- plenary starts spec processes with --noplugin.
vim.cmd.runtime("plugin/plenary.vim")
vim.cmd.runtime("plugin/twintree.lua")
