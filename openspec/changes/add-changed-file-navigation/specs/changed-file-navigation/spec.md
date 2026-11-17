# Spec Delta

## Purpose

Lets a user step through the changed files of a diff session from any
window of the diff tab, with commands and with keys that exist only while
a diff tab is current.

## ADDED Requirements

### Requirement: Commands move between the changed files
The plugin SHALL provide `:TwintreeNextFile`, `:TwintreePrevFile`,
`:TwintreeFirstFile` and `:TwintreeLastFile`. Each SHALL show its target
file in both panes as a selection in the tree does, including the mark in
the tree and the cursor position inside the file, except that the current
window does not change. Next and previous SHALL accept a count.

#### Scenario: Next file
- **WHEN** the panes show a changed file that is not the last one and the
  user runs `:TwintreeNextFile`
- **THEN** both panes show the file on the next file line of the tree, in
  diff mode, and that line is marked as selected

#### Scenario: Previous file
- **WHEN** the panes show a changed file that is not the first one and
  the user runs `:TwintreePrevFile`
- **THEN** both panes show the file on the previous file line of the tree

#### Scenario: First and last file
- **WHEN** the user runs `:TwintreeFirstFile` or `:TwintreeLastFile`
- **THEN** both panes show the first or the last file of the tree

#### Scenario: First file when it is already shown
- **WHEN** the panes show the first file and the user runs
  `:TwintreeFirstFile`
- **THEN** the panes still show it, the cursor inside it has not moved,
  and nothing is reported

#### Scenario: Count
- **WHEN** the user runs `:3TwintreeNextFile` with at least three files
  after the current one
- **THEN** the panes show the third file after the current one

#### Scenario: Count past the end
- **WHEN** the user runs `:5TwintreeNextFile` with two files after the
  current one
- **THEN** the panes show the last file and nothing is reported

#### Scenario: Count past the start
- **WHEN** the user runs `:5TwintreePrevFile` with two files before the
  current one
- **THEN** the panes show the first file and nothing is reported

#### Scenario: Tree hidden
- **WHEN** the tree is hidden and the user runs `:TwintreeNextFile`
- **THEN** the panes show the next file and the tree stays hidden

#### Scenario: No diff session
- **WHEN** the user runs one of the commands in a tab without a diff
  session
- **THEN** one line says there is no diff session in this tab and nothing
  else changes

### Requirement: The order is the order of the tree
The commands SHALL visit the files in the order of the file lines of the
tree. Files inside a collapsed directory SHALL be skipped.

#### Scenario: File in a directory listed first
- **WHEN** the tree lists a file inside a directory above a top-level
  file and the panes show the file in the directory
- **THEN** `:TwintreeNextFile` shows the top-level file

#### Scenario: Collapsed directory in between
- **WHEN** a collapsed directory lies between the current file and the
  next visible file line
- **THEN** `:TwintreeNextFile` shows the file on that next visible line
  and the directory stays collapsed

#### Scenario: Current file inside a collapsed directory
- **WHEN** the user collapses the directory of the file the panes show
  and runs `:TwintreeNextFile`
- **THEN** the panes show the first visible file below that directory

#### Scenario: First and last with collapsed directories
- **WHEN** the first file of the tree is inside a collapsed directory and
  the user runs `:TwintreeFirstFile`
- **THEN** the panes show the first file that is visible in the tree

### Requirement: The commands stop at the ends
When there is no file to move to, the commands SHALL leave the panes as
they are and SHALL report one line that is not an error. They SHALL NOT
continue from the other end of the list.

#### Scenario: Next on the last file
- **WHEN** the panes show the last file and the user runs
  `:TwintreeNextFile`
- **THEN** the panes still show that file and one line says
  "no more changed files"

#### Scenario: Previous on the first file
- **WHEN** the panes show the first file and the user runs
  `:TwintreePrevFile`
- **THEN** the panes still show that file and one line says
  "no more changed files"

#### Scenario: One changed file
- **WHEN** the diff has one changed file, which the panes show, and the
  user runs `:TwintreeNextFile`
- **THEN** one line says "no more changed files"

#### Scenario: No changed files
- **WHEN** the diff has no changed files and the user runs any of the
  four commands
- **THEN** one line says "no changed files" and the panes are as they
  were

#### Scenario: List empty after a refresh
- **WHEN** the panes show a file, a refresh leaves no changed file, and
  the user runs `:TwintreeNextFile`
- **THEN** one line says "no changed files" and the panes still show that
  file

#### Scenario: Every file is inside a collapsed directory
- **WHEN** the diff has changed files, none of their lines is visible in
  the tree, and the user runs any of the four commands
- **THEN** one line says "every changed file is in a collapsed directory"
  and the panes are as they were

### Requirement: Continue from the changed file shown last
Next and previous SHALL be relative to the changed file the panes show.
When the panes show a file that is not in the list, they SHALL be relative
to the changed file that was shown last. When no changed file was shown,
or that file is no longer in the list, next SHALL show the first file and
previous the last. A file that was not opened does not count as shown.

#### Scenario: After a jump to another file
- **WHEN** the panes showed the second changed file, the user jumped from
  it to a file that did not change, and runs `:TwintreeNextFile`
- **THEN** the panes show the third changed file

#### Scenario: Nothing shown yet
- **WHEN** the panes are empty because the first file was not opened when
  the session opened, and the user runs `:TwintreeNextFile`
- **THEN** the first file of the tree is the target

#### Scenario: Previous with nothing shown
- **WHEN** no changed file was shown and the user runs
  `:TwintreePrevFile`
- **THEN** the panes show the last file of the tree

#### Scenario: File gone after a refresh
- **WHEN** the file shown last is no longer changed after the tree was
  refreshed, and the user runs `:TwintreeNextFile`
- **THEN** the panes show the first file of the tree

#### Scenario: File that became a changed file
- **WHEN** the panes show a file that was not in the list, a refresh puts
  it into the list, the user jumps to another file that did not change,
  and runs `:TwintreeNextFile`
- **THEN** the panes show the file after the one the refresh marked

### Requirement: The current window stays current
The commands SHALL work from every window of a diff tab, and the window
they were given in SHALL remain the current window. The cursor of every
window of the tab that shows the tree SHALL be on the line of the file
that was shown.

#### Scenario: From the before pane
- **WHEN** the cursor is in the before pane and the user runs
  `:TwintreeNextFile`
- **THEN** the next file is shown and the cursor is in the before pane

#### Scenario: From the tree
- **WHEN** the cursor is in the tree window and the user runs
  `:TwintreeNextFile`
- **THEN** the next file is shown with its first change visible in both
  panes, the cursor is still in the tree window, and it is on the line of
  that file

#### Scenario: From a window the user opened
- **WHEN** the cursor is in a window the user split off in the diff tab
  and the user runs `:TwintreeNextFile`
- **THEN** the panes show the next file and that window is still current
  and shows what it showed

#### Scenario: Tree shown in a window the user made
- **WHEN** the user closed the tree window, shows the tree buffer in
  another window of the tab, and runs `:TwintreeNextFile` there
- **THEN** the next file is shown and the cursor of that window is on its
  line

#### Scenario: Tree window showing another buffer
- **WHEN** the user put another buffer into the tree window and runs
  `:TwintreeNextFile`
- **THEN** the next file is shown, the cursor of that window has not
  moved, and no Lua error is raised

### Requirement: A target that cannot be shown leaves the session as it was
When the target file is not opened, or a pane of the diff is missing, the
commands SHALL report one line as an error, SHALL leave the panes, the
selection and the position for next and previous as they were, and SHALL
NOT raise a Lua error.

#### Scenario: Pane missing
- **WHEN** a pane was closed and the user runs `:TwintreeNextFile`
- **THEN** one line says a pane is missing and names
  `:TwintreeResetLayout`, and no Lua error is raised

#### Scenario: Swap file question declined
- **WHEN** the panes show the first of three files, the second has a
  leftover swap file, and the user runs `:TwintreeNextFile` and answers
  Abort
- **THEN** the panes show the first file, one line says the second was
  not opened, and `:2TwintreeNextFile` then shows the third

#### Scenario: Tree buffer deleted
- **WHEN** the user deleted the tree buffer and runs `:TwintreeNextFile`
- **THEN** the next file is shown and no Lua error is raised

### Requirement: Default keys exist only while a diff tab is current
In normal mode `]<C-f>` SHALL run next and `[<C-f>` previous, each with
the count given, while the current tab holds a diff session. In every
other tab those keys SHALL do what they did before the plugin bound them:
the user's global normal-mode mapping on a key SHALL be restored with its
options and description. Mappings in other modes SHALL NOT be touched.

#### Scenario: Keys in a diff tab
- **WHEN** the cursor is in a pane of a diff tab and the user presses
  `]<C-f>`
- **THEN** the next file is shown

#### Scenario: Count with a key
- **WHEN** the user presses `2]<C-f>` in a diff tab
- **THEN** the second file after the current one is shown

#### Scenario: End of the list with a key
- **WHEN** the panes show the last file and the user presses `]<C-f>`
- **THEN** one line says "no more changed files", and it is not reported
  as an error

#### Scenario: The user's mapping in another tab
- **WHEN** the user has a mapping on `]<C-f>`, a diff tab is open, and
  the user presses the key in a tab without a diff session
- **THEN** the user's mapping runs and no file of the diff changes

#### Scenario: The user's mapping after the diff is closed
- **WHEN** the user closes the diff tab
- **THEN** the normal-mode mapping the user had on each key is in place
  again with the same options and description, and a key the user had not
  mapped is not mapped

#### Scenario: Mapping for several modes
- **WHEN** the user has one mapping on `]<C-f>` for normal, visual and
  operator-pending mode, and a diff tab is entered and left
- **THEN** the key does in each of the three modes what it did before

#### Scenario: Other modes changed during the diff
- **WHEN** the user has such a mapping, changes what the key does in
  visual mode while a diff tab is current, and leaves the tab
- **THEN** the key does in visual mode what the user last set, and in
  normal mode what it did before the diff

#### Scenario: Buffer-local mapping in the current buffer
- **WHEN** the buffer shown in a pane has a buffer-local mapping on
  `]<C-f>`, the user has a global one as well, and the diff tab is
  entered and left with that buffer current
- **THEN** the global mapping is restored unchanged, the buffer-local one
  is untouched, and the plugin's mapping is gone

#### Scenario: Diff opened in the only tab
- **WHEN** a diff session opens in the tab Neovim started with
- **THEN** the keys work in it at once, also when its first file was not
  opened

#### Scenario: Key that reads like another key
- **WHEN** the user configured `<C-I>` for next and has a mapping of their
  own on `<Tab>`, which Neovim keeps apart from `<C-I>`, and a diff tab is
  entered and left
- **THEN** the mapping on `<Tab>` is untouched and the plugin's mapping is
  gone

#### Scenario: Two diff tabs
- **WHEN** two diff tabs are open and the user presses `]<C-f>` in each
- **THEN** each tab moves to its own next file

#### Scenario: Plugin reloaded
- **WHEN** the plugin is reloaded while a diff tab is current, `setup()`
  is called again as before, and the diff tab is then left
- **THEN** the keys still work in the diff tab and the user's mapping is
  restored on leaving

### Requirement: A key mapped again by the user is left alone
When the user, or anything else, maps or unmaps one of the plugin's keys
in normal mode while a diff tab is current, the plugin SHALL NOT change
that key again, neither on leaving the tab nor on entering a diff tab
later. The plugin SHALL bind that key again only after the next accepted
call to `setup()`.

#### Scenario: Mapped again in a diff tab
- **WHEN** the user maps `]<C-f>` to something else while a diff tab is
  current and then goes to another tab and back
- **THEN** the user's new mapping is in place in both tabs and the
  mapping on `[<C-f>` is still the plugin's in the diff tab

#### Scenario: Second diff tab
- **WHEN** the user mapped `]<C-f>` again in one diff tab and enters a
  second diff tab
- **THEN** the user's mapping is in place there too

#### Scenario: Unmapped in a diff tab
- **WHEN** the user removes the mapping on `]<C-f>` while a diff tab is
  current and then goes to another tab and back
- **THEN** the key is not mapped in either tab

#### Scenario: After setup
- **WHEN** the user mapped `]<C-f>` again in a diff tab and then calls
  `setup()` there, without changing tabs in between
- **THEN** the plugin's key works in that tab at once, and on leaving the
  tab the mapping the user made is in place

### Requirement: Keys follow tab changes that fire events
The plugin SHALL bind and release the keys when a tab becomes current in
a way that fires Neovim's tab events. After a tab change that fired no
event, the first press of a plugin key in a tab without a diff session
SHALL release the plugin's keys and do nothing else; from then on the
keys do what they did before. In a diff tab entered without an event the
keys MAY be missing until the next tab event; the commands SHALL work
regardless.

#### Scenario: Leaving a diff tab without events
- **WHEN** another tab became current in a way that fired no event, and
  the user presses `]<C-f>` there twice
- **THEN** the first press changes no file and reports no error, both
  plugin mappings are gone after it, and the second press runs the
  user's own mapping, or Neovim's handling of the key when there is none

#### Scenario: Back in a diff tab
- **WHEN** the keys were released by such a press and the user then
  enters a diff tab in a way that fires an event
- **THEN** the keys work there

#### Scenario: Leaving without events after a reload
- **WHEN** the plugin was reloaded in a diff tab, another tab became
  current without an event, and the user presses `]<C-f>` there
- **THEN** the plugin's mappings are gone and no Lua error is raised

#### Scenario: Entering a diff tab without events
- **WHEN** a diff tab became current in a way that fired no event
- **THEN** `:TwintreeNextFile` works, and the keys work after the next
  change of tab that fires an event

### Requirement: The keys are configurable
The keys for next and previous SHALL be options of `setup()`. Setting one
to `false` SHALL leave that action without a key. A call to `setup()`
while a diff tab is current SHALL take effect at once. A call with a
value that is not usable SHALL be reported in one line and SHALL change
nothing: every option, every mapping and every key the plugin gave up
stay as they were.

#### Scenario: Other keys
- **WHEN** the user configures other keys for next and previous
- **THEN** those keys work in a diff tab and `]<C-f>` and `[<C-f>` are
  not mapped by the plugin

#### Scenario: A key turned off
- **WHEN** the user sets the key for next to `false`
- **THEN** the plugin maps no key for next, `:TwintreeNextFile` still
  works, and the key for previous is mapped

#### Scenario: Reconfigured in a diff tab
- **WHEN** the user calls `setup()` with other keys while a diff tab is
  current
- **THEN** the new keys work in that tab, and the old keys do what they
  did before the plugin bound them

#### Scenario: Keys swapped in a diff tab
- **WHEN** the user calls `setup()` with the keys for next and previous
  exchanged while a diff tab is current, and then leaves the tab
- **THEN** each key runs its new action in the diff tab, and after
  leaving, the mappings the user had before the diff are in place and no
  mapping of the plugin is left

#### Scenario: The same key for both actions
- **WHEN** the user configures one key for next and for previous, also
  when it is written differently, as `]<C-f>` and `]<c-f>`
- **THEN** one line says so and the keys in use are the ones from before
  that call

#### Scenario: Not a usable value
- **WHEN** the user sets the option to a value that is not a table, a key
  to an empty string, to a key Neovim cannot map, or to a value that is
  neither a string nor `false`, or names an action the plugin does not
  have
- **THEN** one line says so, no Lua error is raised then or on a later
  change of tab, and the keys in use are the ones from before that call

#### Scenario: Invalid call after a key was given up
- **WHEN** the plugin gave up a key the user mapped again, and the user
  calls `setup()` with a value that is not usable
- **THEN** the user's mapping on that key is still in place

#### Scenario: Reload without setup
- **WHEN** the plugin's modules are reloaded and `setup()` is not called
  again
- **THEN** the default keys apply from the next change of tab, until
  `setup()` is called
