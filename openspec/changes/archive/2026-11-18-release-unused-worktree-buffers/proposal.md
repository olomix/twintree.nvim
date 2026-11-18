# Proposal

## Why

When a diff tab is closed, the buffers of its cached worktrees stay. They
are read-only copies of an old commit that no window shows any more, yet
they remain in the buffer list, and the language server that was started
for the worktree keeps running. Every diff adds more of both, for as long
as Neovim runs.

Measured with the current code: after a diff with two changed files and
one jump into an unchanged file, three buffers of the cached worktree are
still listed and loaded once the tab is closed. Neovim does not stop an
LSP client when its last buffer goes away, on 0.11, on 0.12 or on
nightly.

## What Changes

- When a tab is closed, the plugin wipes out every buffer of a cached
  worktree that nothing uses any more: no open diff session uses that
  worktree, no window shows the buffer, no quickfix or location list
  refers to it, and it has no unsaved changes.
- It then stops every client of Neovim's built-in LSP client whose
  workspace lies in such a worktree and that has no buffer attached.
- The buffers are wiped out the way `:bwipeout` does it, with the usual
  buffer events, so that Neovim and other plugins drop what they keep
  per buffer, such as diagnostics.
- Buffers of the user's working directory are never touched, whoever
  loaded them, and neither are their language servers.
- The worktree directories stay on disk as before; `:TwintreeClean` is
  still what removes them.

Reopening a diff of the same commit therefore loads its files again and
starts its language server again. The worktree itself is reused, so the
checkout is not repeated.

Not part of this change:

- Buffers of the working directory that the plugin loaded for the after
  side. They are the user's project files.
- Language servers that do not run through Neovim's built-in client
  (coc.nvim, ALE). Their buffers are wiped out; their processes are not
  the plugin's to stop.
- An option to keep buffers or servers.
- A language server that is still starting when the tab is closed.
  Neovim does not list it yet; it is stopped with the next closed tab.
- Entries of the jump list, the tag stack and the alternate file that
  point at a wiped buffer. Neovim drops them, as for every wiped buffer.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `revision-worktrees`: two new requirements, for the buffers and for the
  language servers of cached worktrees that are no longer used.

## Impact

- `lua/twintree/worktree.lua`: finding and releasing what belongs to
  unused cached worktrees.
- `lua/twintree/session.lua`: the roots of every pane of every open
  session, for deciding what is in use.
- `plugin/twintree.lua`: the `TabClosed` autocommand calls it and becomes
  nested.
- `tests/`: new specs; a language server that runs inside Neovim, so
  that no real server is needed.
- `README.md`, `doc/twintree.txt`: the help said the plugin contains no
  LSP code and that language servers keep their index; both change.
- `TODO.md`: the item goes.
