# Spec Delta

## ADDED Requirements

### Requirement: File open in another running Neovim
When the plugin shows in a pane a file whose swap file belongs to another
Neovim process that is still running, the file SHALL be opened and editable
as usual, with Neovim's own warning and without a question, unless the user
configured Neovim to handle such swap files differently.

#### Scenario: Selecting a file that is open elsewhere
- **WHEN** a file of the working tree is open in another running Neovim and
  the user selects it in the tree
- **THEN** both panes show the file in diff mode, the after pane is
  editable, a one-line warning names the other process, and no Lua error is
  raised

#### Scenario: Following a jump to a file that is open elsewhere
- **WHEN** the user jumps in the before pane to a file whose working tree
  counterpart is open in another running Neovim
- **THEN** the after pane shows that counterpart without a question

### Requirement: Prompt for a swap file that needs a decision
When the plugin shows in a pane a file that has a swap file and nothing has
decided what to do with it, the plugin SHALL ask the user, showing the facts
of Neovim's own swap file message, and SHALL offer Open Read-Only, Edit
anyway, Recover, Delete it, Quit and Abort. Neovim SHALL apply the choice.

#### Scenario: What the prompt shows
- **WHEN** the prompt is shown
- **THEN** it names the swap file, its owner, the time the swap file was
  last written, the file, whether it was modified, the user and host it
  belongs to, and the file being opened

#### Scenario: Open read-only
- **WHEN** the user selects a file with a leftover swap file and answers
  Open Read-Only
- **THEN** both panes show the file in diff mode and the buffer is read-only

#### Scenario: Edit anyway
- **WHEN** the user answers Edit anyway
- **THEN** both panes show the file in diff mode and the buffer is editable

#### Scenario: Recover
- **WHEN** the user answers Recover
- **THEN** the pane shows the file with the content recovered from the swap
  file

#### Scenario: Delete it
- **WHEN** the user answers Delete it
- **THEN** the swap file is deleted and both panes show the file, editable

#### Scenario: Quit or Abort
- **WHEN** the user answers Quit or Abort, or dismisses the prompt
- **THEN** the file is not opened

#### Scenario: Owner still running
- **WHEN** the prompt is shown for a swap file whose process is still
  running
- **THEN** the prompt shows the process id, says the process is still
  running, and does not offer Delete it

### Requirement: Prompt only for files the plugin opens
The plugin's prompt SHALL appear only while the plugin itself is putting a
file into a pane. For a file the user opens, in a pane or anywhere else,
Neovim's own handling SHALL apply unchanged. When something else has already
decided what to do with a swap file, the plugin SHALL NOT ask.

#### Scenario: File opened by the user
- **WHEN** the user opens a file that has a leftover swap file with a
  command of their own
- **THEN** Neovim's own dialog handles it and the plugin's prompt is not
  shown

#### Scenario: Another handler decided
- **WHEN** a swap handler that runs before the plugin's has chosen what to
  do
- **THEN** the plugin does not ask and that choice is applied

#### Scenario: File of a cached worktree
- **WHEN** the plugin shows a file of a cached worktree
- **THEN** no swap file is involved and nothing is asked

### Requirement: A file that is not opened leaves the session consistent
When a file the plugin tried to show is not opened, the plugin SHALL report
one line that names the file, and SHALL NOT raise a Lua error. Every pane
the plugin had changed for the attempt SHALL show the file it showed before.
A pane the user navigated SHALL keep the file the user went to, as a plain
window. The files the session records as compared, and the mark in the
tree, SHALL be those from before the attempt.

#### Scenario: Selection declined
- **WHEN** the panes compare one file, the user selects another in the tree
  and answers Abort
- **THEN** both panes still show the first file in diff mode, the tree
  still marks it, and one line says the other file was not opened

#### Scenario: Selection declined with empty panes
- **WHEN** no file was selected before and the user answers Abort
- **THEN** both panes are empty, no line of the tree is marked, and one line
  says the file was not opened

#### Scenario: Second pane declined after the first was changed
- **WHEN** the before pane already shows the new file and the after pane's
  file is declined
- **THEN** the before pane shows its previous file again

#### Scenario: Counterpart of a jump declined
- **WHEN** the user jumps in the before pane to a file and declines its
  working tree counterpart
- **THEN** the before pane keeps the file the user jumped to, without diff
  mode, the after pane keeps its file, and the tree keeps its mark

#### Scenario: Returning after a declined jump
- **WHEN** the user then returns in the before pane to the file it showed
  before
- **THEN** both panes are in diff mode again

#### Scenario: Selecting again
- **WHEN** a file was declined and the user selects it again
- **THEN** the prompt is shown again

#### Scenario: One question per jump
- **WHEN** the user jumps in a pane to a file and declines its counterpart
- **THEN** the prompt is shown once for that jump, and again only after the
  pane showed another file and the user returns to that one

#### Scenario: File that landed in the pane of the other side
- **WHEN** a file of one side is opened in the pane of the other side and
  the user declines its counterpart
- **THEN** the prompt is shown once, the file stays in the pane it landed
  in, and the other pane and the tree's mark are unchanged

#### Scenario: Declined while the layout is reset
- **WHEN** `:TwintreeResetLayout` has to open the compared file again and
  the user declines it
- **THEN** the layout is rebuilt with empty panes, no file is recorded as
  compared, no line of the tree is marked, and the cursor is in the tree

### Requirement: Swap files without a user interface
When no user interface is attached, so that nobody can answer, the plugin
SHALL NOT ask and SHALL treat a swap file that needs a decision as a file
that is not opened.

#### Scenario: Headless session
- **WHEN** the plugin runs without a user interface and a file to show has a
  leftover swap file
- **THEN** the file is not opened, one line says so, and nothing waits for
  input
