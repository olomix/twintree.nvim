# Tasks

## 1. Remember what the session has shown

- [x] 1.1 Add the `viewed` field to the session record in `lua/twintree/session.lua`: document it on `twintree.Session`, default it in `session.get`, and have `show_pair` add the file buffers of both panes after it succeeded, not the placeholder (design decision 3); verify with specs in `tests/session_spec.lua` that after a selection the buffers of both panes are recorded, that a deleted file records only its before buffer, that a declined or failed show records nothing, and that a session record without the field still works

## 2. Cursor on the first change

- [x] 2.1 In `session.show`, jump to the first change when the buffer of the pane that takes the jump was not in `viewed` before the pair was shown (design decisions 1, 2 and 4); verify with specs in `tests/session_spec.lua` for a change further down than one window height that the cursor of the after pane is on its first line, that the before pane is on the corresponding line with the same top line, and that the cursor is in the after pane
- [x] 2.2 Run `make test` and adjust existing specs that assumed line 1 after a selection; verify the whole suite passes and no assertion was removed without a replacement
- [x] 2.3 Verify with specs the edges of the jump: a first change that exists on the before side only, a change on line 1, lines added above line 1 on either side, a file with the same content on both sides (no error, line 1), an added and a deleted file
- [x] 2.4 Verify with a spec that `<C-o>` after a first view does not go to line 1 of the file, and with a spec that a user mapping of `]c` does not change where the cursor lands
- [x] 2.5 Verify with a spec that the first file shown by `twintree.open()` has the cursor on its first change
- [x] 2.6 Verify with a spec that a working tree file open in a window of another tab is shown on its first change while the cursor of that other window stays where it was
- [x] 2.7 Do not scroll a pair with a placeholder together (design decision 7); verify with a spec that a deleted file stays at its top after a command ends in the empty after pane, and that the next pair with both sides scrolls together again

## 3. Returning and navigation

- [x] 3.1 Verify with specs in `tests/session_spec.lua` that the cursor is where it was left after: select A, move, select B, select A; selecting the file the panes already show; wiping the buffer in between puts it on the first change again; and a file shown in one diff tab is on its first change when first selected in another diff tab. If Neovim's own position turns out not to be kept in one of these, stop and record it in design.md before adding the fallback of decision 5
- [x] 3.2 Verify with specs in `tests/follow_spec.lua` that a jump to a line of a changed file the session has not shown keeps the cursor on that line, and that selecting that file in the tree later leaves the cursor where the user left it

## 4. Broken layout

- [x] 4.1 Check the pane window for validity before the jump (design decision 6); verify with specs in `tests/layout_ui_spec.lua` that selecting a file with a pane closed reports the missing pane without a Lua error and records nothing, that after `:TwintreeResetLayout` the same file is shown on its first change, and that a window closed by an autocommand while the buffers load gives no Lua error

## 5. Documentation

- [x] 5.1 Describe in `README.md` and `doc/twintree.txt` where the cursor is when a file is shown for the first time and when it is shown again; verify `:helptags doc` succeeds
- [x] 5.2 Remove the item about the cursor on the first change from `TODO.md`; verify by reading the file

## 6. End-to-end check

- [x] 6.1 Add a case to `tests/resize_spec.lua` in the real terminal: `nvim +Twintree` on a repository whose first file changes far below the top shows that change on screen in both panes
- [x] 6.2 Run `make test` and `openspec validate cursor-on-first-change --strict`; verify both pass
