# Spec Delta

## Purpose

Lets a user open a diff between two versions of a git repository as a
three-column tab in which both versions are real, browsable code.

## ADDED Requirements

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
SHALL keep a fixed width when other windows are resized.

#### Scenario: Layout after opening
- **WHEN** a session opens
- **THEN** the tab contains exactly three windows in the order tree, before,
  after, and the cursor is in the tree window

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
Each code pane SHALL allow navigation to any other buffer. Diff mode in a
pane SHALL be on only while the pane shows the currently selected file of its
side.

#### Scenario: Leaving the selected file
- **WHEN** the user jumps from the selected file to another file in the
  before pane
- **THEN** diff mode and scroll binding are switched off in the before pane
  and the after pane is not scrolled by movement in the before pane

#### Scenario: Returning to the selected file
- **WHEN** the user returns to the selected file in that pane
- **THEN** diff mode is switched on again in that pane

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
