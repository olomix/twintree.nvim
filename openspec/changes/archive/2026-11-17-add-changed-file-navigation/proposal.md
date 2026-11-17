# Proposal

## Why

Going to the next changed file means leaving the code, moving in the tree
and pressing `<CR>`, and it is not possible at all while the tree is
hidden. A review needs one key for "next file" that works from the panes.

## What Changes

- Four commands move between the changed files of the current diff tab:
  `:TwintreeNextFile` and `:TwintreePrevFile`, which take a count, and
  `:TwintreeFirstFile` and `:TwintreeLastFile`. The file is shown as after
  a selection in the tree, except that the current window does not
  change.
- Default keys in normal mode: `]<C-f>` for the next file and `[<C-f>`
  for the previous one. The first and last file have no default key.
- The keys are bound only while a diff tab is the current tab. A global
  normal-mode mapping the user has on the same keys is put back when
  another tab becomes current, and works as before. Without a diff tab
  the plugin maps nothing.
- The keys are set in `setup()` and each can be turned off.
- The order is the order of the tree. Files inside a collapsed directory
  are skipped.
- At the first and the last file the commands stop and say so in one
  line. They do not cycle.
- When the panes show a file that is not in the list, for example after a
  jump to a definition, next and previous continue from the changed file
  that was shown last.
- The cursor of every window that shows the tree follows the file, also
  in a window the user made for the tree.

Why these keys: the panes show code the user browses, and the bracket
letters (`]f`, `]c`, `]m`...) are where plugins put motions over code;
one widespread configuration maps `]f` to "next function" in every code
buffer. A bracket followed by a control key is outside that namespace and
follows Neovim's own `]<C-q>`, which goes to the next file of the
quickfix list.

Not part of this change:

- Restoring a missing pane.
- Default keys for `:TwintreeToggleTree` and `:TwintreeResetLayout`.
- Overriding a buffer-local mapping another plugin has on the same keys.
- Making `]c` on the last change continue in the next file.
- Making the code that shows a file safe against a pane or the diff tab
  being closed while the file is shown. That is a weakness of every way
  of showing a file today, the new commands are no worse than `<CR>` in
  the tree, and it is described in `TODO.md` for a change of its own.

## Capabilities

### New Capabilities

- `changed-file-navigation`: moving between the changed files of a diff
  session with commands and keys, and how those keys are scoped to diff
  tabs.

### Modified Capabilities

- `diff-session`: the two requirements about the cursor of a shown file
  name the new commands next to a selection in the tree.

## Impact

- `lua/twintree/nav.lua` (new): which file is next, previous, first and
  last, showing it and reporting.
- `lua/twintree/keys.lua` (new): binding the keys for a diff tab and
  restoring the user's mappings.
- `lua/twintree/tree.lua`: the file entries in tree order, with the ones
  that are visible.
- `lua/twintree/session.lua`: the session record remembers the last
  changed file shown; `show` can leave the current window alone; the
  cursor of every tree window in the tab follows the selection.
- `lua/twintree/treeview.lua`: `first_file` uses the new list; a refresh
  that marks the shown file records it as shown last.
- `lua/twintree/config.lua`, `lua/twintree/init.lua`,
  `plugin/twintree.lua`: the `keys` option and its validation, the four
  commands, the autocommand that keeps the keys in step with the current
  tab.
- `tests/`: new specs, including cases in the real terminal.
- `README.md`, `doc/twintree.txt`, `TODO.md`.
