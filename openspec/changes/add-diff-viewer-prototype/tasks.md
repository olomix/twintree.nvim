# Tasks

## 1. Repository and skeleton

- [x] 1.1 Run `git init` with `main` as the initial branch and add a `.gitignore`; verify `git status` works and lists the OpenSpec files as untracked
- [x] 1.2 Create `tests/minimal_init.lua` (repository and plenary on the runtimepath, plenary path from `PLENARY_DIR` with the lazy install as default) and a `Makefile` with a `test` target running `PlenaryBustedDirectory tests/`; verify `make test` runs a placeholder spec and exits 0
- [x] 1.3 Create `lua/twintree/config.lua` and `lua/twintree/init.lua` with an idempotent `setup(opts)` (`tree_width`, `cache_dir`); verify with a spec that calling `setup` twice keeps one merged config and that defaults apply without `setup`

## 2. Git access and changed files

- [x] 2.1 Implement `lua/twintree/git.lua`: run git in a directory, repository toplevel, absolute common dir, resolve a revision to a commit, merge-base; verify with specs against a temp repository, including the error results for a non-repository, an unknown revision and unrelated histories
- [x] 2.2 Implement the pure parser in `lua/twintree/changes.lua` for `--name-status -z` and `ls-files -z` output; verify with specs covering added, modified, deleted, renamed, type-changed, and names with spaces and non-ASCII characters
- [x] 2.3 Implement listing changed files for two commits and for a commit against the working tree (staged, unstaged, untracked, ignored excluded); verify with integration specs against a temp repository
- [x] 2.4 Implement side resolution for zero, one and two revision arguments (design decision 1); verify with specs that each form yields the expected before commit and after side, and that more than two arguments is an error

## 3. Worktrees

- [x] 3.1 Implement `lua/twintree/worktree.lua` path computation (`<cache>/twintree/<repo-id>/<sha>`); verify with a spec that two repositories with the same directory name get different locations and that a linked worktree of the same repository gets the same one
- [x] 3.2 Implement `ensure(repo, sha)`: create with `git worktree add --detach`, reuse when `HEAD` matches, replace when the directory is unusable, return git's stderr on failure; verify with specs for first creation, reuse (no second `worktree add`), replacement and failure
- [x] 3.3 Implement cleaning of the current repository's cached worktrees, skipping given in-use roots, followed by `git worktree prune`; verify with specs that removed worktrees are gone from disk and from `git worktree list` and that in-use ones remain
- [x] 3.4 Add the `BufReadPost`/`BufNewFile` autocommand that makes buffers under the cache directory `readonly` and `nomodifiable`; verify with a spec that a file opened from a worktree cannot be modified and a file from the checkout can

## 4. Tree of changed files

- [x] 4.1 Implement the pure pipeline in `lua/twintree/tree.lua`: entries to nested nodes, sorting with directories first, single-child chain collapsing, flattening to lines with collapsed and selected state; verify with specs for nesting, chain collapsing, collapsed directories, renamed entries and the empty list
- [x] 4.2 Implement `lua/twintree/treeview.lua`: scratch buffer with filetype `twintree`, line rendering, status and selection highlights through extmarks, default-linked highlight groups; verify with a spec that the buffer is `nofile` and not modifiable and that its lines match the pipeline output
- [x] 4.3 Add tree keymaps: `<CR>` selects a file or toggles a directory, `R` refreshes while keeping collapsed directories and the selection; verify with specs that drive the keys with `nvim_feedkeys` and check buffer lines and session state
- [x] 4.4 Mark directory lines with `A` or `D` when the directory exists on one side only, decided by checking the directory in both roots; verify with a pure spec for the line text and highlights and an integration spec with a new and a removed directory

## 5. Session

- [x] 5.1 Implement `lua/twintree/session.lua` layout: new tab or reuse of a lone empty tab, three windows in order tree, before, after, fixed tree width, state stored in the tab variable; verify with specs for both tab placement cases and the window order
- [x] 5.2 Implement showing a selected file in both panes with diff mode, including placeholder buffers for added and deleted files and the old path for renames; verify with specs checking buffer names per pane and `&diff` in both windows for each status
- [x] 5.3 Add the `BufWinEnter` handling that switches diff mode off when a pane shows a buffer other than its selected one and on again when it returns; verify with a spec that edits another file in the before pane and then returns
- [x] 5.4 Implement `open(revs)` in `init.lua` connecting side resolution, worktrees, changed files, layout and tree, creating nothing when resolution or worktree creation fails; verify with integration specs for the three argument forms, for the error cases (no new tab, no worktree), and for two sessions in two tabs selecting files independently
- [x] 5.5 Verify reload safety with a spec: open a session, clear `package.loaded` for `twintree*`, re-source `plugin/twintree.lua`, select a file, and check that both panes update and each autocommand exists once
- [x] 5.6 Switch folding off in a pane after every `diffthis` so unchanged lines stay visible; verify with a spec that a 60-line file with one change has no closed fold in either pane, also after leaving the file and returning
- [x] 5.7 Remove the worktrees a failed open created, clean up after a failed `git worktree add`, resolve `HEAD` only when it is a side, treat a directory as not a file when choosing pane buffers, escape control characters in tree names and drop untracked nested repositories; verify with the specs added for each case in `tests/`

## 6. Commands and documentation

- [x] 6.1 Register `:Twintree` (0 to 2 arguments, revision completion from branches and tags) and `:TwintreeClean` in `plugin/twintree.lua` with one augroup created with `clear = true`; verify with specs that both commands exist, that `:Twintree a b c` errors, and that `:TwintreeClean` reports the number removed and keeps worktrees of an open session
- [x] 6.2 Write `doc/twintree.txt` and `README.md`: commands, argument forms and merge-base rule, tree keys, configuration, worktree location and cleaning, known limitations (untracked dependencies, blocking checkout, worktrees visible in `git worktree list`); verify `:helptags doc` succeeds and `:help twintree` opens the file

## 7. End-to-end check

- [x] 7.1 Run the full suite with `make test` and verify it passes
- [x] 7.2 Manual check in a Go repository with `nvim -c "set rtp+=<plugin dir>" -c "runtime plugin/twintree.lua" -c "Twintree HEAD~1"` (lazy.nvim resets the runtimepath, so `--cmd` is too early): the session uses the first tab, selecting a file shows a diff, go-to-definition works in both panes with separate gopls clients (`:checkhealth vim.lsp` shows two roots), the before side is read-only, and the after side is editable; record the result in the change notes

## Workflow follow-up

- Check whether the name `twintree.nvim` is free on GitHub before creating the remote.
- Archive the change after review.
