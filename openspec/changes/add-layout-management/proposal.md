# Proposal

## Why

The layout of a diff tab is set once when it opens and never maintained.
When the terminal changes width only the right pane grows or shrinks, zooming
a pane with `<C-w>|` crushes the tree for good, and closing the tree window
cannot be undone without reopening the diff. Neovim's own window commands
cover most layout needs, so the plugin should fill only the gaps they leave.

## What Changes

- Keep the width ratio of the before and after panes when the terminal is
  resized, including a resize that happened while another tab was current.
- Keep `<C-w>=` as the way to get equal panes: it resets the ratio to 50/50.
- Remember the tree width the user sets by hand and restore it after a zoom:
  `<C-w>|` in any of the three windows followed by `<C-w>=` returns to the
  tree at its remembered width with equal panes.
- Let the tree be hidden with `<C-w>c`: the session keeps working with the
  two panes and the tree content is kept.
- Add `:TwintreeToggleTree` to hide the tree or show it again.
- Add `:TwintreeResetLayout` to return a diff tab to its original view:
  exactly three windows, tree at the configured width, equal panes, the
  selected file shown again. Other windows in the tab are closed.
- Both commands report "no diff session in this tab" as a message when run
  in a tab without a diff, never a Lua traceback.
- Delete the tree buffer when its diff tab closes.
- Selecting a file while a pane window is missing reports a message that
  points to `:TwintreeResetLayout`.

Out of scope: default key mappings for the new commands, re-maximizing a
zoomed window after a terminal resize, removing worktree file buffers and
stopping the language server of the old side when a tab closes, and ending a
diff that occupies the only tab. These stay in `TODO.md`.

## Capabilities

### New Capabilities

- `diff-layout`: how the windows of a diff tab are sized and kept over time:
  pane ratio across terminal resizes, the remembered tree width and its
  restoration after a zoom, hiding and showing the tree, resetting the
  layout, and behaviour when the layout was changed by the user.

### Modified Capabilities

- `diff-session`: the "Three-column layout" requirement states that the tree
  keeps a fixed width when other windows are resized. That becomes: the tree
  keeps its width when the other windows are equalized, with sizing over
  time delegated to `diff-layout`.

## Impact

- New module `lua/twintree/layout.lua`; changes in `session.lua`,
  `treeview.lua`, `init.lua` and `plugin/twintree.lua`.
- Two new user commands and two new Lua functions (`toggle_tree`,
  `reset_layout`).
- New autocommands on `WinResized`, `VimResized`, `TabEnter` and
  `TabClosed`.
- The tree buffer changes from being wiped with its window to being kept
  until its tab closes.
- `README.md`, `doc/twintree.txt` and `TODO.md` are updated: the advice to
  keep the windows in place is replaced by the two commands.
- No new dependencies. `WinResized` needs Neovim 0.9, below the declared
  minimum of 0.11.
