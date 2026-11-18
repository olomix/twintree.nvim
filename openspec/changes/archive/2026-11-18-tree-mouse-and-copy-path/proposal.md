# Proposal

## Why

The tree of changed files answers only to the keyboard: a click moves the
cursor and nothing more. Someone who reaches for the mouse cannot open a
file or fold a directory with it. There is also no way to get the path of
a changed file out of the tree, for a git command, a review comment or
another program, short of typing it.

## What Changes

- A double click on a line of the tree does what `<CR>` does: it shows
  the file, or folds or unfolds the directory. A single click and a drag
  are left to Neovim, so the cursor moves and text is selected as before.
- A new command, `:TwintreeCopyPath {relative|absolute|name}`, copies the
  path of a changed file or directory to the clipboard. In the tree it
  takes the line under the cursor; elsewhere in the diff tab it takes the
  file the panes show, also one the tree does not list.
- The menu of the right mouse button gets three items in the tree, "Copy
  relative path", "Copy absolute path" and "Copy file name". They are
  there only on a file or directory line of the tree and nowhere else.
- A key the user maps for the `twintree` filetype now wins over the
  plugin's key in the tree. Until now the plugin's `<CR>` replaced it.

Not part of this change:

- A default key for the command; it can be mapped by the user.
- Other menu items, such as opening a file or refreshing the tree.
- A submenu: the menu of the terminal Neovim has one level.
- The menu items in visual mode, and a triple click; both keep what
  Neovim does.
- Changing `'mousemodel'` or `'mouse'`. With a `'mousemodel'` that shows
  no menu, there is none, and the command still works.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `changed-files-tree`: five new requirements, for the double click, the
  user's own keys in the tree, the command that copies a path, what it
  acts on, and the menu items.

## Impact

- `lua/twintree/treeview.lua`: the mouse mapping, and what the line under
  the cursor stands for.
- A new module for the path forms and the copying, a function in
  `lua/twintree/init.lua`, the command and a `MenuPopup` autocommand in
  `plugin/twintree.lua`.
- `tests/`: new specs, some of them on a real terminal screen; a
  clipboard for tests in `tests/minimal_init.lua`, so that no spec writes
  the system clipboard.
- `README.md`, `doc/twintree.txt`: the mouse, the command, the menu.
- `TODO.md`: the item about the mouse click goes.
