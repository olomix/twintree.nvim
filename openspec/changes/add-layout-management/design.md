# Design

## Context

See proposal.md for motivation. Current state:

- `session.create` builds the three windows once: tree with `winfixwidth`
  at `config.options.tree_width`, then `wincmd =`. Nothing reacts to size
  changes afterwards.
- The tree buffer is created with `bufhidden = "wipe"`, so closing its
  window deletes it together with the stored entries.
- `session.show` refuses to work unless all three windows are valid
  (`session.is_intact`).
- Session state is plain data in `vim.t[tab].twintree`; the changed files
  are in the buffer variable `twintree_entries` of the tree buffer.

Observed behaviour of Neovim that shapes the design (measured in a bare
instance with a fixed-width left window and two panes):

| Action | Widths |
|---|---|
| start | 35, 62, 61 |
| `<C-w>|` in the right pane | 1, 1, 156 |
| then `<C-w>=` | 1, 78, 79 |
| `<C-w>|` in the fixed window | 76, 1, 1 |
| then `<C-w>=` | 76, 1, 1 (no change) |
| same, with `winfixwidth` off first | 26, 26, 26 |

A terminal resize gives or takes columns at the rightmost window only.
Closing a window re-equalizes the others when `equalalways` is on.

The project rule in `CLAUDE.md` applies: the tab belongs to the user, so no
feature may assume the three windows are still there.

## Goals / Non-Goals

**Goals:**

- Build on Neovim's own window commands; add only what they cannot do.
- One place that decides what to do after any size change, written as a pure
  function so that every case is unit-tested without a UI.
- Every entry point works, or reports a message, in any state of the tab.

**Non-Goals:**

- Remapping `<C-w>|`, `<C-w>=` or any other built-in key.
- Default key mappings for the new commands.
- Re-maximizing a zoomed window after a terminal resize.
- Removing worktree file buffers or language-server clients on tab close.
- Solving the "diff is the only tab" closing problem.

## Decisions

### 1. Layout intent is stored in the session state

`state.layout = { ratio, tree_width, columns, tree_shown, zoomed, seen }`:

- `ratio`: before width divided by before plus after width. Starts at 0.5.
- `tree_width`: remembered tree width. Starts at `config.options.tree_width`.
- `columns`: `vim.o.columns` when the layout was last synchronized. A
  different value means the terminal was resized in between.
- `tree_shown`: whether the tree window existed at the last synchronization.
- `zoomed`: whether a window was maximized at the last synchronization. A
  shrinking terminal squeezes a pane to the minimum just as a zoom does, so
  the widths after a resize cannot tell the two apart; this flag can.
- `seen`: the widths of the three windows at the last synchronization.

Sessions created before this change have no `layout`; `session.get` fills in
the defaults, so a reload with an open diff keeps working.

"Tree visible" is not stored as truth. It is always
`nvim_win_is_valid(state.wins.tree)` and the window still showing the tree
buffer; `tree_shown` only records what was seen last time.

### 2. One pure decision function

`layout.decide(input)` in `lua/twintree/layout.lua` takes plain numbers and
returns an action. Input: current `columns`, the stored `layout`, the widths
of the tree (nil when hidden), before and after windows, whether the tree
has `winfixwidth`, and the minimum width `max(1, winminwidth)`. A window is
"at minimum" when its width is not larger than that.

Rules, first match wins:

| # | Condition | Action |
|---|---|---|
| 1 | `columns` differs from stored | stored `zoomed`: only store `columns`. Otherwise `apply` stored ratio and tree width |
| 2 | tree visibility differs from `tree_shown` | `apply` stored ratio and tree width |
| 2a | widths equal `seen` | nothing, and `zoomed` stays as stored |
| 3 | tree at minimum, both panes above it | `restore`: tree to remembered width, fixed on, panes 50/50, ratio 0.5 |
| 4 | tree above minimum, both panes at minimum | `unfix`: switch the tree's `winfixwidth` off |
| 5 | any window at minimum | nothing |
| 6 | tree visible without `winfixwidth` | `restore` as in rule 3 |
| 7 | otherwise | `learn`: remember tree width and pane ratio |

Rule 2a makes a second event for the same sizes harmless. Without it the
layout the plugin itself produced in a terminal too narrow for the tree, with
the panes squeezed to the minimum, was read as a zoom by the next event and
never restored when the terminal grew again.

How the rules map to the scenarios:

- Pane zoom then equalize: rule 5 while zoomed, then rule 3.
- Tree zoom then equalize: rule 4 makes `<C-w>=` act on all three windows,
  which produces a size change; rule 6 then restores.
- Hand resize of the tree or of a pane: rule 7.
- `<C-w>=` in a normal layout: rule 7 learns ratio 0.5.
- `<C-w>c` on the tree: Neovim equalizes the panes; rule 2 puts the stored
  ratio back instead of learning 0.5 from it.

`learn` treats panes whose widths differ by at most one column as equal and
stores exactly 0.5 for them, whichever pane got the odd column. Otherwise it
changes the stored ratio only when the stored ratio would not
produce the current before width (`round(avail * ratio) ~= before`), so the
plugin's own adjustments do not make the ratio drift by rounding.

Alternative considered: remap `<C-w>|` and `<C-w>=` in the tab to plugin
functions. Rejected: it needs window-local keymaps that Neovim does not
have, and it would still miss `:vertical resize`, the mouse and `:only`.

### 3. Synchronization glue

`layout.sync(tab)` gathers the input for the current tab, calls `decide`,
performs the action with `nvim_win_set_width` and `vim.wo[win].winfixwidth`,
and saves the state. It returns early when the tab has no session or a pane
window is invalid. A module-local flag prevents re-entry while it resizes.

It is called from one autocommand on `WinResized`, `VimResized` and
`TabEnter` (the last covers a terminal resize that happened while another
tab was current). Layouts the plugin builds itself go through `reapply`,
described below, never through `sync`.

`apply` sets the tree width first, then the before width to
`round((before + after) * ratio)`, then the after width to the rest. The
after width is set explicitly because a window of the user's between the
panes would otherwise absorb the difference.

`layout.reapply(tab)` applies the stored ratio and tree width without
calling `decide`. `session.create`, `toggle_tree` and `reset_layout` use it, because the sizes
Neovim gives the windows when one is opened or closed carry no intent, and
the tree may have been hidden without any size event (another buffer put in
its window), in which case rule 2 would not fire.

### 4. The tree buffer lives as long as its tab

`treeview.create_buf` uses `bufhidden = "hide"`. A `TabClosed` autocommand
calls `treeview.sweep()`: every buffer with filetype `twintree` that is not
the `tree_buf` of a session in an existing tab is deleted with
`nvim_buf_delete(buf, { force = true })`. (As implemented the buffers are
recognized by their name prefix `twintree://tree/`, since a tree buffer
unloaded with `:bdelete` has lost its filetype.) This needs no bookkeeping about
which tab a buffer belonged to and also removes buffers left by a crash of a
previous sweep.

Alternative: delete in a `WinClosed` handler when the tab's last window
goes. Rejected: more cases, and `TabClosed` already means exactly this.

### 5. Session functions stop requiring the tree window

`session.is_intact` is replaced by `session.has_panes(state)`: both pane
windows are valid. `session.show` needs only that; when it is false it
returns an error string that names `:TwintreeResetLayout`.

`treeview.activate` already works from the cursor of the current window, so
`<CR>` works in any window that shows the tree buffer. `treeview.draw` needs
only a valid tree buffer.

`treeview.ensure_buf(tab)` returns the session's tree buffer, re-creating it
and recomputing the entries with `git.changed_files` when the buffer is no
longer a working tree buffer. That is checked with `treeview.is_tree_buf`:
valid, loaded and still of filetype `twintree`. Validity alone is not
enough, because `:bdelete` leaves the buffer valid but unloaded and without
its options, variables and mappings. `toggle_tree` and `reset_layout` use it.

### 6. `:TwintreeToggleTree`

`require("twintree").toggle_tree()` returns `true` or `nil, err`.

- No session in the current tab: `nil, "no diff session in this tab"`.
- Tree visible: when it is the only non-floating window of the tab, return
  an error that names `:TwintreeResetLayout`; otherwise close the window.
- Tree hidden: `nvim_open_win(buf, true, { split = "left", win = -1 })`
  creates a full-height window at the far left whatever else is in the tab.
  The window options of the tree are set by a helper shared with
  `session.create`. The cursor goes to the line of the selected file.
- `layout.reapply` runs afterwards and keeps the pane ratio and the tree
  width. Opening the window fails when the tab has no room for it; that is
  returned as a message.

The command in `plugin/twintree.lua` reports `err` with `vim.notify` at
error level, like `:Twintree`.

### 7. `:TwintreeResetLayout`

`require("twintree").reset_layout()` returns `true` or `nil, err`.

1. No session: `nil, "no diff session in this tab"`.
2. Close every non-floating window of the tab but one. A tab filled with
   splits has no room for another window, so the tree cannot be opened
   first.
3. Open a new far-left window with the tree buffer, as in decision 6, then
   close the remaining old window. Windows are closed with
   `nvim_win_close(win, true)`, which hides a modified buffer instead of
   failing. A buffer whose `bufhidden` would remove it is set to `hide` for
   the moment of closing and gets its setting back afterwards, so nothing is
   discarded. Failing to open a window is returned as a message.
4. Create the before and after windows to the right, as `session.create`
   does. The window-building part of `session.create` is extracted into a
   function used by both.
5. Store the new window ids, set `layout` to its defaults and `reapply`
   it.
6. When a file is selected and still listed, `session.show` it; otherwise
   leave the placeholders and keep the cursor in the tree.

Building a fresh tree window first, instead of reusing one of the user's
windows, avoids replacing a buffer in a window the plugin does not own.

### 8. Errors are messages

Both commands and `session.show` return `nil, err`; only the command layer
and the tree keymaps call `vim.notify`. No function raises for a missing
session, window or buffer. Each of these paths gets a test.

### 9. Tests

- `tests/layout_spec.lua`: table-driven tests of `layout.decide`, one row
  per rule and per scenario of the spec, including a large `winminwidth`.
- `tests/session_spec.lua` and a new `tests/layout_ui_spec.lua`: `sync`
  called directly after changing widths with `nvim_win_set_width`,
  `wincmd |` and `wincmd =`; toggling; resetting from broken layouts;
  commands in a tab without a session; tree buffer sweep.
- Terminal resize end to end: a spec starts a child Neovim in a pty with
  `jobstart({ ... }, { pty = true, width = W })`, drives it over
  `--listen` RPC, resizes with `jobresize` and reads the window widths.
  This is the only test that exercises the real events.

## Risks / Trade-offs

- [Rule 3 also fires when the user drags the tree to one column on purpose]
  → Accepted and documented: the tree is hidden with `<C-w>c` or
  `:TwintreeToggleTree`, not by squeezing it.
- [The heuristics were derived from measured widths, not from observing the
  events] → The pty test covers the event path; the manual check in the
  tasks covers what the test cannot.
- [`WinResized` is delivered after redraw, so a script that resizes and
  reads widths immediately sees the old layout] → Tests call `sync`
  directly; the pty test waits for the widths to settle.
- [The pty test may be flaky or unsupported on some systems] → It is
  skipped with a message when a pty cannot be opened; the pure tests still
  cover every rule.
- [A zoomed window is not re-maximized when the terminal is resized] →
  Documented non-goal; `<C-w>|` again fixes it.
- [`:TwintreeResetLayout` closes windows the user opened] → That is its
  stated purpose; buffers are kept, and the help text says so.
- [Another plugin opens a sidebar in the diff tab] → `sync` only sets the
  widths of the session's windows; reset closes the sidebar's window.
