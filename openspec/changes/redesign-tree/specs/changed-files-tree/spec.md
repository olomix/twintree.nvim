# Spec Delta

## ADDED Requirements

### Requirement: Layout of a tree line
A file line SHALL show, from left to right: the indentation, the icon when
there is one, the file name, the line counts when there are any, and the
status letter. The status letter SHALL be the last character at the right
edge of the tree window, with the line counts directly before it. The marker
of a directory that exists on one side only SHALL be at the same right edge.

#### Scenario: File line
- **WHEN** a modified file with 5 added and 3 deleted lines is listed
- **THEN** its line shows the name on the left and `+5 -3 M` at the right
  edge of the window

#### Scenario: Status letters form a column
- **WHEN** several files with names of different lengths are listed
- **THEN** their status letters are in the same column, the last one of the
  window

#### Scenario: Directory on one side only
- **WHEN** a directory exists only on the after side
- **THEN** its line ends with `A` in the column of the status letters

### Requirement: Line counts
The tree SHALL show for each file the number of lines added and deleted
between the two sides, in the form `+added -deleted`, with the additions
highlighted as added and the deletions as deleted. An untracked file of the
working tree SHALL be shown with all of its lines added. A file for which
the counts are not available, such as a binary file, SHALL show no counts.

#### Scenario: Modified file
- **WHEN** a file has 23 added and 18 deleted lines
- **THEN** its line shows `+23 -18`

#### Scenario: Added and deleted files
- **WHEN** one file was added with 40 lines and another with 53 lines was
  deleted
- **THEN** their lines show `+40 -0` and `+0 -53`

#### Scenario: Untracked file
- **WHEN** the after side is the working tree and it contains an untracked
  file of 12 lines
- **THEN** its line shows `+12 -0`

#### Scenario: Binary file
- **WHEN** a changed file is binary
- **THEN** its line shows the status letter and no counts

#### Scenario: Renamed file
- **WHEN** a file was renamed and 2 of its lines were changed
- **THEN** its line shows the counts of that change under the new name

### Requirement: Icons
When an icon plugin is installed and icons are not switched off, a file line
SHALL show the icon of the file's type before the name, and a directory line
SHALL show a folder glyph that differs between an open and a folded
directory. Without an icon plugin, or with icons switched off, file lines
SHALL have no icon and directory lines SHALL show an arrow that differs
between open and folded.

#### Scenario: Icon plugin installed
- **WHEN** an icon plugin is installed and a Lua file is listed
- **THEN** its line shows the plugin's icon for Lua files before the name,
  in the plugin's colour for it

#### Scenario: Folder glyphs
- **WHEN** an icon plugin is installed
- **THEN** an open directory and a folded directory show different folder
  glyphs

#### Scenario: No icon plugin
- **WHEN** no icon plugin is installed
- **THEN** file lines start with the name, directories show arrows, and no
  error is reported

#### Scenario: Icons switched off
- **WHEN** an icon plugin is installed and the `icons` option is false
- **THEN** the tree looks as it does without an icon plugin

### Requirement: Names that do not fit
A name that does not fit between the icon and the right-hand block SHALL be
cut in the middle and the cut marked with an ellipsis, so that the beginning
of the name and its extension stay visible. A line SHALL never be wider than
the tree window. Widths SHALL be measured in display cells, so that names
with wide or non-ASCII characters are cut and aligned correctly.

#### Scenario: Long file name
- **WHEN** a file named `kz_028_promotion_events.sql` does not fit
- **THEN** its line shows the beginning of the name, an ellipsis and the end
  of the name including `.sql`

#### Scenario: Long directory chain
- **WHEN** a directory line shows a chain such as `a/very/long/chain/` that
  does not fit
- **THEN** the chain is cut in the middle in the same way

#### Scenario: Non-ASCII name
- **WHEN** a long file name contains wide characters
- **THEN** the line is exactly as wide as the window and the status letter
  is in its column

### Requirement: Order of giving way
When a line does not fit, the tree SHALL give up parts in this order: the
rename origin is left out; the name is cut down to a minimum length; the
line counts are left out; the name is cut further. The status letter SHALL
always be shown.

#### Scenario: Slightly too narrow
- **WHEN** the name and the counts do not fit together but a shortened name
  of at least the minimum length does
- **THEN** the name is cut and the counts are shown

#### Scenario: Much too narrow
- **WHEN** even the minimum name and the counts do not fit together
- **THEN** the counts are left out and the name is cut to what fits

#### Scenario: Extremely narrow
- **WHEN** the window is only a few cells wide
- **THEN** the line still ends with the status letter and no error is raised

### Requirement: Rename origin
The line of a renamed file SHALL show where it came from, after the new
name, only when the full new name, the origin, the line counts and the
status letter all fit. For a rename within the same directory the origin
SHALL be the old file name alone; otherwise it SHALL be the old path.

#### Scenario: Room for the origin
- **WHEN** a file was renamed from `api.go` to `client.go` in the same
  directory and the window is wide enough
- **THEN** the line shows `client.go`, then the origin `api.go`, then the
  counts and `R`

#### Scenario: Renamed into another directory
- **WHEN** a file was moved from `old/api.go` to `new/api.go` and the window
  is wide enough
- **THEN** the origin shown is `old/api.go`

#### Scenario: No room for the origin
- **WHEN** the origin does not fit
- **THEN** the line shows the new name, the counts and `R`, and no origin

### Requirement: Indent guides
The tree SHALL draw a vertical guide for each level of nesting in front of
the lines inside a directory.

#### Scenario: Nested file
- **WHEN** a file is two directories deep
- **THEN** its line starts with two guides, one per level

#### Scenario: Top level
- **WHEN** a file or directory is at the top level
- **THEN** its line has no guide

### Requirement: The tree follows the width of its window
The tree SHALL be drawn for the width of the window that shows it, and SHALL
be drawn again when that width changes, so that the status letters stay at
the right edge and names are cut for the current width.

#### Scenario: Widening the tree
- **WHEN** the user makes the tree window wider
- **THEN** names that were cut are shown longer or in full and the status
  letters are at the new right edge

#### Scenario: Narrowing the tree
- **WHEN** the user makes the tree window narrower
- **THEN** no line is wider than the window

#### Scenario: Tree shown again
- **WHEN** the tree was hidden and is shown again with a different width
- **THEN** it is drawn for that width

#### Scenario: Selecting after a redraw
- **WHEN** the tree was redrawn for another width and the user presses
  `<CR>` on a file line
- **THEN** that file is shown, whatever part of its name is visible
