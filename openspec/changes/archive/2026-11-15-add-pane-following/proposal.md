# Proposal

## Why

Today a pane leaves diff mode as soon as it shows any file other than the one
selected in the tree. Following a reference, a definition or a quickfix entry
in the before pane therefore ends the comparison: the before pane shows the
new file as plain text and the after pane stays on the old one. To compare
again the user has to find the file in the tree, which is impossible when the
file is not among the changed files. The plugin has both versions of every
file on disk, so it can keep the comparison going wherever the user
navigates.

## What Changes

- **BREAKING** When a file enters the before or the after pane by any kind
  of navigation, the other pane shows the same file from its own side and
  both panes stay in diff mode. This replaces the current rule that a pane
  leaves diff mode when it leaves the selected file. There is no option to
  switch it off.
- The counterpart is found through the changed files, so a renamed file is
  paired with its other name. A file that does not exist on the other side
  is paired with the empty placeholder.
- A file outside both sides (a dependency, the standard library) is shown as
  the same buffer in both panes, in diff mode.
- Buffers that are not files (terminal, help, scratch buffers) are left
  alone: the pane leaves diff mode, as today.
- A file always ends up in the pane of the side it belongs to. When a jump
  puts a file of the before side into the after pane, or the reverse, the
  file is moved to its own pane together with the cursor, and the pane where
  it landed shows the counterpart.
- The tree window refuses to show any buffer other than the tree, so a
  quickfix jump made from the tree opens in a pane.
- A window the user splits off a pane is not part of the diff: it leaves
  diff mode as it is created, so a file opened there does not become a
  third side of the comparison.
- The mark in the tree follows the file the panes show. It disappears while
  the panes show a file that is not among the changed files.
- `:TwintreeResetLayout` and a tree refresh keep the file the panes show,
  also when the user reached it by navigation.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `diff-session`: the requirement "Panes stay browsable" changes from
  "diff mode only on the selected file" to "the other pane follows"; new
  requirements cover files outside both sides, non-file buffers, placing a
  file in the pane of its side, the tree window keeping the tree, a missing
  pane, and what the selected file of a session is.
- `changed-files-tree`: the mark of the selected file follows navigation in
  the panes, and a refresh no longer ends the comparison when the shown file
  is not listed.
- `diff-layout`: resetting the layout brings back a file that was reached by
  navigation and is not among the changed files.

## Impact

- `lua/twintree/session.lua`: pairing of files across sides, the
  buffer-entered handler that replaces `sync_diff`, the tree window option.
- `lua/twintree/treeview.lua`: moving the mark, refresh without clearing the
  panes.
- `lua/twintree/init.lua`: layout reset restores the shown pair.
- `plugin/twintree.lua`: the buffer autocommand becomes nested, and a new
  one handles new windows.
- `lua/twintree/worktree.lua`: path resolution is shared with the session.
- Tests: `tests/session_spec.lua` and `tests/layout_ui_spec.lua` contain
  cases that rely on the old rule or put another buffer into the tree
  window; a new spec file covers following.
- `README.md` and `doc/twintree.txt`: the sections that say diff mode is
  switched off after a jump.
- No new dependencies. `winfixbuf` needs Neovim 0.10; the plugin already
  requires 0.11.
