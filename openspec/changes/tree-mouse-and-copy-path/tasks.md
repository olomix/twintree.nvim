# Tasks

## 1. Double click and keys

- [x] 1.1 Set a clipboard for tests in `tests/minimal_init.lua` (design decision 5); verify with a spec that `setreg("+", …)` in a spec reaches the test clipboard, that `getreg("+")` reads it back, and that `has("clipboard")` is 1
- [x] 1.2 Add a function to `treeview` that returns the line of the cursor for a state and make `activate()` use it (design decision 3); verify that the existing specs of `<CR>` pass unchanged
- [x] 1.3 Map `<2-LeftMouse>` in `treeview.create_buf()` (design decision 1); verify with specs in `tests/mouse_spec.lua`, with `getmousepos()` stubbed, that the key shows a file, folds and unfolds a directory, works in a second window that shows the tree buffer, reports the reset-layout message of `<CR>` when a pane is closed, and does not act when the position is line 0 or another window; verify that the tree buffer has no buffer-local mapping for `<LeftMouse>`, `<LeftDrag>`, `<LeftRelease>`, `<3-LeftMouse>` or `<4-LeftMouse>`; verify that the specs fail without the mapping and that the last one fails without the position check
- [x] 1.4 Set the keys before the filetype in `create_buf()` (design decision 2); verify with specs that a `FileType twintree` autocommand of the user that maps `<2-LeftMouse>`, and one that maps `<CR>`, is what the key runs, and that the specs fail with the old order
- [x] 1.5 Verify with specs on a pseudo terminal: a real double click on a file line shows that file while the cursor was in a pane; a single click on another line only moves the cursor; a double click below the last line acts on the last line; a drag over a line selects text and shows no file; a triple click ends in linewise visual mode; a double click on the status line of the tree shows no file and folds nothing

## 2. Copy a path

- [x] 2.1 Add `lua/twintree/path.lua` (design decision 3); verify with specs the three forms for a modified file of the working tree, a deleted file, a renamed file, a file of a diff of two commits, a listed file that is on neither side any more, a directory, a line of several nested directories, a directory that exists on the before side only, and a path with spaces
- [x] 2.2 Add `copy_path(form)` to `lua/twintree/init.lua` and the command `:TwintreeCopyPath` to `plugin/twintree.lua`; verify with specs that the test clipboard gets the text and a message shows it, with a control character escaped in the message and raw in the clipboard, that no argument means `relative`, that `getcompletion("TwintreeCopyPath ", "cmdline")` gives the three forms and `"TwintreeCopyPath a"` only `absolute`, and that two arguments are refused with the clipboard unchanged
- [x] 2.3 Verify with specs what the command acts on: the line of the cursor in the tree; the shown file in a pane, wherever the cursor of the tree is; an unchanged file a pane shows, with its relative path; a file outside both sides, with `absolute` and `name` copied and `relative` refused; the shown file from a window of the diff tab that is neither tree nor pane; the shown file when the tree is hidden; the line of the cursor in the tree when both panes are closed; the line of the cursor in a second window that shows the tree buffer; the line of the cursor in a window of another tab that shows the tree buffer, with the absolute path of the owning diff
- [x] 2.4 Verify with specs the failures, each with the clipboard unchanged and no Lua error: the "No changes" line, no file shown and the cursor outside the tree, an unknown argument, a tab without a diff, `has("clipboard")` stubbed to 0, and a register write that raises

## 3. Menu

- [x] 3.1 Add the function that keeps the menu items in step and its autocommands (design decision 4); verify with specs, with `getmousepos()` stubbed, that after `MenuPopup` in the tree on a file line and on a directory line `menu_get("PopUp")` starts with the three items and the separator; that none of the four is there after the event in a pane, in a tab without a diff, on the "No changes" line, and when the mouse position names another window
- [x] 3.2 Verify with specs that the items are gone after leaving the tree buffer for another window, after closing the diff tab, and after the plugin file is sourced again; that an item of the user, and one of the user named "Copy file name" that runs something else, is still there with its own action before and after the menu was opened in the tree; that the event raises nothing after `:aunmenu PopUp`; that `'mouse'` and `'mousemodel'` are as they were; and that the group has one `MenuPopup` autocommand after the plugin file is sourced again
- [x] 3.3 Verify with specs on a pseudo terminal: a right click on a file line that is not the line of the cursor, from a pane, followed by choosing the first item, puts the relative path of the clicked file into the clipboard of the child; a right click in a pane afterwards opens a menu whose first item is not the plugin's, and copies nothing; a right click inside a visual selection in the tree opens the menu for visual mode, without the plugin's items

- [x] 3.4 Verify with specs that `<CR>` and a double click in a tree buffer shown in a tab without a diff, and in another diff tab, report that the diff of the tree is in another tab and change nothing; that the menu has no copy items when the mouse is on no line; and that a name ending in a carriage return reaches the clipboard unchanged

## 4. Documentation

- [x] 4.1 Update `doc/twintree.txt` and `README.md` as in design decision 6; verify that `:helptags doc` succeeds and that the command has a help tag
- [x] 4.2 In `TODO.md`, remove the item about the mouse click; verify by reading the file

## 5. Checks

- [x] 5.1 Run `make test` on the oldest supported, the stable and the nightly Neovim, and `openspec validate tree-mouse-and-copy-path --strict`; verify all pass
