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
- Handle a swap file conflict when the panes open a file of the checkout
  that another Neovim instance is editing. The file is opened through the
  API, which cannot show the `E325` dialog, so it ends in a Lua traceback,
  and the session is left recording a pair the panes do not show. Since the
  panes follow navigation, any jump to such a file hits it, not only a
  selection in the tree. To decide: open the file anyway and editable, or
  read-only. Either way, a failure to show a pair should give a one-line
  message and leave the previous pair in place. Needs a test with an
  existing swap file.
- When a session opens, show the diff of the first changed file instead of
  empty panes. Only after the swap file conflict above is handled: until
  then, opening a session could end in a traceback before the user did
  anything.
- When a changed file is shown, put the cursor on its first change instead
  of the top of the file. When the user returns to a file they already
  viewed, the cursor should be where they left it.
