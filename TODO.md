# TODO

- Make git calls async and show a progress bar or spinner while work is in
  progress. Decide what to do when a conflicting command is issued while the
  previous one is still running.
- Default key mappings for `:TwintreeToggleTree` and `:TwintreeResetLayout`.
  Keys bound only while a diff tab is current exist now (`keys` option,
  `lua/twintree/keys.lua`); new keys can be added as further actions
  there.
- Open the file diff on mouse click in the tree.
- Work out how to end a diff that occupies the only tab (`nvim +Twintree`):
  `:tabclose` refuses to close the last tab, so today the only way is to
  quit Neovim. One possible solution, to be evaluated: open two tabs in that
  case, the default empty one and the diff, so that `:tabclose` on the diff
  lands in the empty tab.
- Clean up when a diff tab closes: remove the worktree buffers that are not
  shown anywhere else, so they do not stay in the buffer list and keep the
  language server of the old worktree running.
