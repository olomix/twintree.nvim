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
- Make showing a file safe when the layout changes while it is being
  shown. Found by plan reviews of the changed-file navigation; not fixed
  there.

  Background. Every way of showing a file (`<CR>` in the tree, opening a
  diff, following a jump in a pane, `:TwintreeResetLayout`, the commands
  that move between changed files) ends in `show_pair` in
  `lua/twintree/session.lua`. It checks once, at the start, that both
  pane windows exist, and then works in several steps: register the two
  buffers, switch diff mode off, load each file into its pane, take the
  old buffers out of the diff, switch diff mode on, redraw the tree.
  Almost every one of these steps fires Neovim events (`BufNew`,
  `BufAdd`, `BufReadPost`, `FileType`, `OptionSet` for `diff`,
  `scrollbind` and others), and an autocommand of the user or of another
  plugin can react to them by closing a window or the whole tab. The
  code after such a step still uses the windows it saw at the start.

  What goes wrong today:

  - A pane is closed in the middle. The next step touches the closed
    window and the user gets a Lua traceback instead of the message
    "a pane of this diff is missing; run :TwintreeResetLayout". This was
    also reported as a pre-existing issue by the code review of the
    cursor-on-first-change work.
  - The diff tab is closed in the middle. The code goes on to save the
    session into a tab that no longer exists: again a traceback.
  - The callers have the same problem right after `show_pair` returns:
    `reset_layout` focuses the tree window of a closed tab, `open`
    returns the handle of a closed tab, and the code that moves a file
    to the pane of its side restores the view in a window that may be
    gone.
  - When an attempt is taken back (`undo_pair`), the file can already be
    recorded as shown (`viewed`), so it would not get its cursor on the
    first change later. With one pane gone, the remaining pane is put
    back into diff mode alone, although a pane without a partner is
    meant to be a plain window.
  - Returning to the compared file in one pane switches diff mode on
    before checking that the other pane still exists.

  How to see it: add an autocommand that closes a window when a file is
  read, for example
  `autocmd BufReadPost * ++once lua vim.api.nvim_win_close(<pane>, true)`
  with the window number of the other pane, and select a file in the
  tree.

  How rare it is: it needs something that closes windows or tabs in
  reaction to a buffer or option event. Plain use of the plugin does not
  trigger it. The project rule it breaks is "never a Lua traceback" for
  a layout the user changed.

  A pane moved to another tab is not part of this: `<C-w>T` gives the
  window a new number, so the old pane already counts as closed and the
  message about a missing pane appears. The window it leaves in the
  other tab stays in diff mode, which is only cosmetic. A pane keeps its
  number in another tab only when a script moves it through the API.

  Ideas for the fix, to be designed:

  - A safety net instead of a check after every step: when `show_pair`
    fails and the layout turns out to be broken afterwards (tab gone,
    session gone, pane gone), report that as one line; when the layout
    is intact, raise the error as today, because then it is a bug.
  - Make the small helpers (`set_diff`, `leave_diff`) do nothing for a
    window or tab that is gone.
  - Record a file as shown (`viewed`, the last changed file) only after
    the last step that can fail.
  - Decide what the remaining pane looks like when the other one is
    gone: its previous file, without diff mode.
  - Make `reset_layout`, `open` and the move of a file to its own pane
    check their windows again after `show_pair` returns.
  - A tree buffer shown in another tab is deleted when its diff tab
    closes; say so wherever "other tabs are not changed" is promised.
  - Tests can use real autocommands: `BufReadPost` can close the other
    pane, the pane being loaded, or the current tab.
