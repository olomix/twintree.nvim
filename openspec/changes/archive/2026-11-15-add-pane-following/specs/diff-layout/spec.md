# Spec Delta

## ADDED Requirements

### Requirement: Reset keeps a file reached by navigation
`:TwintreeResetLayout` SHALL show, in both panes and in diff mode, the file
the panes compared before the reset, also when that file is not among the
changed files.

#### Scenario: File that is not in the tree
- **WHEN** the user jumped in a pane to a file that is not listed in the
  tree and runs `:TwintreeResetLayout`
- **THEN** both panes show that file in diff mode and no line of the tree is
  marked

#### Scenario: File outside both sides
- **WHEN** both panes show a file outside the root directories of both
  sides and the user runs `:TwintreeResetLayout`
- **THEN** both panes show that file in diff mode

#### Scenario: A buffer of the comparison was deleted
- **WHEN** the user deleted a buffer the panes compared and runs
  `:TwintreeResetLayout`
- **THEN** both panes show the file they compared again, in diff mode, and
  no Lua error is raised
