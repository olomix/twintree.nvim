# Proposal

## Why

A diff that was opened in the only tab cannot be ended. The plugin reuses
that tab when it holds one empty window, as after `nvim +Twintree` or
after `:Twintree` in a Neovim started without a file, and `:tabclose`
refuses to close the last tab. The only way out is to quit Neovim.

Because the tab never closes, what the plugin does on a closed tab never
happens for such a diff either: its tree buffer, the buffers of its
cached worktrees and their language servers stay for as long as Neovim
runs.

## What Changes

- A diff session always opens in a new tab. The exception for a lone
  empty tab goes away, so `nvim +Twintree` starts with two tabs: the
  empty one Neovim started with, and the diff, which is the current tab.
- `:tabclose` therefore ends a diff whenever another tab exists, which
  is the case from the start. After `nvim +Twintree` it lands in the
  empty tab.
- An open that fails after the new tab exists, as when the terminal is
  too small for the three windows, closes that tab again.

What the user sees differently:

- The tab line is shown from the start with the default `'showtabline'`,
  since there are two tabs.
- After `nvim +Twintree`, closing the three windows of the diff one by
  one leaves Neovim in the empty tab instead of quitting it. `:qa` quits
  as before.
- The empty buffer Neovim started with stays listed.

Not part of this change:

- A command that ends a diff. `:tabclose` is Neovim's way.
- A diff that the user makes the only tab, by closing the other tabs or
  with `:tabonly`. `:tabclose` refuses there as before; the help file
  says how to get out.
- Removing the empty tab after the diff tab was closed, or hiding the
  tab line.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `diff-session`: the requirement "Tab placement" loses its exception.
- `changed-file-navigation`: one scenario of "Default keys exist only
  while a diff tab is current" describes a diff in the tab Neovim
  started with; it now describes a diff opened from that tab.

## Impact

- `lua/twintree/session.lua`: `create()` always opens a tab and closes
  it again when the layout cannot be made; the check for a blank tab and
  a reset of `'winfixbuf'` that only the reused tab needed go.
- `lua/twintree/init.lua`: `open()` reports a layout that could not be
  made.
- `tests/`: the specs that expect one tab after opening a diff in an
  empty Neovim; a new spec for ending a diff that was opened at startup.
- `README.md`, `doc/twintree.txt`: where a diff opens, and the sentences
  about the refused `:tabclose`.
- `TODO.md`: the item goes.
