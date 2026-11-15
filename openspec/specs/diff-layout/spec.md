# diff-layout Specification

## Purpose

Keeps the windows of a diff tab usable over time: their sizes when the
terminal or the user changes them, hiding and showing the tree, and a way
back to the original view after the user rearranged the tab.

## Requirements

### Requirement: Pane ratio survives a terminal resize
When the width of the terminal changes, the plugin SHALL keep the ratio
between the widths of the before pane and the after pane, and SHALL keep the
tree at its remembered width. The ratio starts at one half.

#### Scenario: Terminal grows
- **WHEN** the panes are equally wide and the terminal becomes wider
- **THEN** both panes grow and stay equally wide, and the tree keeps its
  width

#### Scenario: Terminal shrinks
- **WHEN** the panes are equally wide and the terminal becomes narrower
- **THEN** both panes shrink and stay equally wide

#### Scenario: Hand-set ratio
- **WHEN** the user made the before pane half as wide as the after pane and
  the terminal is then resized
- **THEN** the before pane is still about half as wide as the after pane

#### Scenario: Resize while another tab is current
- **WHEN** the terminal is resized while the user is in another tab and the
  user then returns to the diff tab
- **THEN** the panes have the ratio they had before the resize

#### Scenario: Tree hidden
- **WHEN** the tree is hidden and the terminal is resized
- **THEN** the two panes keep their ratio

#### Scenario: Terminal too narrow for the layout
- **WHEN** the terminal becomes so narrow that the panes are squeezed to the
  minimum width, and is then made wide again
- **THEN** the tree has its remembered width and the panes have their ratio,
  as before the terminal was narrowed

#### Scenario: Diff opened in a narrow terminal
- **WHEN** a diff is opened in a terminal too narrow for the tree and two
  panes, and the terminal is then made wide
- **THEN** the tree has the configured width and the panes are equally wide

#### Scenario: A window of the user between the panes
- **WHEN** the user opened a window of their own between the before and the
  after pane and the terminal is resized
- **THEN** the panes keep their ratio and the width of that window is not
  changed

### Requirement: Equalizing resets the pane ratio
Equalizing the windows SHALL make the before and after panes equally wide
and SHALL make one half the ratio that later terminal resizes keep.

#### Scenario: Equalize after a hand-set ratio
- **WHEN** the user set unequal pane widths, presses `<C-w>=`, and the
  terminal is then resized
- **THEN** the panes are equally wide after the resize

### Requirement: Tree width is remembered
The plugin SHALL remember the width the user gives the tree window, and
SHALL NOT take a width from a layout in which the tree or a pane is squeezed
to the minimum window width. The remembered width starts at the configured
tree width.

#### Scenario: Widening the tree by hand
- **WHEN** the user widens the tree and later equalizes the windows or
  resizes the terminal
- **THEN** the tree keeps the width the user gave it

#### Scenario: Zoom does not change the remembered width
- **WHEN** the user maximizes a pane with `<C-w>|`, which squeezes the tree
- **THEN** the remembered tree width is unchanged

### Requirement: Layout returns after a zoom
After the user maximizes one of the three windows with `<C-w>|` and then
equalizes with `<C-w>=`, the tree SHALL have its remembered width and the
two panes SHALL be equally wide.

#### Scenario: Zooming a pane
- **WHEN** the user presses `<C-w>|` in the after pane and then `<C-w>=`
- **THEN** the tree is back at its remembered width and the panes are
  equally wide

#### Scenario: Zooming the tree
- **WHEN** the user presses `<C-w>|` in the tree and then `<C-w>=`
- **THEN** the tree is back at its remembered width and the panes are
  equally wide

#### Scenario: While zoomed
- **WHEN** a window is maximized and the user has not equalized yet
- **THEN** the plugin leaves the widths as the user set them

### Requirement: The tree can be hidden
Closing the tree window SHALL hide the tree without ending the session. The
panes SHALL keep working, and the tree's content, folded directories and
selected file SHALL be kept for when it is shown again.

#### Scenario: Closing the tree window
- **WHEN** the user closes the tree window with `<C-w>c`
- **THEN** the tab shows the two panes, they stay in diff mode, and the
  session still exists

#### Scenario: Showing it again
- **WHEN** the tree was hidden with folded directories and a selected file
  and is shown again
- **THEN** the same directories are folded and the same file is marked as
  selected

### Requirement: Toggle the tree with a command
The plugin SHALL provide a `:TwintreeToggleTree` command. When the tree is
visible it SHALL hide it. When the tree is hidden it SHALL show it as the
leftmost window of the tab with its remembered width, move the cursor into
it and place the cursor on the selected file. The pane ratio SHALL be the
same before and after.

#### Scenario: Hiding
- **WHEN** the user runs `:TwintreeToggleTree` while the tree is visible
- **THEN** the tree window is closed and the panes keep their ratio

#### Scenario: Showing
- **WHEN** the user runs `:TwintreeToggleTree` while the tree is hidden
- **THEN** the tree is the leftmost window with its remembered width, the
  cursor is in it on the line of the selected file, and the panes keep their
  ratio

#### Scenario: Tree content was deleted
- **WHEN** the tree buffer no longer exists and the user runs
  `:TwintreeToggleTree`
- **THEN** the tree is rebuilt from the changed files and shown

#### Scenario: Tree buffer was unloaded
- **WHEN** the user unloaded the tree buffer with `:bdelete` and runs
  `:TwintreeToggleTree`
- **THEN** the tree is rebuilt with its content and keys, and the selected
  file is still marked

#### Scenario: Another buffer in the tree window
- **WHEN** the user put another buffer into the tree window and runs
  `:TwintreeToggleTree`
- **THEN** the tree is shown as the leftmost window with its remembered
  width

#### Scenario: No room for the tree
- **WHEN** the tree is hidden, the tab has no room for another window and the
  user runs `:TwintreeToggleTree`
- **THEN** a message says there is no room, no window is opened or closed,
  and no Lua error is raised

#### Scenario: The tree is the only window
- **WHEN** the tree is the only window left in the tab and the user runs
  `:TwintreeToggleTree`
- **THEN** the tab is not closed and a message suggests
  `:TwintreeResetLayout`

### Requirement: Reset the layout with a command
The plugin SHALL provide a `:TwintreeResetLayout` command that returns the
diff tab to its original view: exactly the tree, the before pane and the
after pane in that order, the tree at the configured width, the panes
equally wide, and no window maximized. Every other window of the tab SHALL
be closed without discarding its buffer. The selected file and the folded
directories SHALL be kept, and the selected file SHALL be shown in both
panes in diff mode.

#### Scenario: After the user rearranged the tab
- **WHEN** the user closed a pane, opened other windows and shows unrelated
  buffers in the tab, and then runs `:TwintreeResetLayout`
- **THEN** the tab has exactly three windows in the order tree, before,
  after, with the tree at the configured width and the panes equally wide

#### Scenario: Selected file
- **WHEN** a file was selected before the reset
- **THEN** both panes show that file in diff mode and its line is marked in
  the tree

#### Scenario: Nothing selected
- **WHEN** no file was selected before the reset
- **THEN** both panes are empty and the cursor is in the tree

#### Scenario: Window with unsaved changes
- **WHEN** another window of the tab shows a buffer with unsaved changes
- **THEN** the window is closed and the buffer with its changes stays loaded

#### Scenario: Widened tree
- **WHEN** the user had widened the tree and runs `:TwintreeResetLayout`
- **THEN** the tree has the configured width, and that is the width that is
  remembered from then on

#### Scenario: Buffer set to be removed when hidden
- **WHEN** another window of the tab shows a buffer whose own setting removes
  it when it is hidden
- **THEN** the window is closed, the buffer and its content are kept, and
  the buffer keeps its setting

#### Scenario: Tab with no room for another window
- **WHEN** the tab is filled with so many windows that no further window can
  be opened, and the user runs `:TwintreeResetLayout`
- **THEN** the tab ends up with exactly the three windows of the original
  view

#### Scenario: Windows closed by an autocommand
- **WHEN** an autocommand of the user closes another window of the tab while
  the reset is closing windows
- **THEN** the reset completes with the three windows of the original view,
  the diff tab still exists, and no Lua error is raised

#### Scenario: Tab closed by an autocommand
- **WHEN** an autocommand of the user closes the diff tab itself while the
  reset is closing windows
- **THEN** a message says the diff tab was closed, no window is opened in
  another tab, and no Lua error is raised

### Requirement: Commands outside a diff tab
`:TwintreeToggleTree` and `:TwintreeResetLayout` SHALL report an error
message saying that the current tab has no diff session, and SHALL change
nothing, when run in a tab without a session.

#### Scenario: Toggle in an ordinary tab
- **WHEN** the user runs `:TwintreeToggleTree` in a tab without a diff
- **THEN** an error message says there is no diff session in this tab, no
  window is opened or closed, and no Lua error is raised

#### Scenario: Reset in an ordinary tab
- **WHEN** the user runs `:TwintreeResetLayout` in a tab without a diff
- **THEN** an error message says there is no diff session in this tab, no
  window is opened or closed, and no Lua error is raised

### Requirement: Selecting a file with a missing pane
When a file is selected while the before or the after pane window no longer
exists, the plugin SHALL leave the windows as they are and report a message
that names `:TwintreeResetLayout`.

#### Scenario: A pane was closed
- **WHEN** the user closed the before pane and presses `<CR>` on a file in
  the tree
- **THEN** a message suggests `:TwintreeResetLayout` and no Lua error is
  raised

#### Scenario: Tree shown in a window the user made
- **WHEN** the user closed the tree window, shows the tree buffer in another
  window of the tab and presses `<CR>` on a file there
- **THEN** the file is shown in both panes

### Requirement: Tree buffer ends with its tab
The plugin SHALL delete the tree buffer of a session when the session's tab
is closed, whether the tree was visible or hidden at that moment, and SHALL
NOT delete tree buffers of sessions in other tabs.

#### Scenario: Closing a diff tab
- **WHEN** a diff tab is closed
- **THEN** its tree buffer no longer exists

#### Scenario: Closing a tab with a hidden tree
- **WHEN** the tree was hidden and the diff tab is closed
- **THEN** its tree buffer no longer exists

#### Scenario: Another diff is open
- **WHEN** two diff tabs are open and one is closed
- **THEN** the tree of the other tab still exists and works
