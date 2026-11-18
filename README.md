# twintree.nvim

[![test](https://github.com/olomix/twintree.nvim/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/olomix/twintree.nvim/actions/workflows/test.yml)

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

The diff opens with the first file of the tree shown in both panes and the
cursor in the after pane. When nothing changed, the panes are empty and the
cursor is in the tree.

A file shown for the first time, when the diff opens or when you select
it in the tree, has the cursor on its first change. When you come back to
a file, the cursor is where you left it. A file you reach by a jump keeps
the cursor of the jump.

From the shell:

```sh
nvim +Twintree
nvim +"Twintree main"
```

Neovim then starts with two tabs: the empty one it always starts with, and
the diff, which is the current tab.

In the tree:

| Key | Action |
|---|---|
| `<CR>`, double click | Show the file in both panes, or fold a directory |
| `R` | Refresh the list of changed files |

A single click and a drag are left alone: they move the cursor and select
text as in any buffer. A key you map for the `twintree` filetype replaces
the key of the plugin.

The menu of the right mouse button has three items in the tree, "Copy
relative path", "Copy absolute path" and "Copy file name", for the file or
directory you clicked. They do what `:TwintreeCopyPath` does.

Anywhere in the diff tab:

| Key or command | Action |
|---|---|
| `]<C-f>`, `:TwintreeNextFile` | Show the next changed file |
| `[<C-f>`, `:TwintreePrevFile` | Show the previous changed file |
| `:TwintreeFirstFile` | Show the first changed file |
| `:TwintreeLastFile` | Show the last changed file |
| `:TwintreeCopyPath {form}` | Copy a path to the clipboard |

`:TwintreeCopyPath` takes `relative` (the default, the path from the
repository root), `absolute` or `name`. In the tree it copies the path of
the line under the cursor, a file or a directory. Elsewhere in the diff tab
it copies the path of the file the panes show. The absolute path is the
file of the after side, or of the before side when the file exists only
there.

The files come in the order of the tree, and files inside a folded
directory are skipped. Next and previous take a count (`3]<C-f>`). At the
first and last file they stop and say "no more changed files"; they do not
start over. The window you are in stays the current one, so you can step
through the files from the tree as well. After a jump into a file that did
not change, next and previous continue from the changed file you looked at
last.

The two keys exist only while a diff tab is the current tab, in normal
mode. In every other tab a mapping of your own on those keys is back in
place. See [Keys](#keys) to change them.

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

### Files with a swap file

A file of your checkout that a pane is about to show may have a swap file.

- **The file is open in another running Neovim.** It opens as usual, and
  Neovim prints its one-line warning (`W325`). You can edit it in both; the
  second one to save is warned that the file changed on disk.
- **The swap file was left by a crash.** The plugin asks, with the facts and
  the choices of Neovim's own dialog: Open Read-Only, Edit anyway, Recover,
  Delete it, Quit, Abort.
- **You answer Quit or Abort.** The file is not opened and one line says so.
  After a selection in the tree the panes show what they showed before.
  When it was the file a diff opens with, the diff still opens, with empty
  panes and the cursor in the tree.
  After a jump in a pane, that pane keeps the file you went to, without
  diff mode, and the other pane keeps its file.

Files of the old side never use swap files.

### Closing the diff

The diff always opens in a new tab, next to the tabs you already have. To
end it, close that tab with `:tabclose`. The worktree stays cached. After
`nvim +Twintree` this leaves you in the empty tab; `:qa` quits Neovim.

When no other diff uses that worktree, the buffers of its files are wiped
out and its language server is stopped. A buffer stays when a window still
shows it, when a quickfix or location list refers to it, or when it has
unsaved changes; it goes when a later tab is closed and that is no longer
so. Files of your working directory are never touched.

If you close the other tabs, the diff is the only tab, and `:tabclose`
refuses to close the last tab. Open one with `:tabnew` and close the diff tab
from there, or quit Neovim with `:qa`.

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
  -- Keys bound while a diff tab is current; false leaves an action
  -- without a key.
  keys = {
    next_file = "]<C-f>",
    prev_file = "[<C-f>",
  },
})
```

### Keys

The first and last file have no key by default. Map the commands yourself,
for example:

```lua
vim.keymap.set("n", "]<C-g>", "<Cmd>TwintreeLastFile<CR>")
vim.keymap.set("n", "[<C-g>", "<Cmd>TwintreeFirstFile<CR>")
```

`]<C-S-f>` and `[<C-S-f>` look like the natural choice, but they only work
in a terminal that tells Ctrl+Shift+F from Ctrl+F (kitty keyboard protocol,
or tmux with `extended-keys`). Elsewhere Neovim receives `]<C-f>`, and the
key shows the next file instead of the last.

What to know about the keys of the plugin:

* Only global normal-mode mappings are touched. A mapping you made with
  `:map` keeps working in every mode; afterwards `:map` lists it as two
  entries, one for normal mode and one for the other modes.
* A buffer-local mapping on the same key, from you or another plugin, wins
  in that buffer. Choose other keys if that gets in the way.
* When you map or unmap one of the keys while a diff tab is current, the
  plugin leaves that key alone until the next call to `setup()`.
* The keys follow changes of tab that fire Neovim's tab events. After a
  change without events (`:noautocmd tabnext`), the first press of a key
  outside a diff only removes the plugin's mapping, and in a diff tab the
  keys are missing until the next change of tab. The commands always work.
* After the plugin's Lua modules are reloaded, call `setup()` again;
  until then the default keys apply.
* A value `setup()` cannot use (an empty key, the same key for both
  actions) is reported, and that call changes nothing.

## Worktrees

Each commit that is shown gets a detached worktree under
`<cache_dir>/<repository>-<hash>/<commit>`. Worktrees are kept and reused, so
reopening a diff does not check the commit out again. The language server of
a worktree runs while a diff of it is open. Worktrees appear in
`git worktree list` of your repository and lock no branch.

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

GitHub Actions runs `make test` for every pull request, for every push to
`main` and once a week, on three Neovim versions: the oldest supported
release (`nvim oldest`), the latest stable release (`nvim stable`) and
nightly (`nvim nightly`). All specs run there, also the ones that need a
terminal.

A failure of `nvim oldest` or `nvim stable` fails the run. `nvim nightly`
is informational: its check on a pull request can be red while the run is
green, and that blocks nothing.

To reproduce a red job, install the Neovim build its log names, check out
plenary.nvim at the commit named in `.github/workflows/test.yml`, and run:

```sh
PLENARY_DIR=/absolute/path/to/plenary.nvim make test
```

GitHub disables the whole workflow, for every trigger, after sixty days
without activity in the repository. Enable it again in the Actions tab or
with `gh workflow enable test.yml`.

See `:help twintree` for the full documentation.
