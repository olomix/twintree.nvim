# Proposal

## Why

Started with `nvim +Twintree` on Neovim 0.11 or 0.12, a diff whose cursor
ends in the tree gets a fourth window: the tree column is split in two,
and the cursor is in the new half. That happens when nothing changed, and
when the first file was not opened. The spec asks for exactly three
windows.

The cause is outside the plugin's own code. The tree window has
`'winfixbuf'`, so that jumps made from the tree open in a pane. Neovim's
bundled netrw runs `:windo` for `VimEnter`, and Neovim before 0.13 splits
a window that has `'winfixbuf'` before it runs `:windo` there. The
nightly build no longer does, which is why this went unnoticed: one spec
failed on released versions only, and it was read as a problem of the
swap file prompt.

## What Changes

- When a session is created, the after pane becomes the previous window
  of the tree, the one `<C-w>p` goes to. Neovim before 0.13 runs `:windo`
  from the previous window when the current one has `'winfixbuf'`, and
  only splits when there is no such window.
- A diff opened from the command line therefore has three windows on
  every supported Neovim version.
- A new spec starts a second, headless Neovim with `+Twintree`, which is
  the only way to reach the time between the command line and `VimEnter`.

Not part of this change: a `:windo` the user runs later with the cursor
in the tree after the previous window was closed or is another window
with `'winfixbuf'`. On Neovim before 0.13 it then splits the tree window,
as it does for every window with that option.

Alternative considered: set `'winfixbuf'` only after `VimEnter`.
Rejected: the suite runs the plugin from a command of the command line,
before `VimEnter`, so the tree would never get the option there, and
three specs about the tree keeping its buffer failed.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `diff-session`: the requirement about where a session opens gains
  scenarios for a diff started from the command line with the cursor in
  the tree.

## Impact

- `lua/twintree/session.lua`: the previous window of the tree when a
  session is created.
- `tests/startup_spec.lua` (new).
- `TODO.md`: the item about Neovim 0.11 goes; this was its cause.
