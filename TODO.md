# TODO

- Make git calls async and show a progress bar or spinner while work is in
  progress. Decide what to do when a conflicting command is issued while the
  previous one is still running.
- Fast jump to the next/previous changed file (`]f`/`[f`, if they do not
  conflict with other keys).
- Default key mappings for `:TwintreeToggleTree` and `:TwintreeResetLayout`,
  and where such keys should live so they work in the panes without leaking
  into other tabs.
- Open the file diff on mouse click in the tree.
- Work out how to end a diff that occupies the only tab (`nvim +Twintree`):
  `:tabclose` refuses to close the last tab, so today the only way is to
  quit Neovim. One possible solution, to be evaluated: open two tabs in that
  case, the default empty one and the diff, so that `:tabclose` on the diff
  lands in the empty tab.
- Clean up when a diff tab closes: remove the worktree buffers that are not
  shown anywhere else, so they do not stay in the buffer list and keep the
  language server of the old worktree running.
