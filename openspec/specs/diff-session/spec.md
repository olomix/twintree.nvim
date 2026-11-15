# diff-session Specification

## Purpose

Lets a user open a diff between two versions of a git repository as a
three-column tab in which both versions are real, browsable code.

## Requirements

### Requirement: Open a diff session with a command
The plugin SHALL provide a `:Twintree` command that accepts zero, one or two
revision arguments and opens a diff session for the git repository that
contains Neovim's current working directory.

#### Scenario: No arguments
- **WHEN** the user runs `:Twintree` inside a git repository
- **THEN** a session opens with `HEAD` as the before side and the working
  tree as the after side

#### Scenario: One revision
- **WHEN** the user runs `:Twintree main`
- **THEN** a session opens with the merge-base of `main` and `HEAD` as the
  before side and the working tree as the after side

#### Scenario: Two revisions
- **WHEN** the user runs `:Twintree main feature`
- **THEN** a session opens with the merge-base of `main` and `feature` as the
  before side and the commit of `feature` as the after side

#### Scenario: Two revisions on a branch without commits
- **WHEN** the user runs `:Twintree main feature` while `HEAD` cannot be
  resolved
- **THEN** the session opens, because `HEAD` is not one of the sides

#### Scenario: More than two arguments
- **WHEN** the user runs `:Twintree a b c`
- **THEN** the command is rejected with an error and no session opens

### Requirement: Fail cleanly on invalid input
The plugin SHALL report an error message and leave tabs, windows and
worktrees unchanged when a session cannot be opened.

#### Scenario: Not a git repository
- **WHEN** the user runs `:Twintree` outside a git repository
- **THEN** an error says the directory is not a git repository and no tab is
  opened

#### Scenario: Unknown revision
- **WHEN** the user runs `:Twintree no-such-rev`
- **THEN** an error names the revision that could not be resolved and no tab
  or worktree is created

#### Scenario: Failure after a worktree was created
- **WHEN** a step fails after the command has already created a worktree
- **THEN** the worktrees created by that command are removed again, and
  worktrees that were cached before are kept

#### Scenario: No common ancestor
- **WHEN** the two revisions to compare have no merge-base
- **THEN** an error says so and no tab or worktree is created

### Requirement: Three-column layout
A session SHALL occupy one tab with three windows from left to right: the
tree of changed files, the before pane and the after pane. The tree window
SHALL keep its width when the other windows are equalized. How the widths
are kept after the session opens is defined by the `diff-layout` capability.

#### Scenario: Layout after opening
- **WHEN** a session opens
- **THEN** the tab contains exactly three windows in the order tree, before,
  after, and the cursor is in the tree window

#### Scenario: Equalizing the windows
- **WHEN** the user equalizes the windows of the tab with `<C-w>=`
- **THEN** the tree keeps its width and the two panes share the rest equally

### Requirement: Tab placement
A session SHALL open in a new tab, except that it SHALL reuse the current tab
when that tab is the only tab and contains a single window showing an empty,
unnamed, unmodified buffer.

#### Scenario: Opened from an editing session
- **WHEN** the user runs `:Twintree` while a file is open
- **THEN** the session opens in a new tab and the original tab is unchanged

#### Scenario: Started from the command line
- **WHEN** Neovim is started with `nvim +Twintree`
- **THEN** the session uses the first tab and no second tab exists

### Requirement: Show a selected file on both sides
When a changed file is selected, the before pane SHALL show the file from the
before side, the after pane SHALL show the file from the after side, and both
panes SHALL be in diff mode against each other. The buffers SHALL be regular
file buffers located in the root directory of their side.

#### Scenario: Modified file
- **WHEN** the user selects a modified file
- **THEN** both panes show that file from their own root and the changed
  lines are highlighted as a diff

#### Scenario: Unchanged lines stay visible
- **WHEN** the user selects a long file with one changed line
- **THEN** every line of the file is visible in both panes and unchanged
  regions are not folded

#### Scenario: Added file
- **WHEN** the user selects a file that exists only on the after side
- **THEN** the after pane shows the file and the before pane shows an empty
  placeholder buffer

#### Scenario: Deleted file
- **WHEN** the user selects a file that exists only on the before side
- **THEN** the before pane shows the file and the after pane shows an empty
  placeholder buffer

#### Scenario: File replaced by a directory
- **WHEN** the user selects a deleted file whose path is a directory on the
  other side
- **THEN** the side where it is a directory shows the empty placeholder
  buffer, not the directory

#### Scenario: Renamed file
- **WHEN** the user selects a renamed file
- **THEN** the before pane shows the file under its old path and the after
  pane shows it under its new path, in diff mode against each other

### Requirement: Panes stay browsable
Each code pane SHALL allow navigation to any other buffer. When navigation
brings a file into a pane, the other pane SHALL show the same file from its
own side, and both panes SHALL be in diff mode against each other. This
SHALL hold for every way of changing the buffer of a pane, including jumps
to a definition or a reference, quickfix and location list entries, the jump
list and `:edit`.

#### Scenario: Leaving the selected file
- **WHEN** the user jumps from the selected file to another file of the
  before side in the before pane
- **THEN** the after pane shows that file from the after side and both panes
  are in diff mode

#### Scenario: Jump to another file in the after pane
- **WHEN** the user jumps to another file of the after side in the after
  pane
- **THEN** the before pane shows that file from the before side and both
  panes are in diff mode

#### Scenario: File that did not change
- **WHEN** the user jumps to a file that is the same on both sides
- **THEN** both panes show it from their own side in diff mode, with no line
  highlighted as changed

#### Scenario: Renamed file
- **WHEN** the user jumps in the before pane to a file that was renamed
- **THEN** the after pane shows the file under its new path

#### Scenario: File missing on the other side
- **WHEN** the user jumps to a file that does not exist on the other side
- **THEN** the other pane shows the empty placeholder buffer

#### Scenario: Corresponding line
- **WHEN** the user jumps to a line of a file that has lines added above it
  on the other side
- **THEN** the other pane is positioned on the line that corresponds in the
  diff, not on the line with the same number, and the panes scroll together

#### Scenario: Returning to the selected file
- **WHEN** the user returns to the previous file of a pane through the jump
  list
- **THEN** both panes show that previous file in diff mode

### Requirement: Working tree side is editable
When the after side is the working tree, its buffers SHALL be the files of
the user's checkout and SHALL remain modifiable.

#### Scenario: Editing the after side
- **WHEN** the user edits and writes the file in the after pane of a
  working-tree session
- **THEN** the file in the user's checkout is changed and the diff
  highlighting reflects the edit

### Requirement: Session ends with its tab
Closing the session tab SHALL end the session without removing cached
worktrees. Several sessions SHALL be able to exist at the same time in
different tabs.

#### Scenario: Closing the tab
- **WHEN** the user closes the session tab
- **THEN** the session is gone, other tabs are unaffected, and the worktrees
  it used remain on disk

#### Scenario: Two sessions
- **WHEN** the user opens a second session while the first is still open
- **THEN** each tab selects and displays files independently

### Requirement: Survive a plugin reload
Open sessions SHALL keep working after the plugin's Lua modules are reloaded,
and reloading SHALL NOT duplicate commands or autocommands.

#### Scenario: Reload with an open session
- **WHEN** the plugin is reloaded while a session tab is open
- **THEN** selecting a file in the tree still shows it in both panes, and
  each plugin autocommand exists once

### Requirement: Files outside both sides
When a file that belongs to neither side enters a pane, both panes SHALL
show that same file in diff mode.

#### Scenario: Jump into a dependency
- **WHEN** the user jumps from the before pane to a file outside the root
  directories of both sides
- **THEN** both panes show that file, in diff mode, with no line highlighted
  as changed

### Requirement: Buffers that are not files are left alone
When a buffer that is not a file enters a pane, the pane SHALL leave diff
mode and the other pane SHALL NOT be changed. Diff mode SHALL return when
the pane shows the file of the current comparison again.

#### Scenario: Terminal in a pane
- **WHEN** the user opens a terminal buffer in the before pane
- **THEN** the before pane is not in diff mode, the after pane still shows
  its file, and the after pane is not scrolled by movement in the before
  pane

#### Scenario: Returning to the file
- **WHEN** the user then returns to the file the before pane showed
- **THEN** diff mode is on again in the before pane

### Requirement: A file is shown in the pane of its side
A file of the before side SHALL be shown in the before pane and a file of
the after side in the after pane. When navigation puts a file into the pane
of the other side, the plugin SHALL move it to its own pane, keep the cursor
on the same position in that file, and show the counterpart in the pane
where the file landed.

#### Scenario: Quickfix entry opened in the other pane
- **WHEN** the cursor is in the after pane and the user opens a quickfix
  entry that points at a line of a before side file
- **THEN** the before pane shows that file with the cursor on that line, the
  after pane shows the same file from the after side, both panes are in diff
  mode, and the cursor is in the before pane

#### Scenario: Alternate file of the landing pane
- **WHEN** a file was moved out of the pane where it landed and the user
  switches that pane to its alternate file
- **THEN** the pane shows the file it showed before the jump, not the file
  that was moved away

### Requirement: Tree window keeps the tree
The tree window SHALL NOT show any buffer other than the tree. Navigation
started from the tree window SHALL open its target in another window.

#### Scenario: Quickfix entry opened from the tree
- **WHEN** the cursor is in the tree window and the user opens a quickfix
  entry
- **THEN** the tree window still shows the tree, and the file is shown in
  the panes in diff mode

#### Scenario: Editing a file from the tree
- **WHEN** the user runs `:edit` with a file name in the tree window
- **THEN** Neovim refuses with its own error message and the tree window
  still shows the tree

#### Scenario: Tree buffer deleted
- **WHEN** the user deletes the tree buffer while the tree window shows it
- **THEN** the tree is hidden and can be shown again with
  `:TwintreeToggleTree`

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

### Requirement: Only the panes follow
Windows that the user opened in the diff tab SHALL NOT take part in
following or in the diff: a buffer entering such a window SHALL NOT change
the panes, and a window split off a pane SHALL NOT be in diff mode.

#### Scenario: Split made by the user
- **WHEN** the user splits a pane and opens another file in the new window
- **THEN** both panes still show the file they showed, in diff mode

#### Scenario: Split of a pane is not part of the diff
- **WHEN** the user splits a pane that is in diff mode
- **THEN** the new window is not in diff mode and does not scroll with the
  panes, and the changes highlighted in the panes stay the same when the
  new window shows another file

#### Scenario: Pane moves on while another window shows its old file
- **WHEN** a window split off a pane, or a window in another tab, still
  shows the file a pane compared, and that pane is taken to another file
- **THEN** the panes highlight only the differences between the two sides
  of the new file, and a file that did not change shows none

### Requirement: The selected file is the file the panes show
The selected file of a session SHALL be the file the panes currently
compare, whether the user chose it in the tree or reached it by navigation.

#### Scenario: After a jump
- **WHEN** the user selected a file in the tree and then jumped to another
  file in a pane
- **THEN** the other file is the selected file of the session

#### Scenario: Two sessions
- **WHEN** two diff tabs are open and the user jumps to another file in a
  pane of one of them
- **THEN** the panes and the selected file of the other tab are unchanged
