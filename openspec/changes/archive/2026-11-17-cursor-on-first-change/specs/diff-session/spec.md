# Spec Delta

## ADDED Requirements

### Requirement: Cursor on the first change of a file shown for the first time
When a file is shown by selecting it in the tree, or as the first file when
a session opens, and the session has not shown that file before, the cursor
of the after pane SHALL be on the first change of the file and the before
pane SHALL be on the corresponding line. The change SHALL be visible in
both panes. A file reached by navigation SHALL keep the cursor the
navigation gave it.

#### Scenario: Change far below the top
- **WHEN** the user selects a modified file whose first change is further
  down than one window height
- **THEN** the cursor of the after pane is on the first line of that
  change, the before pane is on the corresponding line, and the change is
  visible in both panes

#### Scenario: First file of a session
- **WHEN** a session opens and its first file has its first change below
  the top
- **THEN** the cursor is in the after pane on the first change

#### Scenario: First change removes lines
- **WHEN** the first change of the selected file is a block of lines that
  exists only on the before side
- **THEN** the cursor of the after pane is on the line next to the place
  where they are missing, the before pane is on the same line of text, and
  the lines that exist only on the before side are visible above it

#### Scenario: Change on the first line
- **WHEN** the first line of the selected file is changed, or lines were
  added or removed above it
- **THEN** the cursor is on the first line, not on a later change

#### Scenario: No change to jump to
- **WHEN** the user selects a file with the same content on both sides
- **THEN** the cursor is on the first line and no error is reported

#### Scenario: File on one side only
- **WHEN** the user selects an added or a deleted file
- **THEN** the pane that shows the file is at its top, and stays there
  while the cursor is in the empty pane

#### Scenario: Jump list
- **WHEN** a file was shown with the cursor on its first change and the
  user presses `<C-o>`
- **THEN** the cursor does not go to the first line of that file

#### Scenario: File reached by navigation
- **WHEN** the user jumps from a pane to a line of a changed file the
  session has not shown before
- **THEN** the cursor is on the line the jump points at, not on the first
  change

#### Scenario: File open in another tab
- **WHEN** a working tree file is open in a window of another tab and the
  user selects it in the tree for the first time
- **THEN** the after pane is on the first change and the cursor of the
  window in the other tab has not moved

#### Scenario: Selection with a missing pane
- **WHEN** the user selects a file while a pane is missing, restores the
  layout with `:TwintreeResetLayout`, and selects the file again
- **THEN** the first attempt reports that a pane is missing without a Lua
  error, and the second shows the file with the cursor on its first change

### Requirement: Cursor returns to where it was left
When the user selects in the tree a file the session has already shown, the
cursor SHALL be on the position it had when the panes last showed that
file, and SHALL NOT be moved to the first change. A file counts as shown
whether it was selected in the tree or reached by navigation.

#### Scenario: Returning through the tree
- **WHEN** the user selects a file, moves the cursor in the after pane,
  selects another file, and selects the first one again
- **THEN** the cursor of the after pane is on the line it was left on, and
  the before pane is on the corresponding line

#### Scenario: Selecting the file that is already shown
- **WHEN** the user moves the cursor in the after pane and then selects in
  the tree the file the panes already show
- **THEN** the cursor is in the after pane on the line it was on

#### Scenario: File first reached by navigation
- **WHEN** the user reaches a changed file by a jump, moves the cursor,
  leaves the file, and later selects it in the tree
- **THEN** the cursor is where it was left, not on the first change

#### Scenario: Buffer deleted in between
- **WHEN** the user wipes out the buffer of a file the session has shown
  and selects the file again
- **THEN** the cursor is on the first change

#### Scenario: Two sessions
- **WHEN** a file was shown in one diff tab and is selected for the first
  time in another diff tab
- **THEN** the cursor of that other tab's after pane is on the first change
