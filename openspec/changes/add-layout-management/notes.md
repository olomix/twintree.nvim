# Notes

## What the implementation changed in the design

- A shrinking terminal can squeeze a pane to the minimum width, which looks
  exactly like a zoom. The first version of rule 1 looked at the widths
  after the resize and therefore left such a layout broken. The layout state
  now records `zoomed` at every synchronization, and rule 1 uses that stored
  value. Found by the first test of a large shrink.
- Equal panes are stored as a ratio of exactly 0.5, so that an odd number of
  columns does not turn "equal" into 0.504.

## What was verified automatically

`tests/resize_spec.lua` runs a second Neovim in a pseudo-terminal and drives
it with real key presses and real terminal resizes. It passed for:

- growing and shrinking the terminal with equal panes,
- a hand-set pane ratio across a resize,
- a resize while another tab was current,
- `<C-w>|` then `<C-w>=` in a pane and in the tree,
- a hand-set tree width surviving a zoom,
- the pane ratio surviving `<C-w>c` on the tree.

Observed along the way: in a headless Neovim the `WinResized` event is not
delivered, while `VimResized`, `TabEnter` and `TabClosed` are. The other
specs therefore call `layout.sync` directly or fire the autocommand by hand.

## Check by hand (task 6.3)

Done by the maintainer in a real terminal after reloading the plugin:
resizing the terminal, zooming each of the three windows with `<C-w>|` and
returning with `<C-w>=`, widening the tree and zooming again, hiding and
showing the tree, and breaking the layout followed by
`:TwintreeResetLayout`. Everything behaved as expected.
