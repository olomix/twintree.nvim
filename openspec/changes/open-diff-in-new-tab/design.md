# Design

## Context

`session.create()` opens the layout of a diff. It calls `:tabnew` unless
`is_blank_tab()` is true: one tab, one window, an unnamed, unmodified,
empty buffer. In that case it turns the current window into the tree
window of the diff. Nothing else reads `is_blank_tab()`.

Two lines after that exist for the reused tab:

- The buffer of the window gets `bufhidden=wipe`, so that the empty
  buffer goes when the tree takes its place. `:tabnew` always makes a new
  empty buffer, so this still applies.
- `'winfixbuf'` of the window is switched off, because the reused window
  could be what is left of an earlier diff, its tree window. A window
  made by `:tabnew` never has the option: Neovim does not copy
  `'winfixbuf'` to a new window. A spec in `tests/follow_spec.lua` opens
  a diff in a window that was the tree of an earlier one.

`open()` in `init.lua` calls `create()` without a guard. When
`open_panes()` raises, as with E36 in a terminal too small for three
windows, the error leaves `open()` as a Lua error. With the reused tab
that left one tab; after `:tabnew` it would leave the new tab behind,
with a tree buffer and no session.

After `create()`, `open()` calls `keys.sync()`; a comment says that no
`TabEnter` fires for a diff in the tab Neovim started with. With
`:tabnew`, `TabEnter` fires on every open, but inside `:tabnew`, before
the session is saved, so the autocommand finds no session and binds
nothing. The call stays necessary.

A session ends with its tab. On `TabClosed` the plugin deletes every
tree buffer that no session owns and releases the buffers and language
servers of worktrees no diff uses.

`:tabclose` in the only tab fails with E784. The README and the help
file say so and point to `:qa`; they also say that a diff started from
the shell uses the first tab.

Checked with the change applied to a copy of the repository, on Neovim
0.11, 0.12 and nightly:

- `nvim +Twintree` gives two tabs with the diff tab current when
  `VimEnter` fires. The diff tab has three windows, also with netrw
  loaded, whose `:windo` on `VimEnter` visits the current tab only. The
  first tab keeps buffer 1, listed, with no `bufhidden`.
- `:tabclose` then succeeds, lands in the first tab, and leaves no
  session, no tree buffer and no key of the plugin.
- `nvim file +Twintree`, `nvim -p a b +Twintree` and `nvim -d a b
  +Twintree` never had a blank tab and are not affected. With `-p`, the
  diff tab is between the others, and `:tabclose` goes where Neovim's
  `'tabclose'` says.
- Ten existing specs fail, the same on each version: eight count tabs,
  one uses `gt` to reach the diff tab, one measures the row and height
  of the tree, which the tab line moves by one.

See proposal.md for the motivation.

## Goals / Non-Goals

**Goals:**

- A diff can be ended with `:tabclose` without the user doing anything
  first.
- One way for a session to end, so that the cleanup on a closed tab runs
  for every diff.
- A failed open leaves the tabs as they were.

**Non-Goals:**

- A command that ends a diff.
- A diff that the user turned into the only tab. `:tabclose` refuses
  there; the documents say what to do.
- Removing the empty first tab later, or touching `'showtabline'`.

## Decisions

### 1. Always `:tabnew`

`create()` calls `:tabnew` unconditionally, and `is_blank_tab()` is
removed. `bufhidden=wipe` on the buffer of the new window stays. The
reset of `'winfixbuf'` and its comment are removed: a window made by
`:tabnew` cannot have the option. The spec in `tests/follow_spec.lua`
that guarded the reset is removed with it; `tests/helpers.lua` keeps its
own reset, which is for the window that `:tabonly` leaves.

The empty tab is the first one and the diff tab is current, which is
what `:tabnew` gives.

Alternative: keep the single tab and add a command that turns the three
windows back into one. Rejected by the owner: the plugin would have to
undo by hand what a closed tab undoes for free, the windows, their
options and the session record, in every state the user can leave the
layout in.

Alternative: open the second, empty tab only when the user tries to end
the diff. Rejected: there is no event for a refused `:tabclose`.

### 2. A layout that cannot be made closes its tab

`create()` runs everything after `:tabnew` in `pcall`. On an error it
closes the tab it opened with `:tabclose!`, when that tab is still valid
and not the only one, makes the tab the command was run in current
again, since which tab follows a closed one is the user's setting, and
returns `nil` and a message that names the reason. `open()` then calls
`treeview.sweep()`, which deletes the tree buffer no session owns, and
passes the message to its `fail()`, which removes the worktrees the
command created.

`open()` does not rely on `TabClosed` for this: Neovim fires no
`TabClosed` for a tab that is closed inside another autocommand. For the
same reason the existing path for a tab that an autocommand closes while
the first file is shown now calls `treeview.sweep()` and
`worktree.release()` itself; until now it left the tree buffer behind.

Alternative: check the size of the terminal first. Rejected: the room
needed depends on options and on the user's windows; trying and undoing
is exact.

### 3. The comment in `open()`

The comment before `keys.sync()` in `open()` is rewritten: `TabEnter`
fires inside `:tabnew`, before the session exists. The call stays.

### 4. Specs

All of these are part of the first task, so that the suite passes after
each task:

- `tests/session_spec.lua`: the spec for the lone empty tab expects a
  second tab with the first unchanged, and is renamed. The spec for a
  tab closed by an autocommand while the first file is shown also runs
  from the blank tab. A new spec makes pane creation fail and expects
  one tab, the origin window current, no session, no tree buffer and no
  worktree.
- The specs that count tabs after opening a diff in an empty Neovim, in
  `session_spec`, `keys_spec`, `startup_spec` and `resize_spec`, get the
  new count. The keys spec for a diff "in the only tab" keeps its point,
  that the keys work at once when the first file was not shown, and is
  renamed. The key check at startup already exists in `resize_spec`; no
  second one is added.
- `tests/resize_spec.lua`: the spec that goes to another tab and back
  uses `gT`, since `gt` from the new tab now reaches the empty one.
- `tests/layout_ui_spec.lua`: the spec that checks the place of the tree
  takes the row of the tab line into account; the checks of position and
  height stay.
- `tests/follow_spec.lua`: the spec for a window that was the tree of an
  earlier diff is removed (decision 1).
- `tests/startup_spec.lua`: the report of the child also gives the
  number of tabs, the current tab, and the first tab's windows and its
  buffer: number, listed, `bufhidden`. New specs run `:tabclose` after
  startup, once with the layout intact and once after closing a pane and
  opening a window, and report that it succeeded, the current tab, the
  session and whether a tree buffer is left.
- A spec for a diff left as the only tab: after `:tabonly` in the diff
  tab, `:tabclose` fails and the session is still there.

### 5. Documentation

- `README.md`: "From the shell, the diff uses the first tab" becomes a
  diff in a second tab next to the empty one.
- `doc/twintree.txt`: "When Neovim was just started and shows only an
  empty buffer, that tab is used instead" goes; a diff always opens in a
  new tab.
- Both, where closing the diff is described: `:tabclose` ends the diff
  and, after `nvim +Twintree`, lands in the empty tab; `:qa` quits; when
  the diff is the only tab because the others were closed, `:tabclose`
  refuses, and `:tabnew` followed by closing the diff tab, or `:qa`, is
  the way out. One line says that the empty buffer of the first tab
  stays listed.

## Risks / Trade-offs

- [The tab line appears at startup and an empty tab stays, with its
  buffer in the buffer list] → Accepted by the owner; it is what makes
  `:tabclose` work.
- [`:q` in each window of a diff started from the command line no longer
  quits Neovim] → Documented; `:qa` quits.
- [A user closes the empty tab to be rid of the tab line and is back
  where `:tabclose` refuses] → Accepted by the owner; documented with the
  way out.
- [A script or mapping of a user that relies on `nvim +Twintree` having
  one tab] → The change is stated in the README and the help file.

## Open Questions

None.
