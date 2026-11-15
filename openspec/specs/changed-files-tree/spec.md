# changed-files-tree Specification

## Purpose

Shows which files differ between the two sides of a diff session as a
navigable tree, and lets the user pick the file to compare.

## Requirements

### Requirement: List changed files
The tree SHALL contain every file that differs between the before side and
the after side, each with a status of added, modified, deleted or renamed.
Renames SHALL be detected and shown as one entry under the new path.

#### Scenario: Two committed revisions
- **WHEN** a session compares two commits
- **THEN** the tree lists exactly the files that differ between those commits

#### Scenario: Working tree with staged and unstaged changes
- **WHEN** the after side is the working tree
- **THEN** the tree lists files with staged changes and files with unstaged
  changes relative to the before commit

#### Scenario: Untracked files
- **WHEN** the after side is the working tree and it contains untracked files
  that are not ignored
- **THEN** those files are listed as added, and ignored files are not listed

#### Scenario: Unusual file names
- **WHEN** a changed file name contains spaces or non-ASCII characters
- **THEN** the file is listed under its exact name and can be opened

#### Scenario: Control characters in a file name
- **WHEN** a changed file name contains a newline or another control
  character
- **THEN** the file is listed on a single line with the character shown as an
  escape, and it can be opened

#### Scenario: Untracked nested repository
- **WHEN** the working tree contains an untracked directory that is itself a
  git repository
- **THEN** that directory is not listed

### Requirement: Tree presentation
The tree SHALL group files under their directories, show directories before
files, sort entries by name within a directory, and show a status marker with
a distinct highlight for each file. A chain of directories that each contain
only one directory SHALL be shown as a single line.

#### Scenario: Nested files
- **WHEN** `src/a.lua` and `src/b.lua` are changed
- **THEN** the tree shows one `src/` line with both files indented below it

#### Scenario: Single-child chain
- **WHEN** the only changed file is `a/b/c/file.go`
- **THEN** the tree shows one directory line `a/b/c/` with `file.go` below it

#### Scenario: No changes
- **WHEN** the two sides do not differ
- **THEN** the tree shows a message that there are no changes and both panes
  are empty

### Requirement: Mark directories that exist on one side only
A directory line SHALL carry an added marker when the directory does not
exist on the before side and a deleted marker when it does not exist on the
after side. The marker SHALL be highlighted like the status marker of a file
of that status; the directory name keeps its normal highlight. A directory
that exists on both sides SHALL carry no marker.

#### Scenario: New directory
- **WHEN** a changed file is in a directory that does not exist on the before
  side
- **THEN** the directory line is marked as added

#### Scenario: Removed directory
- **WHEN** all files of a directory were deleted and the directory does not
  exist on the after side
- **THEN** the directory line is marked as deleted

#### Scenario: Directory on both sides
- **WHEN** a directory exists on both sides
- **THEN** its line has no marker

### Requirement: Select a file
Pressing `<CR>` on a file line SHALL make that file the selected file of the
session and move the cursor to the after pane. The selected file SHALL be
visibly marked in the tree.

#### Scenario: Selecting a file
- **WHEN** the user presses `<CR>` on a file line
- **THEN** the file is shown in both panes, its tree line is marked as
  selected, and the cursor is in the after pane

### Requirement: Fold directories
Pressing `<CR>` on a directory line SHALL toggle whether its content is
shown. Directories SHALL start expanded.

#### Scenario: Collapsing a directory
- **WHEN** the user presses `<CR>` on an expanded directory line
- **THEN** the lines below that directory disappear and the directory is
  shown as collapsed

#### Scenario: Expanding a directory
- **WHEN** the user presses `<CR>` on a collapsed directory line
- **THEN** its content is shown again

### Requirement: Refresh
Pressing `R` in the tree SHALL recompute the list of changed files and
redraw the tree, keeping the collapsed directories and the selected file
when they still exist. A refresh SHALL NOT change what the panes show.

#### Scenario: New change in the working tree
- **WHEN** a file in the working tree is modified after the session opened
  and the user presses `R`
- **THEN** the file appears in the tree

#### Scenario: Shown file is not listed
- **WHEN** the panes compare a file that is not among the changed files and
  the user presses `R`
- **THEN** the panes still show that file in diff mode and no line of the
  tree is marked

#### Scenario: Shown file becomes listed
- **WHEN** the panes compare a working tree file that was not changed, the
  file is then modified on disk and the user presses `R`
- **THEN** the file appears in the tree and its line is marked

### Requirement: Tree buffer is not editable
The tree SHALL be shown in a buffer that the user cannot modify and that is
not associated with a file.

#### Scenario: Attempt to edit
- **WHEN** the user tries to insert text in the tree buffer
- **THEN** the buffer content does not change

### Requirement: The mark follows the panes
The tree SHALL mark the line of the file the panes compare, also when the
user reached that file by navigation in a pane. The tree SHALL mark no line
while the panes compare a file that is not among the changed files.

#### Scenario: Jump to a changed file
- **WHEN** the user jumps in a pane to a file that is listed in the tree
- **THEN** the line of that file is marked and the line of the previous file
  is not

#### Scenario: Jump to a file that did not change
- **WHEN** the user jumps in a pane to a file that is not listed in the tree
- **THEN** no line of the tree is marked

#### Scenario: Renamed file reached under its old path
- **WHEN** the user jumps in the before pane to the old path of a renamed
  file
- **THEN** the line of the renamed file is marked

#### Scenario: Tree hidden during the jump
- **WHEN** the tree is hidden, the user jumps to a changed file in a pane
  and then shows the tree
- **THEN** the line of that file is marked and the cursor is on it

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

#### Scenario: File removed from the index but still on disk
- **WHEN** the after side is the working tree and a file was removed from the
  index but is still on disk
- **THEN** its line shows the status letter and no counts

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

#### Scenario: Ambiguous-width characters shown two cells wide
- **WHEN** `ambiwidth` is `double`, so that the ellipsis and the guides take
  two cells each, and names are cut
- **THEN** no line is wider than the window and every file line ends with
  its status letter

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

#### Scenario: Highlights in a squeezed line
- **WHEN** a line has room only for part of its guides and icon before the
  status letter
- **THEN** the guides and the icon that are shown keep their highlights

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

#### Scenario: Line numbers switched on in the tree window
- **WHEN** the user switches on line numbers, a sign column or a fold column
  in the tree window
- **THEN** the tree is drawn again for the narrower text area, and the
  status letters are at its right edge

#### Scenario: Tree shown again
- **WHEN** the tree was hidden and is shown again with a different width
- **THEN** it is drawn for that width

#### Scenario: Selecting after a redraw
- **WHEN** the tree was redrawn for another width and the user presses
  `<CR>` on a file line
- **THEN** that file is shown, whatever part of its name is visible
