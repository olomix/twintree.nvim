# Tasks

## 1. The net and taking an attempt back

- [x] 1.1 Add `layout_problem(tab)` and `session.TAB_GONE` to `lua/twintree/session.lua` (design decisions 1 and 6); verify with specs that it returns nil for an intact session, the missing pane message with either pane closed, and the tab message for a closed tab and for a tab without a session
- [x] 1.2 Add `tests/show_safety_spec.lua` with one case per event of design decision 7 that closes the other pane or the loading pane during a selection, from a real autocommand where the event fires in the suite; verify that the cases fail before the fix with a Lua error or the wrong message, and note in the pull request which did
- [x] 1.3 Make the guard of `show_pair` ask `layout_problem` when the inner function raised, take the attempt back and return the message, and raise as before when there is no problem; add the two explicit checks; turn `undo_pair` into the function that takes an attempt back (design decisions 1, 2 and 3); verify that the specs of 1.2 pass: no Lua error, one message at level ERROR that names `:TwintreeResetLayout`, the previous pair and selection recorded, the tree marking the previous file, and the remaining pane showing its previous file without diff mode
- [x] 1.4 Record `declined`, `viewed` and `last_entry` after diff mode is on (design decision 4); verify with specs that after a pane went away at each event neither `viewed` nor `last_entry` names the file, that after `:TwintreeResetLayout` the file is shown with the cursor on its first change, and that `:TwintreeNextFile` goes to that same file again
- [x] 1.5 Verify with specs that the declined swap file path is unchanged: with both panes there, the previous pair comes back in diff mode and the message says the file was not opened
- [x] 1.6 Verify with a spec that an error with both panes and the tab intact is raised, not reported as a layout message, and with a second spec, run by hand once, that removing the net makes the specs of 1.2 fail

## 2. A closed tab

- [x] 2.1 Verify with specs that a diff tab closed from an autocommand while a selected file is loaded gives one message at level ERROR saying the diff tab was closed, no Lua error, and that the windows and buffers of the other tab are as before, except the tree buffer of the closed diff
- [x] 2.2 Make `show` return the tab message when the session is gone after `show_pair` (design decision 5); verify with a spec that a tab closed while the tree is drawn gives that message and no Lua error

## 3. Callers

- [x] 3.1 Guard `move_to_own_pane` and the recorded-buffer branch of `follow` (design decision 5); verify with specs in `tests/follow_spec.lua` that with the other pane closed during a followed jump the pane keeps the file the user jumped to without diff mode and one message says a pane is missing, that a tab closed during a followed jump gives the tab message and no error from the command that jumped, that a file moved to its own pane raises nothing when that pane is closed while the tree is drawn, and that a pane returning to its recorded file with the other pane closed is not in diff mode
- [x] 3.2 Guard `reset_layout` after its `show_pair` (design decision 5); verify with specs in `tests/layout_ui_spec.lua` that a tab closed while the reset shows the file gives the reset's own message and no Lua error, and that a pane closed then gives the missing pane message, no selection and the cursor in the tree
- [x] 3.3 Make `open` treat a tab closed while the first file is shown as a failed open (design decision 5); verify with specs that `open` returns nil and the tab message, that no session and no extra tab are left, that the worktree the command created is removed while one that was cached before is kept, and that a first file that is only not opened still returns the tab
- [x] 3.4 Verify with specs in `tests/nav_spec.lua` that `:TwintreeNextFile` with a pane closed while its file loads reports the missing pane at level ERROR and leaves the position where it was

## 4. Documentation and checks

- [x] 4.1 Say in `doc/twintree.txt`, where missing panes are described, that a pane or tab closed while a file is being shown gives a message and leaves the previous file selected; verify `:helptags doc` succeeds
- [x] 4.2 Remove the item about layout safety from `TODO.md`; when something found on the way was left out, add it as an item. Verify by reading the file
- [x] 4.3 Run `make test` on the oldest supported, the stable and the nightly Neovim, and `openspec validate survive-layout-change-mid-show --strict`; verify all pass
