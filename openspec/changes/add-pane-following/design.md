# Design

## Context

See `proposal.md` for the motivation.

`session.sync_diff` runs on `BufWinEnter` and `BufEnter`. When the current
window is a pane, it switches diff mode on if the pane shows the buffer
recorded in `state.bufs` and off otherwise. `session.show` is the only code
that puts a pair of buffers into the panes, and it is only called for an
entry of the tree. `state.selected` is the path of that entry;
`reset_layout` and the tree refresh look the entry up again by that path, so
they cannot handle a file that is not in the tree.

Both sides are directories on disk (`state.before.root`,
`state.after.root`), and the changed-file entries carry `old_path` for
renames. That is enough to find the counterpart of any file.

Checked in headless Neovim (a 0.13 development build) while exploring:

- A quickfix jump fires `BufEnter` before it places the cursor. A callback
  scheduled from that `BufEnter` sees the final cursor position.
- In a real terminal the screen is drawn once before a scheduled callback
  runs. `SafeState` fires after the command has finished and before that
  draw, but not for a jump made by a mapping or a callback.
- A buffer that is hidden while its window is in diff mode stays a
  participant of the diff. Showing another pair then gives a three-way
  diff in which every line is highlighted.
- A quickfix jump does not use a window that shows a buffer with a
  `buftype`, such as the empty placeholder; it opens a new window.
- An autocommand that is not nested loads a buffer without firing the
  events that set its filetype.
- When the counterpart is put into the other window and diff mode is
  switched on, inside `BufEnter` or later, Neovim positions the other window
  on the corresponding line of the diff by itself.
- `:keepalt buffer N` leaves the alternate file of the window unchanged;
  `nvim_win_set_buf` does not.
- With `winfixbuf` set on a window, quickfix commands run from it open the
  file in another window, `:edit` and `nvim_win_set_buf` fail with E1513,
  `:help` opens its own window, and deleting the buffer the window shows
  closes the window.

## Goals / Non-Goals

**Goals:**

- One rule for every way a buffer can enter a pane, with no key mappings and
  no dependence on which command caused it.
- A comparison that survives the tree being hidden, a layout reset and a
  refresh, also for files that are not in the tree.
- No traceback and no change to other windows when a pane is missing.

**Non-Goals:**

- An option to switch following off.
- Keeping two different files in the two panes. A window the user opens
  with `:split` serves that purpose.
- Restoring the tree when the user switches `winfixbuf` off and replaces it.
- Controlling which window Neovim picks for a quickfix jump.

## Decisions

### React to the buffer change, not to the command

The existing `BufWinEnter`/`BufEnter` autocommand stays the single entry
point; its handler replaces `sync_diff`. Alternatives: remapping `<CR>` in
quickfix windows misses `:cnext`, `:cc` and jumps made by other plugins;
`switchbuf` is a global option of the user and knows nothing about sides.

### The session records the compared pair as paths

The session gets a record of what the panes compare, next to the existing
fields:

```
state.pair = {
  before = <absolute path, or nil for the placeholder>,
  after  = <absolute path, or nil for the placeholder>,
}
```

`state.bufs` stays as the buffers currently standing for that pair. Paths
are kept besides buffers because a buffer can be deleted while the
comparison should survive a layout reset. `state.selected` keeps its name
and meaning for the tree, the path of the entry to mark, but is now derived
from the pair and is `nil` when the compared file is not listed.
`session.get` fills `pair` from `selected` for a session that was saved
before pairs existed, so that it keeps working after a plugin reload.

One function, `show_pair`, puts a pair into the panes, records it and
switches diff mode on. `show(tab, entry)` becomes: compute the pair of the
entry, call `show_pair`, move the cursor to the after pane. `reset_layout`
calls `show_pair` with the recorded pair instead of looking up an entry.

### Pairing a file with its counterpart

For a buffer that entered a pane:

1. It is a file buffer when `buftype` is empty and it has a name. Anything
   else is not followed.
2. Its side is the side whose root is a prefix of its resolved path. When
   both roots match (one root inside the other), the longer root wins. The
   path is resolved the way `worktree.is_cached` does it, so a file that
   does not exist yet is still classified.
3. No side: the pair is that path on both sides.
4. Otherwise the relative path is mapped to the other side:
   - before to after: the entry whose `old_path` equals it gives
     `entry.path`; otherwise the same relative path.
   - after to before: the entry whose `path` equals it gives
     `entry.old_path or entry.path`; otherwise the same relative path.
   The result is `nil` (placeholder) when no regular file exists there, as
   `file_buf` decides today.
5. `state.selected` is the path of the entry whose after path, or whose
   before path, is the one in the pair; `nil` when there is none.

The entries are read from the tree buffer, as today. When the tree buffer
is gone (the user deleted it), mapping falls back to the same relative path
and nothing is marked until the tree is rebuilt.

### What the handler does

```
buffer B entered window W of a diff tab
  W is not a pane of the session       -> nothing
  B is the recorded buffer of W        -> diff on (as today)
  B is not a file buffer               -> diff off in W (as today)
  the other pane window is missing     -> diff off in W
  B belongs to W's side, or to no side -> show_pair now
  B belongs to the other side          -> schedule a move
```

The move has to wait until the command that caused the jump has placed the
cursor. It is registered twice: as a one-shot `SafeState` autocommand, which
runs before the screen is drawn and so avoids a flash of the file in the
wrong pane, and with `vim.schedule`, which covers jumps made by a mapping or
a callback, where `SafeState` does not fire. Whichever runs second finds
the file already moved and does nothing.

The move checks again that the tab, the session, both panes and "W still
shows B" hold, and gives up silently otherwise. Then it saves the view of W
(`winsaveview`), shows B in its own pane, shows the counterpart in W with
`:keepalt buffer`, restores the view, switches diff mode on in both and
makes the pane of B current if W was current. B goes to its pane first so
that it is never hidden on the way.

The view is carried between two windows that show the same buffer, so it is
exact. No position is ever computed between two different files; diff mode
does that.

Alternative considered: always schedule. Rejected because the common case
does not need it, and doing it inside the event leaves no moment in which
the other pane shows the old file.

### The autocommand is nested

The handler loads the counterpart into the other pane from inside an
autocommand. The autocommand is declared `nested` so that this load fires
the usual events: without them the buffer has no filetype, and a file of a
cached worktree is not made read-only.

### Buffers that leave the panes leave the diff

After a pair is replaced, each buffer of the old pair that no window shows
any more is taken out of the diff (`:diffoff` run for that buffer).
Otherwise Neovim keeps it as a hidden participant and the new pair is
diffed three ways. A buffer that some window still shows is left alone.

### New windows of a diff tab leave diff mode

Neovim copies the window options of a pane, diff mode included, into a
window split off it, and a file opened there joins the diff. A `WinNew`
autocommand switches diff mode off in any new window of a diff tab that is
not a pane. The windows the plugin opens for the panes are created without
diff mode and get it from `show_pair`, so they are not affected.

### Recursion guard is the recorded pair

`show_pair` records `state.bufs` before it changes any window. The events
its own buffer changes fire therefore hit the "B is the recorded buffer of
W" branch and stop. No flag is needed, and the guard survives a module
reload because it is session state.

### The tree window uses `winfixbuf`

`setup_tree_window` sets `winfixbuf`. Neovim then never puts another buffer
into the tree window, and quickfix jumps made from the tree land in a pane,
where the handler above sorts them. `session.tree_win` keeps its check that
the window still shows the tree buffer: it protects toggle, layout and
redraw code when the user switched the option off, and it is not extended
to repair that case.

Alternative considered: let the file land in the tree window and move it
out afterwards. It needs a second fix-up path and briefly destroys the
tree view.

### The tree mark and refresh

The tree marks the line of `state.selected`. After `show_pair` the tree is
redrawn, and when the tree window is visible its cursor is moved to the
marked line without taking focus. A file inside a collapsed directory has no
visible line; the directory is not expanded.

`refresh` no longer calls `clear_selection` when the shown file is not
listed. It recomputes `state.selected` against the new entries and redraws.
`clear_selection` remains for the layout reset with nothing to show.

## Risks / Trade-offs

- [The move of a file to its own pane can be visible as a flash] -> For a
  jump the user types, `SafeState` moves the file before the screen is
  drawn; a test in a pseudo-terminal child counts the redraws that show the
  file in the wrong pane and expects none. A check by eye in a terminal
  showed no flash either. A jump made by a mapping or a callback is moved
  by the scheduled call, after one such redraw.
- [A quickfix jump made from a pane that shows the empty placeholder opens
  a new window, which does not follow] -> Accepted; a placeholder pane has
  no code to jump from.
- [A non-file buffer the user put into a pane is replaced when the other
  pane navigates] -> Accepted: the buffer stays loaded and hidden, and a
  window made with `:split` is the way to keep something next to the diff.
- [The same buffer in both panes for an outside file means an edit shows on
  both sides] -> Accepted; such files are normally read-only dependencies.
- [`winfixbuf` makes `:edit` in the tree an error instead of doing
  something] -> Accepted; the message is Neovim's own and names the option.
- [Existing tests put a buffer into the tree window or expect diff mode to
  switch off after a jump] -> They are rewritten in the task groups that
  change the behaviour, not at the end.
- [Behaviour of `winfixbuf` and of diff positioning was checked on one
  development build] -> Tests pin each of the four observations listed under
  Context, so a difference on Neovim 0.11 shows up in `make test`.
- [Following loads a second buffer on every jump, which can start a language
  server for the other side] -> This already happens for every file selected
  in the tree; no mitigation.
