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
when they still exist.

#### Scenario: New change in the working tree
- **WHEN** a file in the working tree is modified after the session opened
  and the user presses `R`
- **THEN** the file appears in the tree

### Requirement: Tree buffer is not editable
The tree SHALL be shown in a buffer that the user cannot modify and that is
not associated with a file.

#### Scenario: Attempt to edit
- **WHEN** the user tries to insert text in the tree buffer
- **THEN** the buffer content does not change
