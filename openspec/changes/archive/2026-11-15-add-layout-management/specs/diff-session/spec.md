# Spec Delta

## MODIFIED Requirements

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
