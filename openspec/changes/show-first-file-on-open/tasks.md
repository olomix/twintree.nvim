# Tasks

## 1. First file of the tree

- [x] 1.1 Add a function to `lua/twintree/treeview.lua` that returns the entry of the first file line of a session's tree, or nil when there is none; verify with specs in `tests/treeview_spec.lua` for a file inside a directory listed above a top-level file that git reports earlier, and for a diff with no changes

## 2. Show it on open

- [x] 2.1 In `init.open`, show the first file with `session.show` after `treeview.set_entries` and return `tab, message` when it is not opened (design decisions 1 and 3); verify with specs in `tests/session_spec.lua` that after `open` both panes show the first file in diff mode, its tree line is marked, the cursor is in the after pane, and that a diff with no changes opens with empty panes and the cursor in the tree
- [x] 2.2 Run `make test` and adjust the existing specs that assumed empty panes or the cursor in the tree after `open`, per design decision 5; verify the whole suite passes and no assertion was removed without a replacement
- [x] 2.3 Verify with a spec that a deleted first file opens with the file in the before pane, the placeholder in the after pane and the cursor in the after pane

## 3. First file not opened

- [x] 3.1 Verify with specs in `tests/swap_ui_spec.lua`, with `swap.ask` replaced, that Abort for the first file leaves an open session with the tree filled, empty panes, no marked line, the cursor in the tree and one message, that the worktrees of the session still exist, and that selecting the file afterwards asks again and shows it
- [x] 3.2 Verify with a spec that without a user interface a leftover swap file of the first file gives the "not opened" message from `open` without waiting for input
- [x] 3.3 Verify with a spec in `tests/layout_ui_spec.lua` that when a pane is closed while the session opens (simulated, because no event fires between creating the panes and showing the file), `open` returns the tab with the missing pane message and raises no Lua error
- [x] 3.4 Record the layout again after the first file is shown (design decision 6); verify with specs that a session opened in a narrow terminal is not read as zoomed and gets the configured tree width and equal panes when the terminal is widened

## 4. Documentation

- [x] 4.1 Describe in `README.md` and `doc/twintree.txt` that a session opens with the first file of the tree shown and the cursor in the after pane, and what happens when that file is not opened; verify `:helptags doc` succeeds
- [x] 4.2 Remove the item about showing the first changed file from `TODO.md`; verify by reading the file

## 5. End-to-end check

- [x] 5.1 Add cases to `tests/resize_spec.lua` in the real terminal: `nvim +Twintree` shows the first file in both panes with the cursor in the after pane, and with a leftover swap file of the first file the prompt appears at startup and Abort leaves the tree with empty panes
- [x] 5.2 Run `make test` and `openspec validate show-first-file-on-open --strict`; verify both pass
