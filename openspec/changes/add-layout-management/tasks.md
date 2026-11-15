# Tasks

## 1. Decision function

- [x] 1.1 Create `lua/twintree/layout.lua` with the pure `decide(input)` implementing the seven rules of design decision 2; verify with table-driven specs in `tests/layout_spec.lua`, one case per rule plus hidden tree, `winminwidth` larger than 1, and both orders of rule 1 (zoomed and not zoomed)
- [x] 1.2 Add the rounding guard to `learn` so that a ratio is replaced only when it would not produce the current before width; verify with a spec that applies a ratio, feeds the resulting widths back, and gets the same ratio for ten different total widths

## 2. Session state and tree lifetime

- [x] 2.1 Add `layout` to the session state with defaults filled in by `session.get` for states that lack it; verify with a spec that a state saved without `layout` reads back with ratio 0.5, the configured tree width and the current columns
- [x] 2.2 Replace `session.is_intact` with `session.has_panes` and make `session.show` return an error naming `:TwintreeResetLayout` when a pane is missing; verify with specs that selecting a file works while the tree window is closed and the tree buffer is shown in another window, and that a missing pane gives the message without a Lua error
- [x] 2.3 Keep the tree buffer when its window closes (`bufhidden = "hide"`) and add `treeview.sweep()` on `TabClosed`; verify with specs that `<C-w>c` on the tree keeps the buffer, the panes stay in diff mode and the session exists, that closing a diff tab deletes its tree buffer whether the tree was visible or hidden, and that the tree of a second diff tab survives
- [x] 2.4 Add `treeview.ensure_buf(tab)` that re-creates a deleted tree buffer with recomputed entries; verify with a spec that wipes the tree buffer and gets a new one listing the same files

## 3. Synchronization

- [x] 3.1 Implement `layout.sync(tab)`: gather widths, call `decide`, perform `apply`, `restore`, `unfix` and `learn`, save the state, with a re-entry guard and early return when there is no session or a pane is missing; verify with specs in `tests/layout_ui_spec.lua` that call `sync` after `nvim_win_set_width`, `wincmd |` and `wincmd =` for: hand-set pane ratio learned, widened tree learned, pane zoom then equalize, tree zoom then equalize, nothing changed while zoomed, and `sync` in a tab without a session being a no-op
- [x] 3.2 Register one autocommand for `WinResized`, `VimResized` and `TabEnter` calling `sync`, and call `sync` at the end of `session.create`; verify with a spec that the autocommands exist once after re-sourcing `plugin/twintree.lua` and that `nvim_exec_autocmds("WinResized")` triggers a restore after a simulated zoom

## 4. Commands

- [x] 4.1 Extract the window-building part of `session.create` and the tree window options into functions shared with the new commands; verify the existing layout specs still pass unchanged
- [x] 4.2 Implement `require("twintree").toggle_tree()` per design decision 6; verify with specs for hiding, showing at the far left with the remembered width and the cursor on the selected file, the pane ratio being equal before and after a hide and show, a deleted tree buffer being rebuilt, and the tree-is-the-only-window message
- [x] 4.3 Implement `require("twintree").reset_layout()` per design decision 7; verify with specs that start from: a closed pane, extra splits, unrelated buffers in the panes, a hidden tree, a widened tree, and a window holding a modified buffer; each must end with exactly three windows in order, tree at the configured width, equal panes, the selected file shown in diff mode (or empty panes and cursor in the tree when nothing is selected), folds kept, and the modified buffer still loaded
- [x] 4.4 Register `:TwintreeToggleTree` and `:TwintreeResetLayout` in `plugin/twintree.lua`; verify with specs that both exist, and that in a tab without a session each reports "no diff session in this tab" at error level, raises no Lua error and leaves the window count unchanged

## 5. Documentation

- [x] 5.1 Update `README.md` and `doc/twintree.txt`: document both commands, the zoom and equalize behaviour, hiding the tree with `<C-w>c`, that `<C-w>t` goes to the before pane while the tree is hidden, and replace the "keep the windows in place" advice with `:TwintreeResetLayout`; verify `:helptags doc` succeeds and `:help :TwintreeResetLayout` opens the entry
- [x] 5.2 Remove the resize item and the hide-tree and zoom item from `TODO.md`, and add an item for default key mappings of the two commands; verify the file lists neither of the removed items

## 6. End-to-end check

- [x] 6.1 Add a spec that runs a child Neovim in a pty, opens a diff, resizes the pty wider and narrower with `jobresize` and reads the window widths over RPC, including a resize while another tab is current; it must show the panes keeping their ratio and the tree its width, and must be skipped with a message when a pty cannot be opened
- [x] 6.2 Run `make test` and verify the whole suite passes
- [x] 6.3 Manual check in a real terminal: resize the terminal, zoom each of the three windows with `<C-w>|` and return with `<C-w>=`, widen the tree and zoom again, hide and show the tree, break the layout and reset it; record the result in `notes.md` of the change, without machine-specific details

## Workflow follow-up

- Archive the change after review.
