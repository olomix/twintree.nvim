# Spec Delta

## ADDED Requirements

### Requirement: A layout that changes while a file is shown
When a pane or the diff tab goes away while the plugin is showing a file,
whichever action asked for the file, the plugin SHALL report one line and
SHALL NOT raise a Lua error. With a pane gone, the session SHALL record
the files and the selection from before the attempt, and the pane that is
left SHALL show the file it showed before, without diff mode. With the tab
gone, no window of another tab SHALL be changed.

#### Scenario: Other pane closed while a file is loaded
- **WHEN** the user selects a file and an autocommand of theirs closes the
  after pane while the before side of that file is loaded
- **THEN** one line says a pane is missing and names
  `:TwintreeResetLayout`, no Lua error is raised, the tree marks the file
  it marked before, and the before pane shows the file it showed before,
  without diff mode

#### Scenario: Pane closed while it loads its own file
- **WHEN** an autocommand closes the before pane while that pane loads
  the selected file
- **THEN** one line says a pane is missing, and no line says that the
  file could not be loaded

#### Scenario: Pane closed while diff mode is switched on
- **WHEN** both files were loaded and an autocommand closes a pane when
  diff mode is switched on in the other
- **THEN** one line says a pane is missing, the session records the files
  from before the attempt, and the pane that is left is not in diff mode

#### Scenario: The file of a failed attempt leaves the diff
- **WHEN** a pane went away after the other pane already showed the new
  file in diff mode, the layout is restored, and the panes then compare a
  file that is the same on both sides
- **THEN** no line of that file is highlighted as changed

#### Scenario: Not counted as shown
- **WHEN** a file was not shown because a pane went away, the layout is
  restored with `:TwintreeResetLayout`, and the user selects the file
  again
- **THEN** the file is shown with the cursor on its first change

#### Scenario: Position for next and previous
- **WHEN** `:TwintreeNextFile` does not show its file because a pane went
  away, and the layout is restored
- **THEN** `:TwintreeNextFile` shows that same file

#### Scenario: Diff tab closed while a file is loaded
- **WHEN** an autocommand of the user closes the diff tab while a
  selected file is loaded
- **THEN** one line says the diff tab was closed, no Lua error is raised,
  and the windows of the other tabs show what they showed

#### Scenario: Tab closed during a jump
- **WHEN** the diff tab is closed while the plugin shows the counterpart
  of a file the user jumped to in a pane
- **THEN** one line says the diff tab was closed and no Lua error is
  raised

#### Scenario: Pane closed during a jump
- **WHEN** the other pane is closed while the plugin shows the
  counterpart of a file the user jumped to in a pane
- **THEN** the pane keeps the file the user jumped to, without diff
  mode, one line says a pane is missing, and no Lua error is raised

#### Scenario: Tab closed while the layout is reset
- **WHEN** the diff tab is closed while `:TwintreeResetLayout` shows the
  compared file again
- **THEN** one line says the diff tab was closed and no Lua error is
  raised

#### Scenario: Tab closed while a session opens
- **WHEN** the diff tab is closed while `:Twintree` shows the first file
- **THEN** one line says so, no session is left, no Lua error is raised,
  and the worktrees that command created are removed again

#### Scenario: Pane closed after the file is shown
- **WHEN** a pane is closed after both files were shown, while the tree
  is drawn
- **THEN** the file counts as shown, no Lua error is raised, and the next
  selection reports the missing pane

#### Scenario: Error that the layout does not explain
- **WHEN** showing a file fails while both panes and the tab are still
  there
- **THEN** the error is raised, not turned into a message about the
  layout

## MODIFIED Requirements

### Requirement: Following with a missing pane
When a file enters a pane while the other pane window no longer exists, the
plugin SHALL leave the file where it is, without diff mode, SHALL NOT open,
close or change any other window, and SHALL NOT raise an error.

#### Scenario: The other pane was closed
- **WHEN** the user closed the after pane and jumps to another file in the
  before pane
- **THEN** the before pane shows that file without diff mode and no Lua
  error is raised

#### Scenario: File of a side whose pane was closed
- **WHEN** the user closed the before pane and opens a before side file in
  the after pane
- **THEN** the after pane shows that file without diff mode and no Lua
  error is raised

#### Scenario: Returning to the compared file
- **WHEN** the user closed the after pane, showed another buffer in the
  before pane, and returns there to the file the session compared
- **THEN** the before pane shows that file without diff mode and no Lua
  error is raised
