# Spec Delta

## ADDED Requirements

### Requirement: Buffers of unused worktrees are wiped out
When a tab is closed, the plugin SHALL wipe out every buffer of a file
inside a cached worktree that no open session uses, unless a window shows
the buffer, a quickfix or location list refers to it, or it has unsaved
changes. Wiping out SHALL fire Neovim's buffer events. The plugin SHALL
NOT wipe out, unload or unlist any other buffer, and a buffer it cannot
wipe out SHALL NOT cause an error.

#### Scenario: Closing a diff tab
- **WHEN** the user closes a diff tab whose before side is a cached
  worktree
- **THEN** the buffers of that worktree no longer exist, including those
  the user reached by navigation and those that were unloaded

#### Scenario: Buffer events
- **WHEN** a buffer of the worktree has diagnostics and an autocommand of
  the user for `BufWipeout`, and the user closes the diff tab
- **THEN** that autocommand ran for the buffer, and no diagnostics of the
  buffer are left

#### Scenario: Files of the working directory
- **WHEN** the user closes a diff tab whose after side is the working
  directory
- **THEN** every buffer of a file in the working directory still exists
  and is still listed, also the ones the plugin loaded

#### Scenario: File in the cache directory outside a worktree
- **WHEN** a hidden buffer shows a file that lies in the plugin's cache
  directory but not inside a worktree of a commit, and a tab is closed
- **THEN** that buffer still exists

#### Scenario: Worktree used by another diff tab
- **WHEN** two diff tabs use the same cached worktree, a buffer of that
  worktree is hidden in both, and the user closes one of the tabs
- **THEN** that buffer still exists, and the other tab still shows its
  files

#### Scenario: Two worktrees
- **WHEN** two diff tabs use different cached worktrees and the user
  closes one of them
- **THEN** only the buffers of the worktree of the closed tab are gone

#### Scenario: Closing a tab that is not a diff
- **WHEN** a diff tab is open, a buffer of its worktree is hidden, and the
  user closes a tab without a session
- **THEN** that buffer still exists

#### Scenario: Working directory that is itself a cached worktree
- **WHEN** a diff was opened from inside a cached worktree, so that this
  worktree is its working directory, and another tab is closed
- **THEN** the hidden buffers of that worktree still exist

#### Scenario: Buffer shown in another window
- **WHEN** a window of another tab shows a buffer of the worktree and the
  user closes the diff tab
- **THEN** that buffer still exists and the window still shows it, and
  the other buffers of the worktree are gone

#### Scenario: Shown buffer that is hidden later
- **WHEN** such a buffer is hidden later and any tab is then closed
- **THEN** the buffer no longer exists

#### Scenario: Buffer in a quickfix or location list
- **WHEN** the quickfix list, an older list of its stack, or the location
  list of a window has an entry for a buffer of the worktree, and the
  user closes the diff tab
- **THEN** that buffer still exists and the entry can still be opened

#### Scenario: Buffer with unsaved changes
- **WHEN** the user made a buffer of the worktree modifiable, changed it,
  and closes the diff tab
- **THEN** that buffer still exists with its changes, and no error is
  reported

#### Scenario: Autocommand that fails
- **WHEN** an autocommand of the user for `BufWipeout` raises an error for
  one buffer of the worktree, and the user closes the diff tab
- **THEN** the tab is closed without an error and the other buffers of
  the worktree are gone

#### Scenario: Autocommand that fails for every buffer
- **WHEN** an autocommand of the user for `BufWipeout` raises an error for
  every buffer, and the user closes the diff tab
- **THEN** the tab is closed without an error

#### Scenario: Layout changed before the tab is closed
- **WHEN** the user closed a pane, put another file into a pane, or split
  a pane of a diff tab, and then closes that tab
- **THEN** the buffers of its worktree that no window shows are gone, and
  no error is reported

#### Scenario: Pane closed while the diff stays open
- **WHEN** the user closed the before pane of a diff tab, so that its
  buffer is hidden, and then closes another tab
- **THEN** that buffer still exists

#### Scenario: The plugin's own buffers
- **WHEN** a diff tab is closed
- **THEN** the empty placeholder buffer still exists, and the tree buffer
  of the closed tab is gone as before

#### Scenario: Worktree directories
- **WHEN** the buffers of a cached worktree were wiped out
- **THEN** the worktree is still on disk, and opening the same diff again
  reuses it and shows its files

### Requirement: Language servers of unused worktrees are stopped
After the buffers of unused worktrees were wiped out, the plugin SHALL
stop, without force, every client of Neovim's built-in LSP client that
has no buffer attached and whose workspace folders each lie inside a
cached worktree that no open session uses. It SHALL NOT stop any other
client, and a client it cannot stop SHALL NOT cause an error.

#### Scenario: Server of a closed diff
- **WHEN** a language server runs for a cached worktree, its only buffers
  are of that worktree, and the user closes the diff tab
- **THEN** the server receives its shutdown request and exits

#### Scenario: Server of the working directory
- **WHEN** a language server runs for the working directory and the user
  closes the diff tab
- **THEN** that server still runs, also when no buffer is attached to it

#### Scenario: Worktree still in use
- **WHEN** two diff tabs use the same cached worktree, the language
  server of that worktree has no buffer attached, and the user closes one
  of the tabs
- **THEN** the server still runs

#### Scenario: Server with a buffer left
- **WHEN** a buffer of the worktree that is attached to the server was
  not wiped out, because a window shows it or it has unsaved changes, and
  the user closes the diff tab
- **THEN** the server still runs

#### Scenario: Server shared with the working directory
- **WHEN** one language server has a workspace folder in the cached
  worktree and another in the working directory, and the user closes the
  diff tab
- **THEN** the server still runs

#### Scenario: Server above the worktrees
- **WHEN** the workspace folder of a language server is a directory of
  the cache above the worktrees of the commits, and one of those
  worktrees is still used by a diff tab
- **THEN** the server still runs when another tab is closed

#### Scenario: Server in a subdirectory
- **WHEN** the root of a language server is a subdirectory of the cached
  worktree, it has no buffer left, and the user closes the diff tab
- **THEN** the server is stopped

#### Scenario: Server of a removed worktree
- **WHEN** `:TwintreeClean` removed a cached worktree while a buffer of it
  was still shown, and that buffer is hidden later and a tab is closed
- **THEN** the buffer is gone and the language server of that worktree is
  stopped

#### Scenario: Server without a workspace
- **WHEN** a language server has no root directory and no workspace
  folder
- **THEN** the plugin never stops it

#### Scenario: Server that is already stopping
- **WHEN** a server was asked to stop and has not exited yet, and another
  tab is closed
- **THEN** the plugin does not ask it again and does not force it

#### Scenario: Server that fails to stop
- **WHEN** stopping one server raises an error
- **THEN** the tab is closed without an error and the other servers of
  unused worktrees are stopped

#### Scenario: No language server
- **WHEN** no language server runs and a diff tab is closed
- **THEN** the buffers are wiped out and no error is reported
