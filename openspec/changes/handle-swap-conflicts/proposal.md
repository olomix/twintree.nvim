# Proposal

## Why

When a pane is about to show a file of the checkout that has a swap file,
the plugin ends in a Lua traceback, and the session records a pair of files
the panes do not show. This happens even in the harmless case where the file
is simply open in another running Neovim. Since the panes follow navigation,
any jump to such a file triggers it, not only a selection in the tree.

The cause is how the file is put into the pane: through the API, where
Neovim neither runs its swap handlers nor shows its dialog, and only raises
`E325`.

## What Changes

- Put files into the panes through an Ex command, so that Neovim's swap
  handling applies.
- A file open in another running Neovim opens normally with Neovim's own
  one-line warning, without a question.
- For any other swap file, such as one left by a crash, show a prompt
  modelled on Neovim's ATTENTION text, with the same information and the
  same choices: Open Read-Only, Edit anyway, Recover, Delete it, Quit,
  Abort. Neovim applies the answer.
- When a file is not opened, because the user chose Quit or Abort or
  because opening failed, report one line and leave the session consistent:
  panes the plugin had changed show their previous files again, a pane the
  user navigated stays where the user put it, and the recorded pair is the
  previous one.
- The prompt is active only while the plugin itself opens a file. Files the
  user opens keep Neovim's dialog.

Out of scope: files of cached worktrees, which use no swap files; changing
what Neovim does for files the user opens; showing the first changed file
when a session opens (the next item in `TODO.md`, which this change
unblocks).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `diff-session`: new requirements for showing a file that has a swap file,
  for the prompt, and for what the panes and the session look like when a
  file is not opened.

## Impact

- New module `lua/twintree/swap.lua`; changes in `lua/twintree/session.lua`
  (how a buffer is put into a pane, and undoing a failed attempt), in
  `lua/twintree/init.lua` (the layout reset reports a file that was not
  opened) and in `plugin/twintree.lua` (a `SwapExists` autocommand).
- One new autocommand. It does nothing unless the plugin is opening a file
  and no earlier handler has decided.
- `README.md`, `doc/twintree.txt` and `TODO.md` are updated.
- No new dependencies and no new options.
