# Tasks

## 1. Tab placement

- [x] 1.1 Make `session.create()` always open a new tab; remove `is_blank_tab()` and the reset of `'winfixbuf'` with its comment; rewrite the comment before `keys.sync()` in `open()` (design decisions 1 and 3). In the same task adjust the specs of design decision 4 that the change breaks: the renamed spec for the lone empty tab in `tests/session_spec.lua`, the tab counts in `session_spec`, `keys_spec`, `startup_spec` and `resize_spec`, `gT` in the resize spec that returns from another tab, the row of the tab line in the `layout_ui_spec` spec for the place of the tree, and the removal of the `follow_spec` spec for a window that was a tree. Verify that the spec for the lone empty tab fails with the old code, that the whole suite passes, and that the keys spec for the first file not shown fails when the `keys.sync()` call in `open()` is removed
- [x] 1.2 Close the tab again when the layout cannot be made (design decision 2); verify with a spec that makes pane creation fail that the command reports the reason, one tab is left with the origin window current and its buffer unchanged, and no session, no tree buffer and no worktree remains; that with tabs after the origin tab the origin tab is current again; verify that the specs fail without the rollback
- [x] 1.3 Verify with specs: `:tabclose` in a diff opened in an empty Neovim succeeds, leaves the first tab current with no session and no tree buffer; a tab closed by an autocommand while the first file is shown, with the diff opened from the blank tab, leaves one tab with its window as it was and no tree buffer, which fails without the cleanup in `open()`; after `:tabonly` in the diff tab `:tabclose` fails and the session is still there; with tabs to the right of the origin tab, `:tabclose` of the diff tab closes it without an error
- [x] 1.4 Extend `tests/startup_spec.lua`: a real `nvim +Twintree` has two tabs with the diff tab current, three windows in the diff tab, and one window in the first tab showing buffer 1, listed and with no `bufhidden`, with and without changed files; `:tabclose` after startup succeeds and leaves the first tab current, no session and no tree buffer, once with the layout intact and once after a pane was closed and another window opened in the diff tab

## 2. Documentation

- [x] 2.1 Update `README.md` and `doc/twintree.txt` as in design decision 5; verify that the sentences "the diff uses the first tab" and "that tab is used instead" are gone, that the advice for a diff that is the only tab is there, and that `:helptags doc` succeeds
- [x] 2.2 Remove the item about the diff in the only tab from `TODO.md`; verify by reading the file

## 3. Checks

- [x] 3.1 Run `make test` on the oldest supported, the stable and the nightly Neovim, and `openspec validate open-diff-in-new-tab --strict`; verify all pass
