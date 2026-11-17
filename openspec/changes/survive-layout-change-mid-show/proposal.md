# Proposal

## Why

Showing a file takes several steps, and almost every step fires events
that an autocommand of the user or of another plugin can answer by
closing a window or the tab. The plugin checks the two panes once, at the
start, and then uses the windows it saw. When one goes away in the
middle, the user gets a Lua traceback, and the session can be left
recording a file that the panes do not show. The project's rule for a
layout the user changed is a clear message, never a traceback. Since the
keys for the next and previous file, this code runs on every key press.

Seen with the current code, the same on Neovim 0.11 and on nightly:

- An autocommand closes the other pane while a file is loaded: "Invalid
  window id", and the session records the new file as selected.
- An autocommand closes the pane that is loading its file: the message
  says the file "could not be loaded", which is not what happened.
- An autocommand closes the diff tab while a file is loaded: a Lua error,
  from a selection, from a jump in a pane and from a layout reset.
- With the other pane closed, a pane that returns to the file it compared
  is put into diff mode on its own.

## What Changes

- When a pane goes away while a file is being shown, the plugin reports
  the existing message about a missing pane, and the session records what
  it recorded before the attempt. The pane that is left shows the file it
  showed before, as a plain window.
- When the diff tab goes away while a file is being shown, the plugin
  reports one line that says so. Nothing else is done: there is no
  session left to keep consistent.
- This holds for every way a file is shown: a selection in the tree, the
  commands that move between changed files, a jump followed in a pane,
  the first file of a new session and a layout reset.
- A file counts as shown, for the cursor on its first change and for the
  position of next and previous, only when the attempt completed.
- A pane without a partner is never put into diff mode, also when it
  returns to the file the session records for it.
- An error that is not explained by a missing pane or tab is raised as
  before. It is a bug, and it must stay visible.

Not part of this change:

- A pane that a script moved to another tab through the API and that
  keeps its window number there. `<C-w>T` gives the window a new number,
  so the pane already counts as missing.
- Recreating a missing pane.
- A window closed after the file is fully shown. The file is shown; the
  next action reports the missing pane, as today.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `diff-session`: a new requirement for a layout that changes while a
  file is being shown; the requirement about following with a missing
  pane gains the case of a pane that returns to its recorded file.

## Impact

- `lua/twintree/session.lua`: `show_pair` and its guard, `undo_pair`,
  `show`, `follow`, `move_to_own_pane`.
- `lua/twintree/init.lua`: `open` and `reset_layout`, which use windows
  after `show_pair` returns.
- `tests/`: new specs that close a pane or the tab from real
  autocommands at each step.
- `TODO.md`: the item about layout safety goes.
