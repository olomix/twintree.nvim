# TODO

- Make git calls async and show a progress bar or spinner while work is in
  progress. Decide what to do when a conflicting command is issued while the
  previous one is still running.
- Default key mappings for `:TwintreeToggleTree` and `:TwintreeResetLayout`.
  Keys bound only while a diff tab is current exist now (`keys` option,
  `lua/twintree/keys.lua`); new keys can be added as further actions
  there.
- Work out how to end a diff that occupies the only tab (`nvim +Twintree`):
  `:tabclose` refuses to close the last tab, so today the only way is to
  quit Neovim. One possible solution, to be evaluated: open two tabs in that
  case, the default empty one and the diff, so that `:tabclose` on the diff
  lands in the empty tab.
- Scroll both panes together when the mouse wheel is used over the pane that
  is not the current window. Neovim scrolls the window under the mouse but
  applies `'scrollbind'` only from the current window, so today the other
  pane stays where it is; plain `nvim -d` behaves the same. A possible way,
  not yet tried: on `WinScrolled` for a pane that is not current, bring the
  other pane to the matching position, by the alignment of the diff and not
  by line number, without one pane moving the other back.
