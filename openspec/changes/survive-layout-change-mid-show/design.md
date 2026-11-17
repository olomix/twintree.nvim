# Design

## Context

Every way of showing a file ends in `show_pair` in
`lua/twintree/session.lua`: `show` (a selection in the tree, the first
file of a session, the commands that move between changed files),
`follow` and `move_to_own_pane` (a jump in a pane), and `reset_layout`.

`show_pair` checks once, with `has_panes`, that both pane windows are
valid. It then:

1. records the new pair, selection and buffers in the session, which
   registers the two buffers (`BufNew`, `BufAdd`);
2. for each pane, switches diff mode off (`OptionSet`) and loads the file
   with `swap.open` (`BufReadPost`, `FileType`, `BufWinEnter` and more);
3. records the file as shown (`viewed`, `last_entry`) and saves;
4. takes the replaced buffers out of the diff and switches diff mode on
   in both panes (`OptionSet`);
5. draws the tree and puts the cursor of every tree window on the file.

An autocommand can close a window or the tab at any of the events in
brackets. `swap.open` returning false leads to `undo_pair`, which puts
back the previous record and buffers and switches diff mode on again in a
pane that shows its recorded buffer. The public `show_pair` wraps all of
this in `pcall` and raises whatever error it caught.

After `show_pair` returns, its callers go on to use windows: `show`
asserts the session and enters the after pane, `move_to_own_pane`
restores a view in the pane the file was moved to, `reset_layout`
notifies, clears the selection and enters the tree window, and `open`
returns the tab.

Checked with the current code, with the same results on Neovim 0.11 and
on nightly. Each case used a real autocommand:

- `BufReadPost` for the before file closes the after pane: `show` raises
  "Invalid window id", and the session is left recording the new file.
- `BufReadPost` closes the pane that is loading: `show` returns false
  with "was not opened: it could not be loaded".
- `BufReadPost` closes the diff tab: a Lua error from saving the session
  into a tab that is gone, for `show`, for a jump in a pane (where it
  reaches the user as the error of the command that jumped) and for
  `reset_layout`.
- The after pane closed, another buffer shown in the before pane, then
  the recorded file again: the before pane is in diff mode alone.
  `follow` switches diff mode on for the recorded buffer before it looks
  at the other pane.

See proposal.md for the motivation.

## Goals / Non-Goals

**Goals:**

- No step has to be listed for the fix to hold. A step that is added
  later, or one that was overlooked, is covered too.
- A failed attempt leaves nothing behind in the session record.
- An error that is a bug still reaches the developer.

**Non-Goals:**

- Running the steps with events blocked. The events give a file its
  filetype, its read-only protection and the user's own setup.
- A pane moved to another tab through the API with the same window
  number.
- Changing what happens when a window is closed after the file is shown.

## Decisions

### 1. A net around `show_pair`, not a check after every step

The public `show_pair` keeps its `pcall`. When the inner function raised,
it asks `layout_problem(tab)`:

- a problem: the error was caused by the layout. The attempt is taken
  back (decision 3) and `false` and the problem's message are returned.
- no problem: the error is raised as before.

`layout_problem(tab)` returns `TAB_GONE` when the tab is not valid or
holds no session, `BROKEN_LAYOUT` when a pane window of the session is
not valid, and nil otherwise.

Every use of a window or tab that is gone raises in Neovim's API, so the
net catches a closed pane or tab wherever it happens, without the code
having to know where user code can run.

Alternative: check the layout after each step that fires events.
Rejected: plan reviews of an earlier attempt found about eight such
places and callers beyond them, and missed ones would still raise.

### 2. Two explicit checks where nothing raises

Two places can lose a pane without any error:

- `swap.open` returns false when its own window was closed while it
  loaded the file. Before that result is read as "the file was not
  opened", `layout_problem` is asked; a problem wins, so the user is told
  about the pane and not about a file that "could not be loaded".
- A pane can be closed by the last event of the last step that switches
  diff mode on. Before the file is recorded as shown, `layout_problem`
  is asked once more, and a problem is treated like a raised error.

Both go through the same taking back as decision 1.

### 3. Taking an attempt back

`show_pair` keeps what it needs for this in one table that the guard owns
and the inner function fills: the previous pair, selection and buffers,
and, per pane, the window it changed and the buffer that window showed.

- Tab gone: nothing is done. No session is left, and no window of
  another tab is touched.
- Pane gone: the session is read again from the tab, the previous pair,
  selection and buffers are recorded, and the tree is redrawn. A pane
  that was changed gets its previous buffer back when its window is
  still valid and still the pane of the session; a layout reset run by
  user code in between leaves new panes that the attempt never touched.
  Every pane that is left has diff mode switched off: a pane without a
  partner is a plain window.

`undo_pair` becomes this function. With both panes still there, which is
the declined swap file, it behaves as today: diff mode comes back in a
pane that shows its recorded buffer.

### 4. A file is recorded as shown at the end

`declined`, `viewed` and `last_entry` are written after diff mode is on
and the second check of decision 2 passed, not right after the files were
loaded. An attempt that is taken back then has nothing to undo there.

Drawing the tree comes after that point. A tab closed while the tree is
drawn is caught by the net and reported as `TAB_GONE`; a pane closed then
raises nothing, and the file counts as shown, as today.

### 5. Callers

- `show`: reads the session again without asserting it; when it is gone,
  returns `false, TAB_GONE`. Enters the after pane only when that window
  is valid, as now. A tab closed while the tree is drawn is already
  turned into that result by the net, so this is a second line of
  defence that no spec reaches.
- `move_to_own_pane`: restores the view and enters the pane the file
  moved to only when that window is still valid.
- `follow`: asks `has_panes` before it switches diff mode on for the
  recorded buffer; without a partner the pane gets diff mode off.
- `reset_layout`: after its `show_pair`, when the tab is no longer the
  current, valid diff tab, returns its existing "closed while its layout
  was reset" result and does nothing else. It checks the after pane and
  the tree window before it enters one of them.
- `open`: when showing the first file fails and the tab is gone, it is a
  failed open: the worktrees the command created are removed and `nil`
  with the message is returned. A first file that is not opened while
  the session is still there keeps returning the tab with the message.

`treeview.activate`, `nav.run` and `decline` already report a returned
error and need no change.

### 6. Messages

`session.TAB_GONE` is "the diff tab was closed while a file was shown".
A missing pane uses `session.BROKEN_LAYOUT`, unchanged. Both are reported
at level ERROR, as every refused selection is.

### 7. Specs use real autocommands

The earlier assumption that a test cannot close the current tab or the
loading window from an autocommand was wrong: `BufReadPost` can do both.
Each spec arms one autocommand that closes a pane or the tab at one
event, runs the action, and asserts: no Lua error, the one message, the
session record, the panes, and for a closed tab the windows of the other
tab. The events covered are `BufNew` (registering the buffers) and
`BufReadPost` of the first and of the second file, each closing the other
pane and the loading pane.

Found during implementation: `OptionSet` does not fire while Neovim
starts, and the suite runs from a command of the command line, before
startup is over. The cases for diff mode going off and on therefore wrap
the command that switches diff mode and close the pane right after it,
which is the moment the autocommand would run.

The net itself is proven by a spec that fails when the net is removed,
and the "bug stays visible" rule by a spec that makes a step fail with
both panes and the tab intact.

## Risks / Trade-offs

- [A real bug raises while, by coincidence, a pane or the tab is gone,
  and is reported as a layout message] → Accepted. The layout message is
  true in that moment, and the bug shows again with the layout intact.
- [Taking an attempt back runs more events, in which user code closes
  something else] → The function touches only windows it finds valid at
  that moment, and wraps the buffer restore in `pcall` as `undo_pair`
  does today.
- [Recording a file as shown later changes when `follow` sees it] →
  `follow` is blocked by the `showing` flag for the whole attempt, and
  the pair and buffers are still recorded at the start for the events
  that fire in between.
- [`open` now returns nil where it returned a tab that was already
  closed] → A closed tab was never a usable result; the command reports
  the message either way.

## Open Questions

None.
