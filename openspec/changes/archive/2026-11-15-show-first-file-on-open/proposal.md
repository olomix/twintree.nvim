# Proposal

## Why

A session opens with two empty panes, and the user has to press `<CR>` in
the tree before anything is compared. The first thing a diff viewer should
show is a diff.

## What Changes

- When a session opens and the diff has changed files, the first file of
  the tree is shown in both panes, as if the user had selected it: diff
  mode in both panes, its line marked in the tree, cursor in the after
  pane.
- "First" means the top file line of the tree, not the first file git
  reported.
- When the diff has no changed files, the session opens as today: empty
  panes, cursor in the tree.
- When the first file is not opened (a swap file prompt answered with Quit
  or Abort, a leftover swap file without a user interface, a pane closed
  while the session opens), the session still opens with empty panes and
  the cursor in the tree, and one line says why.
- A swap file prompt can therefore appear during `:Twintree` itself.

Not part of this change: where the cursor lands inside the file (it stays
at the position Neovim gives the buffer), and showing a file when a
refresh brings the first changes into a session that opened empty.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `diff-session`: a new requirement that the first changed file is shown
  when a session opens; the "Layout after opening" scenario no longer
  states that the cursor is in the tree window.

## Impact

- `lua/twintree/init.lua`: `open` shows the first file after the tree is
  filled, and returns the tab together with a message when the file was
  not opened. It records the layout again after the cursor moved to the
  after pane, so that a diff opened in a narrow terminal still gets its
  layout back when the terminal is widened.
- `lua/twintree/treeview.lua`: a way to get the first file of the tree.
- `tests/`: new specs for the behaviour; existing specs that rely on empty
  panes or on the cursor being in the tree after `open` need their setup
  adjusted.
- `README.md`, `doc/twintree.txt`, `TODO.md`.
