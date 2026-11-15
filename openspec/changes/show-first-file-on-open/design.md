# Design

## Context

`init.open` resolves the range, prepares the worktrees, lists the changed
files, then calls `session.create` and `treeview.set_entries`. After that
the cursor is in the tree window and both panes show the placeholder.

Selecting a file is `session.show(tab, entry)`: it shows the pair, marks
the tree line, moves the cursor to the after pane, and returns
`false, message` when a file is not opened or a pane is missing. In that
case the panes and the session record are as before the call.

See proposal.md for the motivation.

## Goals / Non-Goals

**Goals:**

- Reuse the selection path unchanged, so that everything specified for a
  selection (swap files, placeholders, renames, the tree mark) holds for
  the file shown on open.

**Non-Goals:**

- Cursor position inside the shown file.
- Showing a file after a refresh of a session that opened with no changes.
- An option to open with empty panes.

## Decisions

### 1. `init.open` shows the file, after the tree is filled

`open` calls `session.show` right after `treeview.set_entries`.

Alternative: do it inside `session.create`. Rejected: `create` builds the
layout and does not know the entries; the tree is filled after it returns.

### 2. The first file comes from the tree lines

The tree view gets a function that returns the entry of the first line of
type `file`, built from the same lines the tree draws. `open` passes that
entry to `session.show`.

Alternative: `entries[1]`. Rejected: entries are in the order git reports
them, and the tree sorts and groups them, so the shown file would not be
the one at the top. The planned jump to the next changed file will walk the
tree order as well.

No directory is collapsed when a session opens, so the first file line is
always present when there are entries.

### 3. A file that is not opened does not fail the open

`open` returns `tab, message` in that case. The `:Twintree` command already
reports a returned message, so the user gets one line and keeps the session
with the tree. The worktrees created for the session are kept: the session
uses them.

Alternative: treat it as a failed open, close the tab and remove the
worktrees. Rejected: declining one file is not a reason to lose the list of
changed files, and it would differ from a declined selection, which leaves
the session in place.

Callers that test `open` with `assert(twintree.open())` keep working,
because the tab is returned first.

### 4. The cursor on failure

`session.show` moves the cursor only on success, and `session.create`
leaves it in the tree window. Nothing extra is needed for the cursor to be
in the tree when the file is not opened.

### 5. Existing specs

Many specs open a session for a diff with changes and then assert empty
panes, the cursor in the tree, or a first selection. Each one is adjusted
to what it tests: a spec about selection or following keeps working with a
file already shown or selects another file; a spec that needs empty panes
gets them from a diff with no changes, or from a session opened before the
files change and refreshed afterwards.
Assertions are not weakened to make them pass.

### 6. The layout is recorded again after the file is shown

Found during implementation. Moving the cursor into the after pane makes
Neovim widen that window to `'winwidth'`. In a terminal too narrow for the
layout this changes the widths recorded when the session was created, and
the next synchronization reads the squeezed windows as a zoom made by the
user; the layout then does not come back when the terminal is widened,
which breaks "Diff opened in a narrow terminal" of `diff-layout`. `open`
therefore calls `layout.reapply` after the file is shown, as the plugin
does after every change of the windows it makes itself.

The same happens today when a file is selected by hand in a narrow
terminal. That case is not changed here.

## Risks / Trade-offs

- [A swap file prompt during `:Twintree`, including `nvim +Twintree` at
  startup] → It is the prompt the user would get one keypress later. An
  end-to-end case in the real terminal covers the startup path, where the
  prompt depends on a user interface being attached.
- [Opening gets slower by the time it takes to load two buffers] → Same
  cost as the first selection, which nearly every session pays anyway.
- [Wide churn in existing specs] → Decision 5; the whole suite is run after
  the change in `open`, before new specs are added.
