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
- Optional: [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons)
  or [mini.icons](https://github.com/echasnovski/mini.icons), with a Nerd
  Font, for icons in the tree

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

A line of the tree shows the file's icon, its name, the lines added and
deleted, and its status at the right edge:

```
▾ commons/
│ json.go                  +9 -4 M
│ json_test.go           +23 -18 M
▾ db_migrations/ams/             A
│ kz_028_prom…_events.sql +40 -0 A
▾ pkg/
│ client.go ← api.go      +12 -3 R
```

- **Status:** `A` added, `M` modified, `D` deleted, `R` renamed, each in its
  own colour. A directory that exists on one side only carries `A` or `D` in
  the same column.
- **Line counts:** untracked files count as all lines added. Binary files
  show no counts.
- **Icons:** shown when an icon plugin is installed; directories then get
  folder glyphs in place of the arrows.
- **Long names** are cut in the middle, so the beginning and the extension
  stay visible. Widen the tree to see more; it is redrawn for its width.
- **Renamed files** show where they came from when there is room: the old
  file name for a rename within a directory, the old path otherwise.

As the tree gets narrower, a line gives up the rename origin first, then the
middle of the name, then the line counts. The status letter always stays.

Files are shown in full; unchanged lines are not folded. Press `zi` in a
pane to switch folding on and see only the changes with context.

The panes are normal windows, and they stay a diff wherever you go. Jump to
a definition or a reference, open a quickfix entry or `:edit` a file in one
pane, and the other pane shows the same file from its side. This also works
for files that did not change, which then show no differences. The file is
marked in the tree when it is one of the changed files.

- A file always goes to the pane of its side. An entry of the before side
  opened while the cursor is in the after pane appears in the before pane,
  and the cursor follows it.
- A file outside both sides, such as a dependency, is shown in both panes.
- A buffer that is not a file, such as a terminal, gets a plain pane.
- The tree window only shows the tree; `:edit` there is refused, and a
  quickfix entry opened from it goes to the panes.

To keep another file next to the diff, open a window of your own with
`:split`. Such a window does not follow and is not part of the diff.

When the after side is the working tree it is your checkout and can be
edited. Worktree files are read-only.

### Closing the diff

The diff lives in its own tab, opened next to the tabs you already have. To
end it, close that tab with `:tabclose`. The worktree stays cached.

When the diff is the only tab, as after `nvim +Twintree`, `:tabclose` refuses
to close the last tab; quit Neovim with `:qa`.

### Windows and layout

The diff tab is yours: resize, zoom, split and close windows as in any other
tab. Neovim's own window commands do most of the work, and the plugin fills
the gaps.

| Key or command | Action |
|---|---|
| `<C-w>t` | Go to the tree (the top-left window) |
| `<C-w>p` | Go back to the window you came from |
| `<C-w>=` | Make the before and after panes equally wide |
| `<C-w>\|` | Maximize the current window; `<C-w>=` brings the layout back |
| `<C-w>c` in the tree | Hide the tree |
| `:TwintreeToggleTree` | Hide the tree, or show it again |
| `:TwintreeResetLayout` | Return the tab to tree, before and after |

What the plugin keeps for you:

- **Pane ratio.** When the terminal is resized, the before and after panes
  keep their ratio. It starts at half and half; resize a pane and that ratio
  is kept; `<C-w>=` sets it back to half and half.
- **Tree width.** The tree keeps the width you give it. `<C-w>=` leaves it
  alone, and after a zoom with `<C-w>|` it returns to that width. Do not
  squeeze the tree to one column to hide it; hide it instead.
- **Hidden tree.** While the tree is hidden the diff keeps working, and the
  tree comes back with the same folds and selection. `<C-w>t` then goes to
  the before pane.

`:TwintreeResetLayout` is the way out when the tab got into a state you do
not want: it closes every other window of the tab (their buffers stay
loaded), puts the tree back at its configured width, makes the panes equal
and shows the selected file again. If a pane is missing when you select a
file, the plugin tells you to run it.

Both commands report an error when the current tab has no diff.

## Configuration

```lua
require("twintree").setup({
  tree_width = 35,
  -- Default: stdpath("cache") .. "/twintree"
  cache_dir = nil,
  -- Icons in the tree, when an icon plugin is installed.
  icons = true,
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
- Submodules, Git LFS and sparse checkouts are not handled. An untracked
  nested git repository is not listed.

## Development

Tests need [plenary.nvim](https://github.com/nvim-lua/plenary.nvim). It is
looked up in `$PLENARY_DIR`, then in `stdpath("data")/lazy/plenary.nvim`.

```sh
make test
```

See `:help twintree` for the full documentation.
