# Spec Delta

## MODIFIED Requirements

### Requirement: Tab placement
A session SHALL always open in a new tab, which becomes the current tab.
The tab the command was run in SHALL stay as it was, also when it is the
only tab and shows nothing but an empty buffer.

#### Scenario: Opened from an editing session
- **WHEN** the user runs `:Twintree` while a file is open
- **THEN** the session opens in a new tab and the original tab is unchanged

#### Scenario: Started from the command line
- **WHEN** Neovim is started with `nvim +Twintree`
- **THEN** there are two tabs: the first holds one window with the empty
  buffer Neovim started with, the second holds the session and is the
  current tab

#### Scenario: Opened in an empty Neovim
- **WHEN** Neovim was started without a file and the user runs
  `:Twintree`
- **THEN** the session opens in a second tab and the first tab still
  holds its one empty window

#### Scenario: Ending a diff that was started from the command line
- **WHEN** Neovim is started with `nvim +Twintree` and the user runs
  `:tabclose` in the diff tab
- **THEN** the tab closes without an error, the first tab is the current
  one, no session is left, and the tree buffer of the diff is gone

#### Scenario: Ending a diff whose layout was changed
- **WHEN** Neovim is started with `nvim +Twintree`, the user closes a
  pane or opens another window in the diff tab, and runs `:tabclose`
- **THEN** the tab closes without an error, the first tab is the current
  one with its buffer as it was, no session is left, and the tree buffer
  of the diff is gone

#### Scenario: Ending a diff between other tabs
- **WHEN** a diff was opened from a tab that has tabs to its right, and
  the user runs `:tabclose` in the diff tab
- **THEN** the tab closes and Neovim chooses the current tab as it does
  for any closed tab

#### Scenario: Diff left as the only tab
- **WHEN** the user closes every other tab, or runs `:tabonly` in the
  diff tab, and then runs `:tabclose`
- **THEN** Neovim refuses to close the last tab, and the session stays
  as it is

#### Scenario: Open that fails
- **WHEN** `:Twintree` is run in the only tab and the session cannot be
  opened
- **THEN** there is still one tab, with its one window and its buffer as
  they were

#### Scenario: Layout that cannot be made
- **WHEN** the three windows of the session cannot be created, as in a
  terminal too small for them
- **THEN** an error message says so, the tab that was opened for the
  session is closed again, the tab the command was run in is the current
  one and unchanged, no session and no tree buffer is left, and no
  worktree this command created remains

#### Scenario: Tab closed while the first file is shown
- **WHEN** `:Twintree` is run in the only tab and an autocommand closes
  the new tab while the first file is shown
- **THEN** the command reports that the diff tab was closed, there is
  one tab with its one window as it was, and no tree buffer is left

#### Scenario: Started from the command line without changes
- **WHEN** Neovim is started with `nvim +Twintree` for a diff without
  changed files, on any supported Neovim version and with Neovim's
  bundled plugins loaded
- **THEN** the diff tab has exactly three windows, the cursor is in the
  tree window, no window shows the tree a second time, and the first tab
  still has its one window

#### Scenario: Previous window of the tree
- **WHEN** a session opens with the cursor in the tree window and the
  user presses `<C-w>p`
- **THEN** the cursor is in the after pane
