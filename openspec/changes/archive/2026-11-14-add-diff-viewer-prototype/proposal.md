# Proposal

## Why

Existing Neovim diff tools show only the changed hunks, or load the old
version into a scratch buffer where LSP does not work. To understand a change
you need to browse the surrounding code on both sides: how it worked before
and how it works now. twintree.nvim gives each side a real directory on disk
(a git worktree), so go-to-definition, references and the rest of LSP work
independently on the old and the new code.

The repository is empty. This change creates the first working prototype.

## What Changes

- Initialize the git repository and the plugin skeleton (Lua modules, command
  registration, help file, headless test setup).
- Add `:Twintree [rev1 [rev2]]`, which opens a diff session in a new tab with
  three columns: tree of changed files, "before" version, "after" version.
  - No argument: `HEAD` against the working tree.
  - One argument: merge-base of `rev1` and `HEAD` against the working tree.
  - Two arguments: merge-base of `rev1` and `rev2` against `rev2`.
- Use the real checkout as the "after" side whenever it is the working tree,
  so it stays editable. Every other side is a detached git worktree and is
  read-only.
- Keep worktrees cached per repository and commit under Neovim's cache
  directory and reuse them. Add `:TwintreeClean` to remove them.
- Render the tree of changed files in a plugin-owned buffer, with status
  markers, nested directories and collapsed single-child directory chains.
- Keep both code panes freely browsable: leaving the diffed file (for example
  by go-to-definition) switches diff mode off in that pane, and returning to
  it switches diff mode back on.
- Reuse the current tab instead of opening a new one when Neovim was just
  started and the tab holds only an empty buffer.
- Mark a directory in the tree with `A` or `D` when it exists on one side
  only.
- Show files in full in both panes; unchanged lines are not folded.

Out of scope for the prototype: making untracked dependencies (`node_modules`,
`.venv`, build output) available in worktrees, submodules, LFS, sparse
checkouts, file icons, asynchronous git calls, and any plugin-managed LSP
configuration. LSP attaches through the user's existing configuration.

## Capabilities

### New Capabilities

- `diff-session`: opening a diff from revisions, resolving the two sides, the
  three-column tab layout, showing a selected file on both sides, and
  browsing behaviour of the code panes.
- `changed-files-tree`: the list of changed files between the two sides and
  its presentation and interaction as a tree.
- `revision-worktrees`: creation, reuse, read-only protection and cleanup of
  the cached git worktrees that back a revision.

### Modified Capabilities

None.

## Impact

- New code only: `lua/twintree/`, `plugin/twintree.lua`, `doc/twintree.txt`,
  `tests/`, `README.md`, `Makefile`.
- Runtime requirements: Neovim 0.11 or newer (developed on 0.13-dev) and git.
  No plugin dependencies at runtime; `plenary.nvim` is needed only to run
  tests.
- Side effects on the user's machine: worktrees are registered in the
  inspected repository (visible in `git worktree list`) and stored under
  `stdpath("cache")/twintree/`.
- Loading the plugin needs a lazy.nvim spec in the Neovim configuration,
  which is outside this repository.
