# Proposal

## Why

The tree of changed files shows a status letter and a name, nothing more. A
reviewer cannot see how large a change is, cannot tell file types apart at a
glance, and loses the end of a long file name, extension included, at the
window edge. The layout familiar from web code review tools carries more in
the same space: an icon, the name, the number of changed lines and the
status, aligned in columns.

## What Changes

- Show a file icon before each file name when `nvim-web-devicons` or
  `mini.icons` is installed, and open and closed folder glyphs for
  directories. Without an icon plugin, files have no icon and directories
  keep the arrows.
- Show the number of added and deleted lines after the name, coloured as
  additions and deletions. Untracked files are counted and shown as added
  lines. Binary files and other entries without line counts show none.
- Move the status letter to the right edge of the window, with the line
  counts directly before it, so that both form a column. The markers of
  directories that exist on one side only move to the same column.
- Cut a name that does not fit in the middle, so that its beginning and its
  extension stay visible.
- Show where a renamed file came from only when the whole line still fits;
  for a rename within the same directory show only the old file name.
- Draw an indent guide for each nesting level.
- Redraw the tree when the width of its window changes, since lines now
  depend on that width.
- Add an `icons` option to switch icons off.

When the window narrows, a line gives way in this order: the rename origin
is dropped, the name is cut down to a readable minimum, the line counts are
dropped, and the name is cut further. The status letter always stays.

Out of scope: glyphs in place of the status letters, configurable column
order, icons for the status column, and git status of the working tree
beyond what the diff already shows.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `changed-files-tree`: new requirements for the layout of a tree line (icon,
  line counts, right-aligned status), for names that do not fit, for the
  rename origin, for indent guides and for following the window width. No
  existing requirement changes its meaning: status markers, directory
  markers, nesting, folding and selection stay as specified.

## Impact

- `lua/twintree/tree.lua` (line builder takes a width and an icon source),
  `lua/twintree/treeview.lua` (width, redraw, highlights),
  `lua/twintree/changes.lua` and `lua/twintree/git.lua` (line counts),
  `lua/twintree/config.lua` (`icons` option), `plugin/twintree.lua` (redraw
  on size change), and a new `lua/twintree/icons.lua`.
- One more git call per refresh (`git diff --numstat`) and one read of every
  untracked file to count its lines.
- Optional dependencies: `nvim-web-devicons` or `mini.icons`. Folder glyphs
  and most file icons need a Nerd Font; that is the icon plugin's
  requirement, not a new one.
- Every test that asserts the text of a tree line changes.
- `README.md`, `doc/twintree.txt` and `TODO.md` are updated.
