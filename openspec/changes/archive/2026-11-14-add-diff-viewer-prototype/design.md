# Design

## Context

The repository contains only OpenSpec scaffolding; it is not yet a git
repository. See proposal.md for motivation.

Constraints:

- Target Neovim is a 0.13-dev nightly. Use current APIs (`vim.system`,
  `vim.fs`, `vim.api.nvim_create_user_command`, `vim.uv`) and no deprecated
  forms. 0.11 is the declared minimum.
- The plugin is loaded through lazy.nvim dev mode and reloaded by hand with
  `:Lazy reload twintree.nvim`, so it must be reload-safe.
- Tests run headless with plenary busted. plenary is taken from
  `PLENARY_DIR` or lazy.nvim's install directory.
- No runtime plugin dependencies.

## Goals / Non-Goals

**Goals:**

- A working end-to-end prototype: command, worktrees, tree, two diff panes.
- Pure logic (parsing git output, building the tree, resolving sides) kept
  apart from window and buffer code so it is testable without UI.
- LSP on both sides without any LSP code in the plugin.

**Non-Goals:**

- Asynchronous git calls. The prototype blocks during `git worktree add`.
- Dependencies that are not tracked by git inside worktrees.
- Submodules, LFS, sparse checkouts.
- File icons, configurable keymaps, syncing the tree selection to the buffer
  shown in a pane.
- Changing the user's Neovim configuration.

## Decisions

### 1. Sides are resolved to a root directory and an optional commit

A side is `{ root = <dir>, commit = <sha or nil> }`. `commit == nil` means the
working tree and `root` is the repository toplevel. Everything after
resolution (tree, panes) only joins `root` with a relative path and does not
care which kind of side it is.

Resolution, with `mb(a, b)` being `git merge-base a b`:

| Arguments | Before | After |
|---|---|---|
| none | `HEAD` | working tree |
| `rev1` | `mb(rev1, HEAD)` | working tree |
| `rev1 rev2` | `mb(rev1, rev2)` | `rev2` |

Merge-base is applied in every case, like `git diff a...b`. When `rev1` is an
ancestor of the other side this equals `rev1`, so `:Twintree HEAD~3` behaves
as expected. Alternative considered: plain two-dot comparison for the
two-argument form; rejected because the user chose merge-base for branch
review and one rule is easier to explain. A two-dot variant can be added
later as a flag.

Revisions are resolved with `git rev-parse --verify <rev>^{commit}` before
anything is created, so errors leave no tab or worktree behind. `HEAD` is
resolved only when it is one of the sides. When a later step fails (a
checkout, listing the changes), the worktrees created by that call are
removed again; worktrees that were already cached stay.

### 2. Worktree location and identity

Path: `stdpath("cache")/twintree/<repo-id>/<full-sha>`.

`<repo-id>` is `<repository name>-<first 12 hex of sha256 of the absolute
git common dir>`. The common dir (`git rev-parse --path-format=absolute
--git-common-dir`) is the same for the main checkout and all of its
worktrees, so opening a diff from inside a linked worktree reuses the same
cache. For the same reason the repository name is taken from the common dir
(the directory that contains `.git`), not from the toplevel of the checkout
the command was run in.

Creation: `git worktree add --detach <path> <sha>`. Reuse check: the path
exists and `git -C <path> rev-parse HEAD` prints `<sha>`. Otherwise run
`git worktree remove --force <path>` (ignore failure), delete the directory,
`git worktree prune`, and create again.

Alternatives considered: a temp dir removed on exit (rejected by the user in
favour of caching); `git archive` extraction (no `.git`, so tools that look
for a repository root behave differently, and no cheap integrity check).

### 3. Cleaning

`:TwintreeClean` lists `<cache>/twintree/<repo-id>/*`, skips paths that are
the root of a side in any open session, runs `git worktree remove --force`
for the rest, then `git worktree prune`. It works on the current repository
only. Worktrees of repositories that were deleted stay in the cache
directory; removing them by hand is safe.

### 4. Read-only worktrees through one autocommand

A `BufReadPost` and `BufNewFile` autocommand checks whether the buffer path
is under `<cache>/twintree/` and sets `readonly` and `nomodifiable`. This
covers files reached through LSP jumps, not only the files opened by the
plugin. Alternative: set the options when the plugin opens a buffer;
rejected because it misses navigation.

### 5. LSP is left to the user's configuration

Worktree files are ordinary files under a directory that contains the
project's root markers (and a `.git` file), so `vim.lsp.enable`-style
configurations compute a different `root_dir` and start a separate client for
the worktree. The plugin contains no LSP code. This is verified by hand with
gopls as part of the tasks, not by automated tests.

### 6. Changed files come from `git diff --name-status -z -M`

- Two commits: `git diff --name-status -z -M <before> <after>`.
- Working tree: `git diff --name-status -z -M <before>` (staged and unstaged
  together) plus `git ls-files --others --exclude-standard -z`, reported as
  added.

Both run in the repository toplevel. The parser is a pure function from the
NUL-separated output to `{ status, path, old_path }` entries; rename and copy
records carry two paths. Type changes and other statuses are shown as
modified. `ls-files` reports an untracked nested repository as a directory
entry with a trailing slash; such entries are dropped. Control characters in
a name (a newline is legal) are escaped for display only.

### 7. Tree is a plugin-owned scratch buffer

Pipeline, all pure until the last step:

1. entries → nested nodes (directories first, sorted by name),
2. collapse chains of single-directory children into one node,
3. nodes + set of collapsed directory paths + selected path → list of
   `{ text, node, highlights }` lines,
4. write lines to a `nofile`, `nomodifiable` buffer with filetype `twintree`
   and apply highlights with extmarks in one namespace.

A directory line gets a trailing `A` or `D` when the directory exists on one
side only. Only the letter uses the highlight group of that status; the name
stays `TwintreeDirectory`. The pure pipeline takes this as a `dir_status(path)` function; the
view implements it with `fs_stat` in both roots, which works the same for a
worktree and for the working tree. For a collapsed chain the deepest
directory is checked. A directory left on disk with only ignored files counts
as existing.

`<CR>` maps the cursor row to a node by flattening the stored entries again;
the result is the same as what was drawn because the pipeline is pure.
Highlight groups (`TwintreeAdded`, `TwintreeModified`, `TwintreeDeleted`,
`TwintreeRenamed`, `TwintreeDirectory`, `TwintreeSelected`) are defined with
`default = true` links to standard groups. Alternatives (`nui.nvim`,
a neo-tree source) were rejected to avoid a dependency and keep control of
the layout.

### 8. Showing a file and keeping panes browsable

Selecting an entry does, in each pane window: `diffoff`, then shows the
buffer of `root/path` (old path on the before side for renames), or a shared
empty `nofile` placeholder buffer when that path is not a regular file on
that side; then `diffthis` in both windows. The buffer is created with
`bufadd` and put in the window with `nvim_win_set_buf`, not with `:edit`, so
that no character of a file name is interpreted by the command line.

`diffthis` folds unchanged lines, which hides the code the plugin exists to
show, so `foldenable` is switched off in the pane right after every
`diffthis`. `zi` switches it back on for a hunk-only view.

`diff`, `scrollbind` and `cursorbind` are window-local, so after a jump to
another file the window would diff the wrong buffer. A `BufWinEnter` and
`BufEnter` autocommand handles this: if the window is a pane of a session, run
`diffthis` when the entered buffer is that pane's selected buffer and
`diffoff` otherwise. Options are changed through `nvim_win_call` so the
current window does not move.

### 9. Session state lives in a tab-scoped variable

State is stored in `vim.t[tab].twintree`: the window ids of the three
windows, the tree buffer, both sides, the repository toplevel, the selected
path, the selected buffer per pane and the collapsed directories. It holds
plain data only, so it survives a module reload. The changed files are kept
as plain data too, in the buffer variable `twintree_entries` of the tree
buffer, so the tree does not change under the cursor between refreshes; the
lines are derived from them on demand. Closing the tab drops the state with
the tab, so no explicit teardown is needed. Functions look the session up by
tab, and the autocommand finds it through the window's tab.

Alternative: a module-level table keyed by tab; rejected because
`:Lazy reload` would lose it.

All autocommands are in one augroup created with `clear = true`. Buffer
keymaps call `require("twintree....")` inside the callback, so they pick up
reloaded code.

### 10. Module layout

```
lua/twintree/init.lua       setup(opts), open(revs), clean()
lua/twintree/config.lua     defaults: tree_width = 35, cache_dir
lua/twintree/git.lua        run git, resolve revisions, merge-base, diff
lua/twintree/changes.lua    pure parser for name-status and ls-files output
lua/twintree/tree.lua       pure: entries -> nodes -> lines
lua/twintree/worktree.lua   cache paths, ensure, clean
lua/twintree/session.lua    tab layout, state, show file, autocommands
lua/twintree/treeview.lua   tree buffer rendering and keymaps
plugin/twintree.lua         :Twintree, :TwintreeClean, augroup
doc/twintree.txt
tests/minimal_init.lua, tests/*_spec.lua
Makefile                    `make test`
```

`setup()` is optional and idempotent; it only merges options. Commands are
registered in `plugin/twintree.lua`, so the plugin works without calling
`setup()`.

Git calls use `vim.system(cmd):wait()` and return `stdout` or
`nil, stderr`. Output is taken as raw bytes because `-z` output is
NUL-separated file names, not text.

### 11. Tests

`tests/minimal_init.lua` adds the repository and plenary to the runtimepath;
plenary's location comes from `PLENARY_DIR` with the lazy path above as the
default. Unit specs cover the parser and the tree pipeline. Integration
specs create a throwaway git repository in a temp directory with a few
commits, point `cache_dir` at another temp directory, and assert on sides,
worktree creation and reuse, cleaning, the window layout and buffer names.

## Risks / Trade-offs

- [Blocking UI while a large repository is checked out] → Show a message
  before `git worktree add`; caching makes it a one-time cost per commit.
  Async is a follow-up.
- [Old-side language server lacks untracked dependencies] → Documented
  limitation of the prototype; a setup hook or symlink list is a follow-up.
- [Two full language-server indexes use a lot of memory] → Inherent to the
  approach; only one worktree is used in working-tree mode.
- [Cached worktree was modified outside Neovim and no longer matches its
  commit] → Only `HEAD` is checked on reuse. `:TwintreeClean` resets it.
  A dirtiness check can be added if it shows up in practice.
- [Worktrees appear in `git worktree list` of the user's repository] →
  Documented; they are detached, so they lock no branch.
- [A language server reuses one client for both roots, or attaches with the
  wrong root] → Depends on the server configuration; checked by hand with
  gopls, and noted in the help file.
- [User closes or rearranges session windows] → Functions validate window
  ids from the session state and report an error instead of failing with a
  Lua traceback; restoring the layout is not attempted.

## Open Questions

- Should the tree follow the buffer shown in a pane when the user navigates
  to another changed file? Deferred; it does not affect the current design.
