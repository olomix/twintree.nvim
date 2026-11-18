# TODO

- Make git calls async and show a progress bar or spinner while work is in
  progress. Decide what to do when a conflicting command is issued while the
  previous one is still running.
- Default key mappings for `:TwintreeToggleTree` and `:TwintreeResetLayout`.
  Keys bound only while a diff tab is current exist now (`keys` option,
  `lua/twintree/keys.lua`); new keys can be added as further actions
  there.
- `<CR>` and a double click in a tree buffer that is shown in a tab without
  its diff (`:tab sbuffer`) do nothing and say nothing. Act on the diff the
  tree belongs to, or report a message.
- Work out how to end a diff that occupies the only tab (`nvim +Twintree`):
  `:tabclose` refuses to close the last tab, so today the only way is to
  quit Neovim. One possible solution, to be evaluated: open two tabs in that
  case, the default empty one and the diff, so that `:tabclose` on the diff
  lands in the empty tab.
