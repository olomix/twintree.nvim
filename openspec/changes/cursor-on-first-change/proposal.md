# Proposal

## Why

A changed file is shown with the cursor on its first line, so the user has
to press `]c` in every file before any change is on screen. A diff viewer
should put the first change in front of the user.

## What Changes

- The first time a changed file is shown in a session, by selecting it in
  the tree or as the first file when the session opens, the cursor of the
  after pane is on the first change, and the before pane is on the
  corresponding line. A file without a change to jump to (same content on
  both sides, an added or a deleted file) stays at the top.
- When the user comes back to a file the session has already shown, the
  cursor is where they left it, not on the first change again.
- Navigation is not overridden: a file reached by a jump (definition,
  quickfix entry, jump list, `:edit`) keeps the cursor the jump gave it,
  and counts as shown from then on.
- The jump to the first change adds no entry to the jump list.
- A deleted or added file is shown from its top and stays there. Until
  now a deleted file was scrolled to its end as soon as a command ended
  in the empty after pane.

Not part of this change: jumping between changed files, centring the
change in the window, and where the cursor is after
`:TwintreeResetLayout`.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `diff-session`: two new requirements, one for the cursor of a file shown
  for the first time and one for a file shown again.

## Impact

- `lua/twintree/session.lua`: the session record remembers which buffers
  it has shown; `show` places the cursor after a pair is shown.
- `tests/session_spec.lua`, `tests/follow_spec.lua`,
  `tests/layout_ui_spec.lua`: new specs. Existing specs that assume the
  cursor is on line 1 after a selection may need their setup adjusted.
- `README.md`, `doc/twintree.txt`, `TODO.md`.
