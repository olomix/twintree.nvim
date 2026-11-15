# Tasks

## 1. Prompt content

- [x] 1.1 Create `lua/twintree/swap.lua` with the pure `describe(info, path, file_mtime)` and `choices(running)`; verify with specs in `tests/swap_spec.lua` for a dead owner, a running owner (`STILL RUNNING`, no Delete it), a modified file, an unreadable swap file, and the letters of all six choices
- [x] 1.2 Add `swap.ask(text, labels)` using `vim.fn.confirm` and the mapping from its answer to `v:swapchoice`, with 0 treated as Abort; verify with a spec that stubs `vim.fn.confirm` and checks the text, the labels and each answer including 0

## 2. Opening through a command

- [x] 2.1 Implement `swap.open(win, buf, keepalt)` that runs `buffer N` or `keepalt buffer N` in the window, sets the "plugin is opening" flag around it, and returns whether the window shows the loaded buffer and a one-line reason otherwise; verify with specs in `tests/swap_ui_spec.lua` for a normal file, a placeholder buffer, an invalid buffer, and that the flag is cleared after a failure
- [x] 2.2 Implement `swap.on_swap_exists()` and register the `SwapExists` autocommand in `plugin/twintree.lua`: act only while the plugin is opening and `v:swapchoice` is empty, and not without a user interface; verify with specs that the plugin's `ask` is not called for a file the user opens with `:edit`, not called when an earlier handler set a choice, not called without a user interface, and that the autocommand exists once after the plugin file is sourced again
- [x] 2.3 Use `swap.open` in `session.show_pair` for both panes; verify the existing session, layout and pane-following specs pass unchanged, and add `keepalt` or `keepjumps` only where one of them requires it

## 3. Swap file outcomes

- [x] 3.1 Add helpers to the specs that leave a swap file behind (a second headless Neovim that edits the file and is killed) and that keep an owner running; verify with a spec that `swapinfo()` reports the expected process state for both
- [x] 3.2 Verify with specs, with `swap.ask` replaced, each answer after a selection in the tree: Open Read-Only (read-only, diff mode), Edit anyway (editable), Recover (recovered content), Delete it (swap file gone, editable), Quit and Abort (not opened)
- [x] 3.3 Verify with a spec that a file owned by a running Neovim opens editable in diff mode without `ask` being called and with the `W325` warning, after a selection and after a jump in the before pane
- [x] 3.4 Verify with a spec that a file of a cached worktree is shown without `ask` being called

## 4. A file that is not opened

- [x] 4.1 Implement the undo in `session.show_pair` per design decision 5 and the one-line reason of decision 6; verify with specs for a declined selection with a previous pair (both panes back in diff mode, mark kept, state unchanged), with empty panes, and for the second pane declined after the first was changed
- [x] 4.2 Report the failure from `session.follow` and `move_to_own_pane`; verify with specs that after a declined jump the navigated pane keeps the user's file without diff mode, the other pane and the mark are unchanged, one message is given, and returning to the previous file restores diff mode in both panes
- [x] 4.3 Report a file that is not opened during `reset_layout`; verify with a spec that the layout is rebuilt, no Lua error is raised and one message is given
- [x] 4.4 Verify with a spec that selecting a declined file again asks again, and that without a user interface a leftover swap file gives the "not opened" message without waiting

## 5. Documentation

- [x] 5.1 Document in `README.md` and `doc/twintree.txt` what happens when a file has a swap file: the warning for a running Neovim, the prompt and its choices, what the panes show after Quit or Abort; verify `:helptags doc` succeeds
- [x] 5.2 Remove the swap file item from `TODO.md` and drop the "only after the swap file conflict is handled" condition from the item about showing the first changed file; verify both by reading the file

## 6. End-to-end check

- [x] 6.1 Add cases to `tests/resize_spec.lua` in the real terminal: a leftover swap file, a selection in the tree, the prompt text on the screen, a key as the answer and the result for Open Read-Only and for Abort; and the prompt after a jump made with `:edit` in the before pane
- [x] 6.2 Run `make test` and verify the whole suite passes
- [x] 6.3 Check by hand with two Neovim instances: a file open in the other instance (warning, no question), and a leftover swap file from a killed instance (prompt, each kind of answer); record the result in `notes.md` of the change without machine-specific details

## Workflow follow-up

- Archive the change after review.
