# Design

## Context

A side that is a commit is backed by a git worktree under the plugin's
cache directory, `<cache>/<repository>-<hash>/<commit>`. `worktree.lua`
knows whether a path lies in the cache (`is_cached`, which resolves
symbolic links first and tests only the prefix of the cache directory)
and makes every buffer of such a file read-only. The working directory is
never copied: its files are the user's own.

`show_pair` registers the two buffers of a pair with `bufadd()` and lists
them. Navigation in a pane loads further buffers of the same worktree.

A session is plain data in a tab variable and ends when its tab is
closed. `plugin/twintree.lua` has a `TabClosed` autocommand that calls
`treeview.sweep()`, which deletes every tree buffer that no open session
owns. That function needs no record of the closed tab: by the time
`TabClosed` fires, the tab variable is gone. `session.roots_in_use()`
lists the worktree roots of the sides that are commits, for
`:TwintreeClean`; the roots are resolved paths.

Checked with the current code and a headless Neovim, on 0.11, 0.12 and
nightly:

- After a diff tab is closed, the buffers of its cached worktree are
  hidden, loaded and listed. So are the buffers of the working directory
  that the plugin loaded.
- When `TabClosed` fires, the session of the closed tab is gone and its
  windows are closed. `:tabclose` of another tab and `:q` on the last
  window fire it once, `:tabonly` once per closed tab, `:qa` not at all.
- The `TabClosed` autocommand is not nested, so a buffer wiped out in it
  fires no `BufUnload`, `BufDelete` or `BufWipeout`. `vim.diagnostic`
  then keeps the diagnostics of the wiped buffer, and
  `vim.diagnostic.setqflist()` fails on them.
- With an LSP server that runs inside Neovim (`vim.lsp.start` with a Lua
  function as `cmd`): wiping out a buffer detaches it from its client at
  once; the client stays in `vim.lsp.get_clients()` with no attached
  buffers. A client has `root_dir`, `workspace_folders` (tables with a
  `uri`) and `attached_buffers`.
- `client:stop(false)` sends the shutdown request and never forces.
  `client:stop()` without an argument takes the client's `exit_timeout`
  on 0.12 and later, and a second `stop` on a client that is already
  stopping terminates it on nightly. `client:is_stopped()` is true from
  the moment the stop was asked, not from the moment the server exited.
- `vim.lsp.get_clients()` does not list a client that is still
  initializing.
- A quickfix or location-list entry of a wiped buffer loses its buffer,
  and jumping to it fails.

The help file says "The plugin contains no LSP code", and the README says
that with cached worktrees "language servers keep their index".

See proposal.md for the motivation.

## Goals / Non-Goals

**Goals:**

- No state: what to release follows from the buffers, the open sessions
  and the LSP clients as they are when a tab is closed.
- Nothing of the user's is removed: only buffers of files in a cached
  worktree, and only clients that work on nothing else.
- Closing a tab never ends in an error because of the release.

**Non-Goals:**

- Removing buffers of the working directory that the plugin loaded.
- Language servers outside Neovim's built-in client.
- A client that is still initializing when the tab is closed. Finding it
  needs a private function of Neovim. It is stopped with the next closed
  tab, and the help file says so.
- Keeping jump-list, tag-stack and alternate-file entries of a wiped
  buffer.
- An option to keep buffers or servers. If restarting a slow server on
  every reopened diff turns out to hurt, an option is a later change.
- Removing worktree directories; that stays with `:TwintreeClean`.

## Decisions

### 1. One stateless sweep in a nested `TabClosed` autocommand

`worktree.lua` gets a function that releases what belongs to unused
cached worktrees. The existing `TabClosed` autocommand calls it after
`treeview.sweep()`. There stays exactly one `TabClosed` autocommand in
the group; an existing spec counts them.

The autocommand becomes `nested = true`. Without it Neovim fires no
buffer events for what the callback wipes out, and everything that cleans
up per buffer is skipped. `treeview.sweep()` then fires those events for
the tree buffer as well, which is harmless. Wiping out a hidden buffer
enters no window, so `session.follow` does not run.

It runs for every closed tab, not only for a diff tab: the closed tab can
no longer say what it was, and a buffer that was kept because a window
showed it should go once that is no longer so.

Alternative: record in the session which buffers it loaded and remove
those. Rejected: the record dies with the tab before `TabClosed` fires,
and it would miss buffers reached by navigation unless every buffer load
were tracked.

Alternative: defer the sweep with `vim.schedule`. Rejected: it would run
at an arbitrary later moment, when the user may already have opened the
same diff again.

### 2. Which worktree a path belongs to, and which are in use

A path belongs to a cached worktree when, after `worktree.resolve`, it
lies at or below a directory two levels under the resolved cache
directory, `<cache>/<repository>-<hash>/<commit>`. That directory is its
worktree root. A file directly in the cache directory or in a repository
directory belongs to none and is never touched. `is_cached` alone is too
wide for this, so `worktree.lua` gets a function that returns the
worktree root of a path, or nil.

The roots in use are the roots of both panes of every open session,
whether the side is a commit or not. `roots_in_use()` covers only commit
sides; a diff opened from inside a cached worktree has that worktree as
its working directory, and it must count. `session.lua` gets a function
that returns all pane roots, and `roots_in_use()` keeps its meaning for
`:TwintreeClean`.

A worktree root that still exists on disk is compared in resolved form.
The worktree of a path whose directory was removed by `:TwintreeClean`
cannot be resolved through a symbolic link; such a buffer may be left
behind, which is harmless.

### 3. Which buffers

A buffer is wiped out when all of these hold:

- it is a normal file buffer (`buftype` is empty) with a name;
- its path belongs to a cached worktree (decision 2);
- that worktree root is not a root in use;
- no window of any tab shows it;
- no quickfix or location list refers to it;
- it is not modified.

The buffers that lists refer to are collected once per sweep: from every
list of the quickfix stack, and from every list of the location-list
stack of every window.

It is removed with `pcall(vim.cmd.bwipeout, buf)`. That is `:bwipeout`
without force: marks and the buffer number go as well, and a buffer that
cannot be wiped out is left. `pcall(vim.api.nvim_buf_delete, …)` is not
used: in a nested autocommand an error raised by a `BufWipeout`
autocommand of the user escapes it and stops the remaining wipes.

A buffer of a cached file that the user opened by hand, outside a diff,
is treated the same: hidden and unused, it goes with the next closed tab.

Alternative: `:bdelete`, which keeps the buffer as an unlisted entry.
Rejected by the owner.

### 4. Which language servers

After the buffers, for each client of `vim.lsp.get_clients()`:

- it has no attached buffer;
- it is not stopping already (`client:is_stopped()` is false);
- it has at least one folder: every `workspace_folders` entry converted
  with `vim.uri_to_fname(folder.uri)`, or `root_dir` when there are
  none;
- every folder belongs to a cached worktree (decision 2) whose root is
  not a root in use.

Because a folder must lie at or below a commit directory, a folder above
the commit directories, which may span a worktree in use, never
qualifies. A folder equal to a worktree root or in a subdirectory of it
belongs to that worktree.

Such a client is stopped with `pcall(client.stop, client, false)`. The
explicit `false` asks for a normal shutdown on every supported version
and never forces; skipping a client that is already stopping keeps a
second closed tab from terminating it.

The conditions keep the plugin away from a server that is idle for
another reason, such as one of the user's projects whose buffers are
closed, and from a server that also works on the working directory. A
client without any folder is never stopped.

Alternative: stop nothing and let idle servers run. Rejected by the
owner.

Alternative: match servers by name. Rejected: the rule above is the same
for every server and needs no list.

### 5. Order and failure

Buffers first, then clients: wiping out a buffer is what detaches it, and
only then does a client have none left. A failure in either step is
swallowed for that one buffer or client and the rest goes on. Nothing is
reported: the user closed a tab and asked for nothing.

### 6. Specs use a server inside Neovim

`tests/helpers.lua` gets a function that starts an LSP client whose
server is a Lua table. It answers `initialize` at once, records the
`shutdown` request and the `exit` notification, can be told to delay its
answer to `shutdown` or to raise in it, and implements `is_closing` and
`terminate`, recording a `terminate` call. Each client gets its own
name, because `vim.lsp.start` reuses a client with the same name and
root.

A spec that says a server was stopped waits for the recorded `exit` and
for the client to leave `vim.lsp.get_clients()`; `is_stopped()` alone
proves nothing. A spec that says a server was not forced asserts that
`terminate` was not recorded.

The specs that keep something because its worktree is in use must hold a
buffer that no window shows, or a client with no buffer attached.
Otherwise the window rule or the attached-buffer rule keeps it, and the
rule about roots in use is not tested.

### 7. Documentation

- `doc/twintree.txt`, LANGUAGE SERVERS: the plugin starts and configures
  no server; when a cached worktree is no longer used by any diff, it
  wipes out the buffers of its files and stops the built-in LSP clients
  that worked on nothing else. A server that was still starting when the
  tab was closed is stopped with the next closed tab.
- `README.md`, Worktrees: worktrees are kept and reused, so reopening a
  diff does not check the commit out again; the language server of a
  worktree runs while a diff of it is open.
- A short paragraph where closing a diff is described, with what is
  kept: shown buffers, buffers in a quickfix or location list, changed
  buffers.

## Risks / Trade-offs

- [Reopening the same diff starts its language server again, which can
  take long for a server that indexes the whole project] → Accepted by
  the owner. An option is a possible later change.
- [A user keeps a file of a cached worktree in a hidden buffer on
  purpose; jump-list, tag-stack and alternate-file entries of it go] →
  It is wiped out with the next closed tab. The file is still on disk
  while the worktree is cached.
- [A nested `TabClosed` lets autocommands of the user run during the
  sweep; one of them could open a diff or close a tab] → The sweep reads
  the roots in use once at its start and tolerates a buffer that is gone
  or cannot be wiped. A tab closed inside it runs its own sweep.
- [A tab closed in the middle of `show_pair`, `open` or `reset_layout`
  now also wipes buffers] → Those paths already report a closed tab; the
  specs of show safety must pass unchanged.
- [A buffer referred to by an old quickfix list stays until that list is
  dropped] → Accepted: a working list is worth more than one buffer.
- [The plugin now calls the LSP API, which changes between Neovim
  versions] → Only `get_clients`, `attached_buffers`,
  `workspace_folders`, `root_dir`, `is_stopped` and `stop`, checked on
  the three versions CI runs; the calls are wrapped in `pcall`.

## Open Questions

None.
