# Spec Delta

## ADDED Requirements

### Requirement: First changed file is shown when a session opens
When a session opens and the diff has changed files, the plugin SHALL show
the file on the first file line of the tree as if the user had selected it,
and the cursor SHALL be in the after pane. When that file is not opened, the
session SHALL still open, with empty panes and the cursor in the tree
window, and the plugin SHALL report one line that says why, without raising
a Lua error.

#### Scenario: Diff with changed files
- **WHEN** a session opens for a diff with changed files
- **THEN** both panes show the first file of the tree in diff mode, its
  tree line is marked as selected, and the cursor is in the after pane

#### Scenario: First file in tree order
- **WHEN** the tree lists a file inside a directory above a file that git
  reported earlier
- **THEN** the file inside the directory is the one shown

#### Scenario: First file exists on one side only
- **WHEN** the first file of the tree was deleted
- **THEN** the before pane shows the file, the after pane shows the empty
  placeholder buffer, and the cursor is in the after pane

#### Scenario: No changes
- **WHEN** a session opens for a diff with no changed files
- **THEN** both panes are empty and the cursor is in the tree window

#### Scenario: Swap file prompt declined
- **WHEN** the first file has a leftover swap file and the user answers
  Abort to the prompt shown while the session opens
- **THEN** the session is open with the tree filled, both panes are empty,
  no line of the tree is marked, the cursor is in the tree window, and one
  line says the file was not opened

#### Scenario: A pane closed while the session opens
- **WHEN** a pane is closed before the first file is shown
- **THEN** the session is open, one line says a pane is missing, and no Lua
  error is raised

#### Scenario: Opened in a narrow terminal
- **WHEN** a session opens in a terminal too narrow for the tree and two
  panes, and the terminal is then made wide
- **THEN** the tree has the configured width and the panes are equally
  wide, although the cursor moved to the after pane while the terminal was
  narrow

#### Scenario: Selecting the file later
- **WHEN** the first file was not opened and the user then selects it in
  the tree
- **THEN** the file is shown as after any other selection

## MODIFIED Requirements

### Requirement: Three-column layout
A session SHALL occupy one tab with three windows from left to right: the
tree of changed files, the before pane and the after pane. The tree window
SHALL keep its width when the other windows are equalized. How the widths
are kept after the session opens is defined by the `diff-layout` capability.

#### Scenario: Layout after opening
- **WHEN** a session opens
- **THEN** the tab contains exactly three windows in the order tree, before,
  after

#### Scenario: Equalizing the windows
- **WHEN** the user equalizes the windows of the tab with `<C-w>=`
- **THEN** the tree keeps its width and the two panes share the rest equally
