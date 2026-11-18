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

### Requirement: Double click in the tree
A double click with the left mouse button on a line of the tree SHALL do
what `<CR>` does on that line. A double click that is not on the text of
the tree window SHALL keep the meaning Neovim gives it. The plugin SHALL
NOT map a single click, a drag, the release of the left button, or a
triple or quadruple click in the tree.

#### Scenario: Double click on a file
- **WHEN** the user double-clicks a file line of the tree
- **THEN** the file is shown in both panes, its tree line is marked as
  selected, and the cursor is in the after pane

#### Scenario: Double click on a directory
- **WHEN** the user double-clicks an expanded directory line
- **THEN** the directory is shown as collapsed, and a second double click
  shows its content again

#### Scenario: Double click from another window
- **WHEN** the cursor is in a pane and the user double-clicks a file line
  of the tree
- **THEN** that file is shown

#### Scenario: Double click below the last line
- **WHEN** the user double-clicks the empty area below the last line of
  the tree
- **THEN** the action applies to the line the cursor lands on, as `<CR>`
  there would, and no error is reported

#### Scenario: Double click outside the text
- **WHEN** the tree is the current window and the user double-clicks its
  status line, the separator next to it, the tab line or the command
  line
- **THEN** no file is shown and no directory is folded, and Neovim does
  what it does for that double click without the plugin

#### Scenario: Single click and drag
- **WHEN** the user clicks a line of the tree once, or drags over its
  text
- **THEN** the cursor moves or the text is selected as in any buffer, no
  file is shown and no directory is folded

#### Scenario: Triple click
- **WHEN** the user clicks a line of the tree three times
- **THEN** the third click selects the line, as in any buffer

#### Scenario: Double click with a pane missing
- **WHEN** the user closed a pane and double-clicks a file line of the
  tree
- **THEN** the same message as for `<CR>` asks to reset the layout, and
  no Lua error is raised

#### Scenario: Tree buffer in a second window
- **WHEN** the user opened the tree buffer in a second window of the diff
  tab and double-clicks a file line there
- **THEN** that file is shown

#### Scenario: Tree buffer in another tab
- **WHEN** the user opened the tree buffer of a diff in a window of
  another tab, with or without a diff of its own, and double-clicks a
  line or presses `<CR>` there
- **THEN** a message says that the diff of this tree is in another tab,
  and no file is shown and no directory is folded in any tab

### Requirement: The user's own keys in the tree
A buffer-local mapping that the user defines for the tree in a `FileType`
autocommand for `twintree` SHALL take the place of the plugin's mapping
for the same key.

#### Scenario: Own mapping for the double click
- **WHEN** the user maps `<2-LeftMouse>` for the filetype `twintree` and
  opens a diff
- **THEN** a double click in the tree runs the mapping of the user

#### Scenario: Own mapping for the Enter key
- **WHEN** the user maps `<CR>` for the filetype `twintree` and opens a
  diff
- **THEN** `<CR>` in the tree runs the mapping of the user

### Requirement: Copy the path of a changed file
The plugin SHALL provide a command `:TwintreeCopyPath` that copies a path
to the clipboard register `+` and reports the copied text. Its one
optional argument SHALL be `relative` (the path from the repository
root), `absolute` or `name` (the last component of the path), SHALL be
completed on the command line, and SHALL default to `relative`. The
absolute path SHALL point to the after side when the file or directory
exists there, and to the before side otherwise.

#### Scenario: Relative path of a file
- **WHEN** the cursor is on the line of `src/app.lua` in the tree and the
  user runs `:TwintreeCopyPath relative`
- **THEN** the clipboard holds `src/app.lua` and a message shows that
  text

#### Scenario: No argument
- **WHEN** the user runs `:TwintreeCopyPath` on a file line
- **THEN** the clipboard holds the relative path

#### Scenario: File name
- **WHEN** the user runs `:TwintreeCopyPath name` on the line of
  `src/app.lua`
- **THEN** the clipboard holds `app.lua`

#### Scenario: Completion
- **WHEN** the user completes the argument of the command
- **THEN** the three arguments are offered, and after `a` only `absolute`

#### Scenario: Absolute path of a file of the working tree
- **WHEN** the diff compares a commit with the working tree and the user
  runs `:TwintreeCopyPath absolute` on the line of a modified file
- **THEN** the clipboard holds the path of that file in the working
  directory

#### Scenario: Absolute path of a deleted file
- **WHEN** the user runs `:TwintreeCopyPath absolute` on the line of a
  file that exists on the before side only
- **THEN** the clipboard holds the path of that file in the worktree of
  the before side

#### Scenario: Absolute path between two commits
- **WHEN** the diff compares two commits and the user runs
  `:TwintreeCopyPath absolute` on the line of a modified file
- **THEN** the clipboard holds the path of that file in the worktree of
  the after side

#### Scenario: File that is on neither side any more
- **WHEN** a listed file was removed from the working directory after the
  tree was drawn, and it does not exist on the before side
- **THEN** `:TwintreeCopyPath absolute` copies its path on the before
  side

#### Scenario: Renamed file
- **WHEN** the user runs the command on the line of a renamed file
- **THEN** the relative path is the new path of the file, and the
  absolute path is the file of the after side

#### Scenario: Directory
- **WHEN** the cursor is on a directory line and the user runs the
  command with each of the three arguments
- **THEN** the clipboard holds the path of the directory from the
  repository root, its absolute path, and its name; for a line that
  stands for several nested directories, the path of the innermost one

#### Scenario: Directory that exists on the before side only
- **WHEN** the user runs `:TwintreeCopyPath absolute` on the line of a
  directory that exists on the before side only
- **THEN** the clipboard holds the path of that directory in the worktree
  of the before side

#### Scenario: Path with spaces
- **WHEN** the path has spaces
- **THEN** the clipboard holds it unchanged, without quotes or escapes

#### Scenario: Name with a control character
- **WHEN** the name of the file has a control character, also a line
  break at its end
- **THEN** the clipboard holds the name as it is, with nothing added, and
  the message shows the character escaped, as the tree does

### Requirement: What the copy command acts on
When the current buffer is a tree, `:TwintreeCopyPath` SHALL copy the path
of the file or directory on the line of the cursor, in the diff that tree
belongs to; otherwise it SHALL copy the path of the file the panes of the
current tab show, whether or not the tree lists it. A command that has
nothing to copy SHALL report why, SHALL leave the clipboard unchanged and
SHALL NOT raise a Lua error.

#### Scenario: In a pane
- **WHEN** the cursor is in a pane of the diff tab and the user runs the
  command
- **THEN** the clipboard holds the path of the file the diff shows,
  wherever the cursor of the tree is

#### Scenario: Pane shows a file that is not in the tree
- **WHEN** the user went to an unchanged file in a pane and runs
  `:TwintreeCopyPath relative` there
- **THEN** the clipboard holds the path of that file from the repository
  root

#### Scenario: Pane shows a file outside the repository
- **WHEN** a pane shows a file that belongs to neither side and the user
  runs the command there
- **THEN** `absolute` and `name` copy its path and its name, and
  `relative` reports that the file is not in the repository and leaves
  the clipboard unchanged

#### Scenario: Another window of the diff tab
- **WHEN** the cursor is in a window of the diff tab that is neither the
  tree nor a pane
- **THEN** the command copies the path of the file the panes show

#### Scenario: Tree hidden
- **WHEN** the tree is hidden and the user runs the command
- **THEN** the clipboard holds the path of the file the diff shows

#### Scenario: Panes closed
- **WHEN** the user closed both panes and runs the command in the tree
- **THEN** the clipboard holds the path of the line under the cursor

#### Scenario: Tree buffer in another window
- **WHEN** the user opened the tree buffer in a second window and runs
  the command there
- **THEN** the clipboard holds the path of the line under the cursor of
  that window

#### Scenario: Tree buffer in another tab
- **WHEN** the user opened the tree buffer of a diff in a window of
  another tab and runs the command there
- **THEN** the clipboard holds the path of the line under the cursor,
  with the absolute path taken from the diff the tree belongs to

#### Scenario: Line without a file
- **WHEN** the tree shows "No changes" and the user runs the command on
  that line
- **THEN** a message says there is no file to copy the path of, and the
  clipboard is unchanged

#### Scenario: No file is shown
- **WHEN** the diff shows no file and the user runs the command outside
  the tree
- **THEN** a message says there is no file to copy the path of, and the
  clipboard is unchanged

#### Scenario: Unknown argument
- **WHEN** the user runs `:TwintreeCopyPath full`
- **THEN** a message names the three accepted arguments, and the
  clipboard is unchanged

#### Scenario: More than one argument
- **WHEN** the user runs `:TwintreeCopyPath name absolute`
- **THEN** the command is refused and the clipboard is unchanged

#### Scenario: Tab without a diff
- **WHEN** the user runs the command in a tab without a diff session, in
  a buffer that is not a tree
- **THEN** an error message says there is no diff session in this tab,
  the clipboard is unchanged, and no Lua error is raised

#### Scenario: No clipboard
- **WHEN** Neovim has no clipboard provider
- **THEN** an error message says so, nothing is reported as copied, and no
  Lua error is raised

#### Scenario: Clipboard cannot be written
- **WHEN** writing the clipboard register raises an error
- **THEN** an error message says so and no Lua error is raised

### Requirement: Copy items in the menu of the right mouse button
When the right mouse button opens the menu in normal mode on a file or
directory line of the tree, the menu SHALL start with the items "Copy
relative path", "Copy absolute path" and "Copy file name" and a
separator, each item doing what `:TwintreeCopyPath` does on the line of
the cursor. Everywhere else the menu SHALL NOT contain them. The plugin
SHALL NOT change any other item of the menu, nor `'mouse'` or
`'mousemodel'`.

#### Scenario: Right click on a file line
- **WHEN** `'mousemodel'` is `popup_setpos`, and the user clicks a file
  line of the tree with the right mouse button and chooses "Copy relative
  path"
- **THEN** the clipboard holds the relative path of the clicked file,
  also when the cursor was on another line or in another window before
  the click

#### Scenario: Right click on a directory line
- **WHEN** the user clicks a directory line with the right mouse button
- **THEN** the menu contains the three items

#### Scenario: Right click on the separator of the tree window
- **WHEN** the cursor is on a file line of the tree and the user clicks
  the vertical separator of the tree window with the right mouse button
- **THEN** the menu contains none of the three items

#### Scenario: Right click in a pane
- **WHEN** the user clicks in a pane of the diff tab with the right mouse
  button, after the menu was opened in the tree
- **THEN** the menu contains none of the three items and no empty line in
  their place

#### Scenario: Menu opened by a command after leaving the tree
- **WHEN** the menu was opened in the tree, the user moves to another
  window or closes the diff tab, and opens the menu with `:popup PopUp`
- **THEN** the menu contains none of the three items

#### Scenario: Mouse model that does not move the cursor
- **WHEN** `'mousemodel'` is `popup`, the cursor is in the tree, and the
  user clicks in a pane with the right mouse button
- **THEN** the menu contains none of the three items

#### Scenario: Right click in a selection
- **WHEN** the user selected text in the tree and clicks inside the
  selection with the right mouse button
- **THEN** the menu is Neovim's menu for a selection, without the three
  items

#### Scenario: Right click outside a diff tab
- **WHEN** the user clicks in a buffer of a tab without a diff with the
  right mouse button
- **THEN** the menu is the one the user had before the plugin was loaded

#### Scenario: Items of the user
- **WHEN** the user has items of their own in the menu, one of them named
  "Copy file name"
- **THEN** they are still there and still do what the user defined,
  outside the tree and after the menu was opened in the tree

#### Scenario: Menu removed by the user
- **WHEN** the user removed the whole menu and clicks a file line of the
  tree with the right mouse button
- **THEN** no error is reported

#### Scenario: Plugin loaded again
- **WHEN** the plugin file is sourced again while the items are in the
  menu
- **THEN** the items are gone until the menu opens in the tree again
