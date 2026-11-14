# revision-worktrees Specification

## Purpose

Provides a real directory on disk for a committed revision of a repository,
so that its files can be opened as normal buffers and served by language
servers, and manages the lifetime of those directories.

## Requirements

### Requirement: Worktree per repository and commit
The plugin SHALL back every side that is a commit with a git worktree checked
out at that commit with a detached HEAD. Worktrees SHALL be stored under a
plugin directory inside Neovim's cache directory, outside the inspected
repository, in a location determined by the repository and the full commit
hash.

#### Scenario: First use of a commit
- **WHEN** a session needs a commit that has no cached worktree
- **THEN** a worktree for that commit is created under the plugin cache
  directory and no branch is created or checked out

#### Scenario: Same directory name in two repositories
- **WHEN** two different repositories with the same directory name are diffed
- **THEN** their worktrees are stored in different locations

### Requirement: Reuse cached worktrees
The plugin SHALL reuse an existing cached worktree when it is checked out at
the requested commit, and SHALL NOT remove worktrees when a session ends.

#### Scenario: Reopening the same diff
- **WHEN** a session is opened for a commit whose worktree already exists
- **THEN** no new worktree is created and the existing one is used

#### Scenario: Cached directory is not a usable worktree
- **WHEN** the cached location exists but is not a worktree at the requested
  commit
- **THEN** it is replaced by a fresh worktree for that commit

### Requirement: The working tree is never a worktree copy
When a side is the working tree, the plugin SHALL use the user's checkout
directly and SHALL NOT create a worktree for it.

#### Scenario: Default session
- **WHEN** the user runs `:Twintree` with no arguments
- **THEN** exactly one worktree is in use, for the before commit

### Requirement: Worktree files are read-only
Every buffer for a file inside a cached worktree SHALL be read-only and not
modifiable, including files reached by navigation rather than by selection in
the tree.

#### Scenario: Selected file on the before side
- **WHEN** the user tries to change the text in the before pane
- **THEN** the change is refused

#### Scenario: File reached by go-to-definition
- **WHEN** the user jumps from the before pane to another file in the same
  worktree
- **THEN** that buffer is read-only and not modifiable as well

### Requirement: Clean cached worktrees
The plugin SHALL provide a `:TwintreeClean` command that removes the cached
worktrees of the current repository, both from disk and from the repository's
worktree registry, and reports how many were removed. Worktrees used by an
open session SHALL be kept.

#### Scenario: Cleaning with no open session
- **WHEN** the user runs `:TwintreeClean` and no session is open
- **THEN** all cached worktrees of the current repository are deleted and
  `git worktree list` no longer shows them

#### Scenario: Cleaning with an open session
- **WHEN** the user runs `:TwintreeClean` while a session is open
- **THEN** the worktrees of that session are kept and the others are removed

### Requirement: Report worktree creation failures
The plugin SHALL report git's error output and SHALL NOT open a session when
a required worktree cannot be created.

#### Scenario: Creation fails
- **WHEN** git fails to create a worktree
- **THEN** the user sees git's error message and no session tab is opened

#### Scenario: Checkout hook fails
- **WHEN** a post-checkout hook of the repository fails while the worktree is
  created
- **THEN** the error is reported and no worktree for that commit remains on
  disk or in the repository's worktree registry
