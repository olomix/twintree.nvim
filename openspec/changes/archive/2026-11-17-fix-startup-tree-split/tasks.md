# Tasks

## 1. Fix

- [x] 1.1 Add `tests/startup_spec.lua`, which starts a headless Neovim with `+Twintree` and reports the windows of the tab once startup is over; verify that the case without changes fails on Neovim 0.11 and 0.12 before the fix and passes on nightly
- [x] 1.2 Make the after pane the previous window of the tree in `session.create`, without firing window events; verify that `tests/startup_spec.lua` passes on Neovim 0.11, 0.12 and nightly, that the tree window has `'winfixbuf'`, that a `:windo` with the cursor in the tree of a new session leaves three windows, and that the case of `tests/resize_spec.lua` about a declined swap file prompt at startup passes on 0.11 and 0.12
- [x] 1.3 Run `make test` on Neovim 0.11, 0.12 and nightly; verify the whole suite passes on each

## 2. Documentation

- [x] 2.1 Remove the item about Neovim 0.11 from `TODO.md`; verify by reading the file
- [x] 2.2 Run `openspec validate fix-startup-tree-split --strict`; verify it passes
