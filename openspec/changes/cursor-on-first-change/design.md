# Design

## Context

`session.show(tab, entry)` is the selection path: the tree's `<CR>` and
`init.open` call it. It calls `session.show_pair`, which puts the two
buffers into the panes with `:buffer`, turns diff mode on in both, and
then `show` moves the cursor to the after pane. `show_pair` is also what
following (`session.follow`, `move_to_own_pane`) and
`init.reset_layout` use; those do not go through `show`.

Nothing places the cursor inside the file today. `:buffer` gives a buffer
that was never in a window line 1, and a buffer that was shown before the
position it had when it last left a window. So returning to a file already
works by Neovim's own bookkeeping; what is missing is the first view.

The session record is plain data in a tab variable. It is read as a copy
and has to be saved after a change.

Checked on a current Neovim build, headless, with two diffed windows that
are not the current window:

- `normal! ]c` run inside the after window moves the cursor of the before
  window to the corresponding line as well (`cursorbind`), and scrolls
  both to the same top line.
- Running `]c` in both windows gives a wrong result when the first change
  is a block that exists on one side only: the second jump drags the first
  window past the block.
- `]c` from line 1 skips a change that starts on line 1, and one that is
  only filler lines above line 1.
- `]c` in a file without changes does not move and does not raise.

## Goals / Non-Goals

**Goals:**

- The same notion of "change" as the highlighting on screen, including the
  user's `'diffopt'`.
- No new state that depends on window ids or positions.

**Non-Goals:**

- Storing cursor positions in the session record. Neovim keeps them.
- Cursor placement after `:TwintreeResetLayout`, which builds new windows.
- Centring the change or any other scrolling rule beyond what `]c` does.
- A configuration option to turn the jump off.

## Decisions

### 1. The jump is Neovim's own `]c`

After the pair is shown, in the window that gets the jump:
`keepjumps normal! gg`, then `keepjumps normal! ]c` unless line 1 already
is part of a change (`diff_hlID(1, 1) ~= 0` or `diff_filler(1) > 0`).
`normal!` ignores a user mapping of `]c`; `keepjumps` keeps the jump list
clean. The call is wrapped in `pcall`: a failed jump leaves the cursor at
the top, it must not fail the selection.

Alternative: compute the first hunk with `vim.diff` on the buffer lines.
Rejected: it would disagree with the highlighting whenever `'diffopt'`
changes what counts as a change (`iwhite`, `algorithm:`, `linematch:`).

### 2. One jump, in the pane that takes the focus

The jump runs in the after window when the pair has an after file,
otherwise in the before window. The other pane follows through
`cursorbind`. Jumping in both panes is wrong for one-sided blocks (see
Context).

For an added or deleted file the jump is a no-op: against the placeholder
the whole file is one change that starts on line 1.

### 3. The session record remembers the buffers it has shown

A new field `viewed`: a set of buffer numbers, stored as string keys
because the record lives in a tab variable. `show_pair` adds the file
buffers of both panes after it succeeded, for every caller, so that a file
reached by navigation counts. The placeholder is not added. `session.get`
defaults the field to an empty table for sessions opened by an older
version of the plugin, as it does for `layout`.

`show` reads the set before it calls `show_pair`: the file is new when the
buffer of the pane that takes the jump is not in it.

Buffer numbers, not paths: Neovim never reuses a buffer number, so a
buffer that was wiped out and loaded again is new to the session. That is
the wanted behaviour, because the position Neovim kept for it is gone with
the buffer. A set keyed by path would leave such a file at line 1.

Alternative: a buffer variable. Rejected: a working tree buffer is shared
by every diff tab, and "shown" is per session.

Alternative: mark only on `show`. Rejected: a file the user reached with
`gd` and worked in would be thrown back to its first change when it is
later selected in the tree.

Stale numbers of deleted buffers stay in the set. They are never matched
again and the set dies with the tab.

### 4. Only `show` jumps

`show_pair` itself never moves the cursor. Following has to keep the
cursor the navigating command set, and it calls `show_pair` before that
command has placed it. `reset_layout` restores a comparison, it does not
start one.

The `show` signature and its return values do not change, so the tree and
`init.open` need no change.

### 5. Returning is left to Neovim

No code for the return case, only specs that pin it down: the position
after `select A, move, select B, select A`, after selecting the file that
is already shown, and after a file first reached by a jump.

Alternative: save `winsaveview()` per file in the session record and
restore it. Rejected for now: it duplicates what Neovim does and needs a
hook on every way a buffer can leave a pane. It becomes the fallback if
the specs show that Neovim's own position is not reliable.

### 6. Layout that is not there

`show` already returns the missing pane message before anything is shown,
and the buffer is then not added to `viewed`, so the file still gets its
jump once the layout is back. After `show_pair` succeeded, the window is
checked for validity again before the jump, because the events fired while
the buffers are loaded can run user autocommands that close it; a window
that is gone means no jump and no error.

### 7. A pair with a placeholder does not scroll together

Found during implementation. With a deleted file the cursor goes to the
after pane, which shows the one-line placeholder. As soon as a command
ends there, Neovim scrolls the bound before pane to the end of the file,
so a deleted file was never shown from its top. `set_diff` therefore turns
`'scrollbind'` off in a pane when the pair has a file on one side only.
The pane stays in diff mode, and the option comes back with the next pair
that has both sides, because diff mode is switched off and on for every
pair.

`'cursorbind'` stays on: it does not move the file, and it was not the
cause.

## Risks / Trade-offs

- [When the first change is a block that exists on the before side only,
  the before cursor is below that block, not on its first line] → It is
  the line bound to the after cursor, and any movement in the after pane
  would put it there anyway. The block is on screen right above it.
- [Before pane depends on `cursorbind` to follow] → The specs assert the
  cursor and the top line of the before pane, not only of the after pane.
  If a Neovim version does not sync inside `nvim_win_call`, the fix is to
  run the jump after the after pane became the current window.
- [A user who relies on line 1 after selecting a file] → Line 1 is one
  `gg` away; no option until someone asks.
- [A working tree file the user already had open elsewhere is moved to its
  first change, not to the position it had in the other window] → Wanted:
  the pane is a different window, and the other window keeps its cursor.
- [Existing specs that assert a cursor line after a selection] → The whole
  suite is run right after the change in `show`, before new specs are
  added; assertions are adjusted to what they test, not weakened.
