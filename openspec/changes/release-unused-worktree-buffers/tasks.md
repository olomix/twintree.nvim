# Tasks

## 1. Buffers

- [x] 1.1 Add a function to `lua/twintree/worktree.lua` that returns the cached worktree root of a path or nil (design decision 2); verify with specs in `tests/worktree_spec.lua` that a file in a commit directory and in a subdirectory of it gives that root, also when the cache directory is reached through a symbolic link, and that the cache directory, a repository directory, and a file directly in either give nil
- [x] 1.2 Add a function to `lua/twintree/session.lua` that returns the roots of both panes of every open session (design decision 2), leaving `roots_in_use()` as it is; verify with a spec that it includes a working-directory root and both roots of a diff of two commits
- [x] 1.3 Add the function that wipes out the buffers of unused cached worktrees (design decisions 1, 3 and 5), call it from the existing `TabClosed` autocommand in `plugin/twintree.lua` after `treeview.sweep()`, and make that autocommand nested; verify with specs that after closing a diff tab the buffers of its cached worktree no longer exist, including one reached by navigation and one that was unloaded, that the specs fail without the call, and that the group still has exactly one `TabClosed` autocommand
- [x] 1.4 Verify with a spec the buffer events: a `BufWipeout` autocommand ran for a worktree buffer and `vim.diagnostic.get()` returns nothing for it after the tab is closed; verify that the spec fails when the autocommand is not nested
- [x] 1.5 Verify with specs what must stay: every buffer of the working directory, listed as before, also the ones the plugin loaded; the placeholder buffer; a hidden buffer of a file directly in the cache directory; a buffer shown in a window of another tab, with the other buffers of the worktree gone; a buffer the user made modifiable and changed, with no error reported
- [x] 1.6 Verify with specs the quickfix and location lists: a buffer with an entry in the current quickfix list, in an older list of the quickfix stack, and in the location list of a window each stays, and the entry can still be opened; verify that the spec fails without the condition
- [x] 1.7 Verify with specs the roots in use, each with a buffer of the worktree that no window shows: with two diff tabs on the same worktree, closing one keeps that buffer and the other tab still shows its files; closing a tab without a session while a diff is open keeps it; a diff opened from inside a cached worktree keeps the hidden buffers of that worktree when another tab is closed; with two diff tabs on different worktrees, closing one removes only its buffers. Verify that the first three fail when the roots in use are ignored
- [x] 1.8 Verify with specs the changed layout: after the user closed a pane, put another file into a pane, or split a pane, closing the diff tab removes the buffers no window shows, with no error; a pane moved to its own tab keeps its buffer when the diff tab is closed; with the before pane closed and the diff tab still open, closing another tab keeps the buffer; a buffer that was kept because a window showed it is gone after it was hidden and another tab was closed
- [x] 1.9 Verify with a spec that a `BufWipeout` autocommand that raises for one worktree buffer does not make `:tabclose` fail and does not keep the other buffers from being wiped out
- [x] 1.10 Verify with a spec that the worktree is still on disk afterwards and that opening the same diff again shows its files, and that the tree buffer of the closed tab is still deleted
- [x] 1.11 Run `make test` and adjust existing specs that relied on worktree buffers surviving a closed tab; verify the whole suite passes, that `tests/show_safety_spec.lua` passes unchanged, and that no assertion was removed without a replacement

## 2. Language servers

- [x] 2.1 Add a helper to `tests/helpers.lua` that starts an LSP client whose server runs inside Neovim (design decision 6); verify with a spec that the client initializes, attaches to a buffer, and that after `client:stop(false)` the helper recorded `shutdown` and `exit`, recorded no `terminate`, and the client left `vim.lsp.get_clients()`
- [x] 2.2 Stop the LSP clients of unused cached worktrees after the buffers were wiped out (design decisions 4 and 5); verify with specs that a client whose root is the cached worktree, and one whose root is a subdirectory of it, each with only buffers of that worktree, received `shutdown` and `exit` and left the client list when the diff tab was closed, without `terminate`, and that the specs fail without the code
- [x] 2.3 Verify with specs which clients keep running: one whose root is the working directory, also with no buffer attached; one of a worktree that another diff tab still uses, with no buffer attached, both with `root_dir` equal to the worktree root and with a workspace folder given as a URI; one that still has a buffer because a window of another tab shows it; one attached to a changed buffer that was not wiped out; one with a workspace folder in the worktree and another in the working directory; one whose folder is the repository directory of the cache above a worktree in use; one without a root directory and without workspace folders. Verify that the second fails when the roots in use are ignored
- [x] 2.4 Verify with a spec that a client that was asked to stop and whose server delays its answer is not asked again and not terminated when another tab is closed
- [x] 2.5 Verify with specs that a client whose `stop` raises causes no error and does not keep the other clients from being stopped, and that closing a tab with no LSP client at all works

## 3. Documentation

- [x] 3.1 Update `doc/twintree.txt` and `README.md` as in design decision 7; verify that no sentence still says the plugin contains no LSP code or that language servers keep their index across diffs, that the limit for a server that is still starting is stated, and that `:helptags doc` succeeds
- [x] 3.2 Remove the item about cleaning up worktree buffers from `TODO.md`; verify by reading the file

## 4. Checks

- [x] 4.1 Run `make test` on the oldest supported, the stable and the nightly Neovim, and `openspec validate release-unused-worktree-buffers --strict`; verify all pass
