# Spec Delta

## MODIFIED Requirements

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

#### Scenario: Started from the command line without changes
- **WHEN** Neovim is started with `nvim +Twintree` for a diff without
  changed files, on any supported Neovim version and with Neovim's
  bundled plugins loaded
- **THEN** the tab has exactly three windows, the cursor is in the tree
  window, and no window shows the tree a second time

#### Scenario: Previous window of the tree
- **WHEN** a session opens with the cursor in the tree window and the
  user presses `<C-w>p`
- **THEN** the cursor is in the after pane
