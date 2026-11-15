# Spec Delta

## ADDED Requirements

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

## MODIFIED Requirements

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
