# Tasks

## 1. Record the compared pair

- [x] 1.1 Add `state.pair` (`before`, `after`) in
  `lua/twintree/session.lua`, filled from `selected` in `session.get` for a
  session saved without it; verify with a test that a session saved with
  only `selected` still marks its file and resets correctly
- [x] 1.2 Add `show_pair` and make `show(tab, entry)` build the pair of the
  entry and call it; verify the existing selection tests in
  `tests/session_spec.lua` pass unchanged
- [x] 1.3 Derive `state.selected`, which the tree mark and
  `focus_selected` in `lua/twintree/treeview.lua` use, from the pair;
  verify the existing tree and toggle tests pass
- [x] 1.4 Make `reset_layout` in `lua/twintree/init.lua` restore the
  recorded pair through `show_pair`, recreating deleted buffers from the
  paths; add tests for the three scenarios of "Reset keeps a file reached by
  navigation" by setting a pair directly, and verify they pass

## 2. Pair a file with its counterpart

- [x] 2.1 Add a function that classifies a buffer (not a file, before side,
  after side, no side) with the longer root winning when both match; verify
  with unit tests for a cached worktree file, a checkout file, a file
  outside both, a file that does not exist yet, a terminal buffer and an
  unnamed buffer
- [x] 2.2 Add the mapping to the other side through the changed-file
  entries; verify with unit tests for an unchanged file, a renamed file in
  both directions, a file missing on the other side, a path that is a
  directory on the other side, and a session whose tree buffer was deleted

## 3. Follow navigation in the panes

- [x] 3.1 Replace `sync_diff` with the handler from the design for a file of
  the pane's own side, and update the autocommand description in
  `plugin/twintree.lua`; verify with tests for the scenarios "Leaving the
  selected file", "Jump to another file in the after pane", "File that did
  not change", "Renamed file", "File missing on the other side" and
  "Returning to the selected file"
- [x] 3.2 Rewrite the tests in `tests/session_spec.lua` that expect diff
  mode to switch off after leaving the selected file, so that they assert
  the new behaviour; verify `make test` passes
- [x] 3.3 Add a test that the other pane lands on the corresponding line
  when lines were added above the target, and that the panes scroll
  together; verify it passes
- [x] 3.4 Show a file of neither side as the same buffer in both panes;
  verify with a test for "Jump into a dependency"
- [x] 3.5 Keep non-file buffers out of following; verify with tests for
  "Terminal in a pane" and "Returning to the file"
- [x] 3.6 Handle a missing pane; verify with tests for both scenarios of
  "Following with a missing pane" that no window is opened or closed and
  `vim.v.errmsg` stays empty
- [x] 3.7 Verify with tests that a window split off a pane does not change
  the panes, and that a jump in one diff tab leaves a second diff tab
  unchanged
- [x] 3.8 Verify with a test that sourcing `plugin/twintree.lua` again
  leaves one handler and that following still works afterwards
- [x] 3.9 Switch diff mode off in a new window of a diff tab that is not a
  pane; verify with a test for "Split of a pane is not part of the diff"

## 4. Put a file into the pane of its side

- [x] 4.1 Add the deferred move for a file that landed in the other side's
  pane, carrying the view and using `:keepalt` in the landing window;
  verify with a test for "Quickfix entry opened in the other pane" that
  checks buffers, diff mode, cursor line and current window after
  `vim.wait`
- [x] 4.2 Verify with a test that `<C-^>` in the landing pane returns to the
  file it showed before the jump
- [x] 4.3 Verify with tests that the move gives up without error when the
  landing window was closed, or shows another buffer, before the scheduled
  callback runs

## 5. Tree window keeps the tree

- [x] 5.1 Set `winfixbuf` in `setup_tree_window`; verify with tests for
  "Quickfix entry opened from the tree", "Editing a file from the tree" and
  "Tree buffer deleted"
- [x] 5.2 Update the tests in `tests/layout_ui_spec.lua` that put another
  buffer into the tree window so that they switch the option off first, and
  keep their assertions about `session.tree_win`; verify `make test` passes

## 6. Tree mark and refresh

- [x] 6.1 Redraw the tree after a followed jump and move the cursor of a
  visible tree window to the marked line; verify with tests for the four
  scenarios of "The mark follows the panes"
- [x] 6.2 Make `refresh` recompute `state.selected` without touching the
  panes;
  verify with tests for "Shown file is not listed" and "Shown file becomes
  listed"

## 7. Real terminal and documentation

- [x] 7.1 Add a case to the pseudo-terminal harness of
  `tests/resize_spec.lua` that fills the quickfix list, moves to the after
  pane, opens the quickfix window and presses `<CR>` on a before side
  entry; verify the child ends with the file in the before pane, the
  counterpart in the after pane on the corresponding line, the cursor on
  the entry's line, and no redraw that shows the file in the after pane
- [x] 7.2 Run the same steps by hand in a terminal and watch for a visible
  flash of the file in the wrong pane; record the result, with the Neovim
  version only, in the change notes or as a follow-up item in `TODO.md`
- [x] 7.3 Rewrite the README section that says diff mode is switched off
  after a jump, and describe following, the tree window and the use of
  `:split`; verify the text matches the behaviour covered by the tests
- [x] 7.4 Run `make test` and `openspec validate add-pane-following
  --strict`; verify both pass
