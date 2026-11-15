# Tasks

## 1. Line counts

- [x] 1.1 Add the pure `changes.parse_numstat(out)` for `git diff --numstat -z -M` output; verify with specs in `tests/changes_spec.lua` for a normal record, a binary record (`-\t-`), a rename record keyed by the new path, and names with spaces and non-ASCII characters
- [x] 1.2 Add `git.count_lines(path)` returning the line count, or nil for a file with a NUL byte in its first 8000 bytes, a file over 5 MB or an unreadable path; verify with specs for a file with and without a final newline, an empty file, a binary file, a directory and a missing file
- [x] 1.3 Make `git.changed_files` join `added` and `deleted` onto the entries, from numstat for tracked files and from `count_lines` for untracked ones; verify with specs in `tests/git_spec.lua` for two commits (modified, added, deleted, renamed with a change), the working tree with staged, unstaged and untracked files, a binary file and a file removed from the index but still on disk

## 2. Line builder

- [x] 2.1 Change `tree.lines` to take an options table (`collapsed`, `selected`, `dir_status`, `width`, `icon`) and update its callers; verify the existing nesting, folding, chain and selection specs pass with the new signature
- [x] 2.2 Implement `cut(name, cells)` in display cells with the extension kept; verify with specs for ASCII names, names with wide characters, a name without extension, an extension longer than half the room, and room of 1, 2 and 3 cells
- [x] 2.3 Implement the line anatomy and `fit` of design decision 3: guides, icon or arrow, name, origin, padding, counts and status letter at the right edge, for files and for directories; verify with specs in `tests/tree_spec.lua` giving exact strings at a fixed width for each row of the decision table, for a file without counts, for a directory with and without marker, for widths from 1 to 5, and that no line is wider than the width
- [x] 2.4 Implement the rename origin rule (old file name within the same directory, old path otherwise, only when everything fits); verify with specs for both forms and for a width one cell too narrow
- [x] 2.5 Return byte-range highlights for guides, icon, directory name, origin, added count, deleted count and status letter; verify with specs that check the ranges against the positions of those pieces in lines with ASCII and non-ASCII names

## 3. Icons

- [x] 3.1 Add the `icons` option to `config.lua` (default true) and `lua/twintree/icons.lua` with `source()` per design decision 7; verify with specs in `tests/treeview_spec.lua` using stubbed `mini.icons` and `nvim-web-devicons` modules: each provider alone, both present, neither present, `icons = false`, and a provider that raises an error

## 4. Tree view

- [x] 4.1 Implement `treeview.text_width(state)` and pass the width and the icon source to `tree.lines` in `draw`, storing the drawn width in the buffer; verify with specs that the drawn lines are exactly as wide as the tree window's text area, also with a sign column in a window the user made, and that the configured width is used when no window shows the tree
- [x] 4.2 Add the highlight groups `TwintreeGuide` and `TwintreeOrigin` and apply the new ranges; verify with a spec that the extmarks of a drawn line carry the expected groups
- [x] 4.3 Implement `treeview.redraw_if_resized(tab)` and call it from the size autocommand after `layout.sync` and after `layout.reapply` in `toggle_tree` and `reset_layout`; verify with specs that resizing the tree window and calling it redraws for the new width, that firing the autocommand does the same, that showing a hidden tree at another width draws for that width, that a tab without a session is a no-op, and that `<CR>` on a line with a cut name selects the right file
- [x] 4.4 Update the specs that assert tree lines (`tests/session_spec.lua`, `tests/layout_ui_spec.lua`, `tests/follow_spec.lua`) to the new layout; verify `make test` passes

## 5. Documentation

- [x] 5.1 Update `README.md` and `doc/twintree.txt`: the layout of a tree line, line counts, icons and the `icons` option, the optional icon plugins, cut names, the rename origin, the new highlight groups; verify `:helptags doc` succeeds and the documented option name matches `config.lua`
- [x] 5.2 Remove "Add file icons" from `TODO.md`; verify the item is gone

## 6. End-to-end check

- [x] 6.1 Add a case to `tests/resize_spec.lua`: in the real terminal, widen and narrow the tree window with keys and read the tree lines and the window width over RPC; every line must be as wide as the text area and end with its status letter
- [x] 6.2 Run `make test` and verify the whole suite passes
- [x] 6.3 Check by hand in a real terminal with an icon plugin and a Nerd Font: icons and folder glyphs, colours of counts and letters, the column at the right edge, cut names, the rename origin in a wide tree, indent guides, and resizing the tree; record the result in `notes.md` of the change without machine-specific details
- [x] 6.4 Fixes from review: measure the ellipsis instead of assuming one cell (`ambiwidth=double`); keep the highlights of guides and icon in a squeezed line; redraw on `OptionSet` for the options that change the text area; show no counts for a file removed from the index but still on disk; correct the example in the README and help; verify with the specs added for each case, each shown to fail on the code before its fix

## Workflow follow-up

- Archive the change after review.
