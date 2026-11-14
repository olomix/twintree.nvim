# twintree.nvim

A Neovim diff viewer where both sides of the diff are browsable code.

Diff tools usually show only the changed hunks, or put the old version into a
scratch buffer where the language server does not work. twintree.nvim checks
the old version out into a git worktree, so both sides are real files:
go-to-definition, references and hover work on the old code and on the new
code independently.

A diff is a tab with three columns: the tree of changed files, the version
before and the version after.

This is a prototype.

## Requirements

- Neovim 0.11 or newer
- git

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ "olomix/twintree.nvim" }
```

Calling `setup()` is optional.

## Usage

| Command | Before | After |
|---|---|---|
| `:Twintree` | `HEAD` | working tree |
| `:Twintree rev1` | merge-base of `rev1` and `HEAD` | working tree |
| `:Twintree rev1 rev2` | merge-base of `rev1` and `rev2` | `rev2` |

The merge-base is always used, as in `git diff rev1...rev2`. `:Twintree main`
shows what your branch changed since it left `main`.

From the shell, the diff uses the first tab:

```sh
nvim +Twintree
nvim +"Twintree main"
```

In the tree:

| Key | Action |
|---|---|
| `<CR>` | Show the file in both panes, or fold a directory |
| `R` | Refresh the list of changed files |

A directory that exists on one side only is marked after its name, in the
colour of that status: `A` when it is missing before, `D` when it is missing
after.

Files are shown in full; unchanged lines are not folded. Press `zi` in a
pane to switch folding on and see only the changes with context.

The panes are normal windows. Jump to a definition and diff mode is switched
off in that pane; return to the file and it is switched on again. When the
after side is the working tree it is your checkout and can be edited.
Worktree files are read-only.

Close the tab to end the diff.

## Configuration

```lua
require("twintree").setup({
  tree_width = 35,
  -- Default: stdpath("cache") .. "/twintree"
  cache_dir = nil,
})
```

## Worktrees

Each commit that is shown gets a detached worktree under
`<cache_dir>/<repository>-<hash>/<commit>`. Worktrees are kept and reused, so
reopening a diff is fast and language servers keep their index. They appear
in `git worktree list` of your repository and lock no branch.

`:TwintreeClean` removes the cached worktrees of the current repository,
except those used by an open diff.

## Limitations

- Files that git does not track are missing in worktrees (`node_modules`,
  virtual environments, build output), so some language servers work only
  partly on the old side.
- Checking out a worktree for the first time blocks Neovim until git is done.
- Submodules, Git LFS and sparse checkouts are not handled.

## Development

Tests need [plenary.nvim](https://github.com/nvim-lua/plenary.nvim). It is
looked up in `$PLENARY_DIR`, then in `stdpath("data")/lazy/plenary.nvim`.

```sh
make test
```

See `:help twintree` for the full documentation.
