# Spec Delta

## ADDED Requirements

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
- **WHEN** the name of the file has a control character
- **THEN** the clipboard holds the name as it is, and the message shows
  the character escaped, as the tree does

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
