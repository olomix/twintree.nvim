# Spec Delta

## MODIFIED Requirements

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
- **WHEN** a diff session opens from the only tab of Neovim, as it does
  at startup, and so gets a second tab of its own
- **THEN** the keys work in the diff tab at once, also when its first
  file was not opened

#### Scenario: Key that reads like another key
- **WHEN** the user configured `<C-I>` for next and has a mapping of their
  own on `<Tab>`, which Neovim keeps apart from `<C-I>`, and a diff tab is
  entered and left
- **THEN** the mapping on `<Tab>` is untouched and the plugin's mapping is
  gone

#### Scenario: Key written with the leader
- **WHEN** the user configured `<Leader>n` for next, set `mapleader`
  after the call to `setup()`, and has a mapping of their own on that key
- **THEN** the key shows the next file in a diff tab, and the user's
  mapping is in place again in every other tab

#### Scenario: Leader changed while a diff tab is current
- **WHEN** `mapleader` changes while the plugin's key written with
  `<Leader>` is bound, and another tab becomes current
- **THEN** the mapping the plugin made under the old leader is gone and
  what the user had on that key is restored

#### Scenario: Two diff tabs
- **WHEN** two diff tabs are open and the user presses `]<C-f>` in each
- **THEN** each tab moves to its own next file

#### Scenario: Plugin reloaded
- **WHEN** the plugin is reloaded while a diff tab is current, `setup()`
  is called again as before, and the diff tab is then left
- **THEN** the keys still work in the diff tab and the user's mapping is
  restored on leaving
