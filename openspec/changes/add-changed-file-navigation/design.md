# Design

## Context

A file is selected through `session.show(tab, entry)`, called by `<CR>` in
the tree and by `init.open`. It shows the pair, marks the tree line,
places the cursor inside the file and makes the after pane current.

`show_pair` sets `state.selected` before it opens the files. When a file
is not opened, `undo_pair` puts `pair`, `selected` and `bufs` back.
`treeview.refresh` computes `selected` again from the pair the panes
show, so a refresh can mark a file that was not in the list before.
`init.open` returns early, with the session open, when the first file is
not shown.

The tree draws from `tree.lines(entries, { collapsed = ... })`, which
walks `tree.build(entries)`; the children of a collapsed directory get no
line. The entries live in a variable of the tree buffer, and
`treeview.ensure_buf` rebuilds that buffer when the user deleted it.
`show_pair` puts the cursor of the tree on the selected file only in the
window `session.tree_win` recognises: the recorded tree window, while it
still shows the tree buffer.

`state.selected` is nil when the panes are empty and when they show a
file that is not in the list, which is the normal state after a jump to a
definition.

The plugin has no mappings outside the tree buffer today. The panes show
ordinary buffers, and a working tree buffer can be open in other tabs, so
a buffer-local mapping would follow the buffer out of the diff.

Checked headless on Neovim 0.11, 0.12 and a current development build,
with the same results on all three:

- `maparg(lhs, "n", false, true)` returns a buffer-local mapping of the
  current buffer when there is one, not the global mapping.
  `nvim_get_keymap("n")` lists global mappings only.
- The `lhsraw` of such an entry is not what `vim.keycode()` returns for
  the same key; `vim.keycode(entry.lhs)` is.
- An entry of `nvim_get_keymap` restored with `mapset()` brings back a
  Lua callback, an expression mapping, the options and the description.
- Setting a normal-mode mapping on a key that has a `:map` mapping for
  normal, visual and operator-pending mode leaves the user's mapping in
  place for the other two modes. `mapset("n", false, entry)` then puts
  the normal-mode part back and does not touch the other modes;
  `mapset(entry)` would write all three.
- Such an entry, callback included, can be stored in a `g:` variable and
  restored from there.
- `vim.keymap.set` raises an error for an empty key.
- `:tabnew`, `:tabnext` and `:tabclose` fire `TabEnter` for the tab that
  becomes current. `:noautocmd tabnext` fires nothing.
- `normal! ]c` run through `nvim_win_call` in the after pane moves the
  cursor of the before pane too, while another window is current.

See proposal.md for the motivation and the choice of keys.

## Goals / Non-Goals

**Goals:**

- Without a diff session the plugin leaves no mapping behind.
- The user's own global normal-mode mapping on the same keys is restored,
  not imitated, and nothing else of the user's is written.
- Navigation needs no window to be in a particular place, the tree
  included.

**Non-Goals:**

- Winning over a buffer-local mapping another plugin puts on the same
  keys. The limitation is documented.
- Keys for other commands of the plugin. The binding is a table of
  actions, so they can be added later.
- Recreating a missing pane.
- Making `show` safe against a pane or the diff tab being closed while a
  file is being shown. Today that ends in a Lua error. It affects every
  way of showing a file, is described in `TODO.md`, and gets a change of
  its own; this design does not add to it and does not fix it.
- Binding the keys in a diff tab that was entered without an event.

## Decisions

### 1. The list is a pure function in `tree.lua`

`tree.files(entries, collapsed)` walks `tree.build(entries)` once and
returns the file entries in tree order, each with a flag saying whether
it is visible, that is, not inside a collapsed directory. It draws
nothing and touches no file system. `treeview.first_file` uses it.

The complete order is needed, not only the visible files: the current
file can itself be inside a collapsed directory, and "next" then means
"the first visible file after its place in the order".

`nav` calls `treeview.ensure_buf` before it reads the entries, so that a
deleted tree buffer is rebuilt instead of reading as "no changed files".

Alternative: build the list from `tree.lines`, once with and once without
collapsed directories. Rejected: it lays out and measures every line and
stats every directory, twice per key press.

### 2. The position is the selected file, or the one shown last

The session record gets a field `last_entry`: the path of the last entry
the panes compared. It is written in three places:

- `show_pair`, after both files were opened, next to where a declined
  attempt can no longer be undone, and only when the new `selected` is
  not nil. A declined file therefore never becomes the position, and a
  jump to a file outside the list does not erase it.
- `treeview.refresh`, when it computes a non-nil `selected`.
- For a session saved before the field existed, `show_pair` falls back to
  the selection it replaces. Found during implementation: filling the
  field in `session.get` would also run while a file is being opened,
  when `selected` already names a file that may still be declined.

Navigation is relative to the first of `selected` and `last_entry` that
is among the entries. `selected` can be stale: rebuilding a deleted tree
buffer reads the list again without computing it anew. When neither is
among the entries (never set, or gone after a refresh), there is no
position: next means the first visible file, previous the last.

Both directions are relative to the remembered file, also after the user
wandered off: from the last changed file, next reports the end even
though the panes show something else. Going back to that file is what
`<C-o>` does.

Alternative: use the cursor line of the tree. Rejected: the tree can be
hidden, and its cursor is not where the review is.

### 3. Moving

With the position at index `i` of the complete order, the candidates in a
direction are the visible entries beyond `i`. A count picks the n-th
candidate, or the last one when there are fewer. First and last are the
first and last visible entries. A target that is the file already shown
goes through `show` like any other, as `<CR>` on its tree line does, and
reports nothing.

When there is nothing to show, the reason is one of three messages:

| Situation | Message |
|---|---|
| No candidate in that direction | `no more changed files` |
| The list is empty | `no changed files` |
| The list has files, none visible | `every changed file is in a collapsed directory` |

### 4. One place reports

`nav.run(action, count)` is the one entry point. It finds the target,
shows it and notifies: at level INFO for the three messages above,
because nothing went wrong, and at level ERROR for everything `show`
refuses, as for a selection in the tree. It returns whether a file was
shown. The commands and the keys both call it, so a key press and a
command report the same way. The module table of the plugin gets no new
functions; nothing would use them.

The existing `report()` in `plugin/twintree.lua` always uses ERROR and is
not used for these commands.

### 5. `show` can leave the current window alone

`session.show` gets an option to skip making the after pane current. The
jump to the first change runs through `nvim_win_call` and does not need
the after pane to be current.

Alternative: record the current window in `nav` and restore it after
`show`. Rejected: entering and leaving the after pane fires window events
twice and can resize windows in a narrow terminal.

### 6. Every window that shows the tree follows the selection

`show_pair` puts the cursor on the selected line in every window of the
session's tab that shows the tree buffer, not only in the recorded tree
window. This also holds for a selection with `<CR>`, where it changes
nothing visible: the window `<CR>` was pressed in is already on that
line. A window that shows another buffer is never touched.

### 7. The keys follow the current tab

`lua/twintree/keys.lua` has one idempotent function, `sync()`. The record
it works on is per action (next, previous). It computes the key wanted
for each action, which is the configured one when the current tab has a
session and none otherwise, and then works in three passes over all
actions:

1. An action recorded as bound whose key no longer carries the plugin's
   mapping is marked as given up (decision 9).
2. Every action that is bound to a key other than the wanted one, or is
   bound while no key is wanted, is released.
3. Every action that has a wanted key, is not bound and is not given up,
   is bound.

Releasing everything before binding anything is what makes an exchange of
the two keys safe: no key is read while it still carries the plugin's
mapping for the other action.

It runs on `TabEnter`, in `init.open` right after the session is created
(before the first file is shown, so that the early return cannot skip
it), and at the end of `setup()`. `TabLeave` and `TabClosed` are not
needed: what matters is which tab is current, and `TabEnter` of the next
tab says so, also after a tab was closed.

The bound keys are recorded in one `g:` variable: per action the key, the
saved global mapping or nothing, and whether the key was given up
(decision 9). A `g:` variable survives a reload of the Lua modules, as
the placeholder buffer number does.

Binding reads the global normal-mode mapping from `nvim_get_keymap`,
matched through `vim.keycode(entry.lhs)`, stores it, and sets the
plugin's. A mapping found there that is itself the plugin's, left behind
by a failure, is never stored; the key then counts as unmapped. Releasing
deletes the plugin's mapping and restores the stored entry with
`mapset("n", false, entry)`, or leaves the key unmapped when there was
none.

Only normal mode is written, on binding and on release. A mapping the
user made with `:map` keeps working in visual and operator-pending mode
throughout, and whatever the user changes there during a diff is not
overwritten. The price is cosmetic: after a release `:map` lists such a
mapping as two entries, one for normal mode and one for the other two.

A mapping is the plugin's when it is global and its description is the
one the plugin sets for that action. Its callback passes `vim.v.count1`
on. The callback of the mapping requires
the module when pressed, as the tree buffer's mappings do, so a mapping
set before a reload keeps working and is still recognised afterwards.

The configured keys are not in the record. A reload resets the options to
their defaults, and plugin managers run the user's `setup()` again when
they reload; until that call the default keys apply from the next
`sync()`. This is documented, not worked around.

Alternative: one permanent global mapping that looks for a session when
pressed and otherwise imitates the previous mapping. Rejected: a mapping
can be an expression, a Lua callback, remapped or not; imitating that is
where the errors would be, and restoring it is exact.

Alternative: buffer-local mappings on the buffers shown in the panes, as
other diff plugins do. Rejected: a working tree buffer shown in another
tab would carry the mapping there, and the panes of this plugin can show
any buffer.

Alternative: `maparg()` to read the mapping. Rejected: it returns a
buffer-local mapping of the current buffer first, which would then be
saved as the user's and restored as a global one.

Alternative: restore with `mapset(entry)`, which brings a `:map` mapping
back as one entry. Rejected: it writes visual and operator-pending mode
as well, and would overwrite what the user changed there during the
diff, unless ownership were tracked in three modes.

### 8. A stale mapping releases the keys and does nothing else

When the plugin's mapping fires in a tab without a session, an event was
missed. The callback calls `sync()`, which releases every key because
none is wanted in that tab, and returns. Nothing is shown, nothing is
reported, and the key press is not passed on: the next press of the key
reaches the user's mapping or Neovim's own handling.

Alternative: restore the mapping and feed the key again, so that the
first press already does what the user expects. Rejected: it has to
carry the count and the register, and it needs a guard against feeding
the key into the plugin's own mapping without end when the release
failed. One lost key press after a tab change that fired no events does
not justify that.

The other direction has no repair: in a diff tab entered without an
event, the plugin's mapping is not there to notice. The keys come at the
next `TabEnter`; the commands work at any time. This is specified and
documented.

### 9. A key someone else mapped is given up

When `sync()` finds that the key of a bound action no longer carries the
plugin's mapping in normal mode, the user or another plugin mapped or
unmapped it in the meantime. The action is marked as given up and the
stored mapping is dropped: restoring it would overwrite the newer state.
An action that was given up is neither released nor bound again until an
accepted `setup()` clears the mark.

### 10. Configuration

`config` gets `keys = { next_file = "]<C-f>", prev_file = "[<C-f>" }`. A
value of `false` leaves the action without a key. `setup()` checks the
option before it takes anything from the call:

- it is a table whose only names are `next_file` and `prev_file`;
- each value is a string that is not empty, or `false`;
- no key is used for two actions, compared through `vim.keycode()`, so
  that `]<C-f>` and `]<c-f>` are one key. The check is made on the
  values as they would be in use, the ones of the call merged over the
  defaults: `keys = { next_file = "[<C-f>" }` collides with the default
  for previous.

A call that fails a check is reported in one line at level ERROR and
changes nothing: no option of that call is taken, no mapping is touched,
and the given-up marks stay.

An accepted call takes the options and then, in this order: runs the
first pass of `sync()` so that a key mapped a moment ago is noticed,
releases every bound action, clears the given-up marks, and runs
`sync()`. A key the user had mapped again is thereby read as the user's
mapping when the plugin binds it anew, and comes back on leaving the
tab.

### 11. Layout that is not there

A missing pane is reported by `show` before anything changes. The tree
window is not needed: with the tree hidden nothing follows, with the tree
in a window of the user that window follows (decision 6), and a window
that shows another buffer is left alone. A deleted tree buffer is rebuilt
(decision 1).

What happens when the tab or a pane goes away while a file is being
shown is the behaviour of `show` today and is not changed here (see
Non-Goals).

## Risks / Trade-offs

- [A buffer-local mapping of another plugin on the same key wins in that
  buffer] → Documented; the user picks other keys in `setup()`.
- [The code that shows a file raises a Lua error when a pane or the tab
  is closed while it works, and every key press now goes through it] →
  Not made worse here: the commands are as safe as `<CR>` in the tree.
  Tracked in `TODO.md` for a change of its own.
- [A terminal multiplexer or terminal that eats `<C-f>`] → The commands
  work without keys, and the keys are configurable.
- [`]` and `[` start many mappings, so the key waits for `'timeoutlen'`
  like every other bracket mapping] → Same as `]q`.
- [Events suppressed with `:noautocmd`] → Decision 8: one key press is
  lost in a tab without a session, and the keys are missing in a diff tab
  until the next tab event.
- [After a diff, `:map` lists a mapping the user made for three modes as
  two entries] → Behaviour is unchanged in every mode; decision 7.
- [A reload without `setup()` brings the default keys back] → Documented;
  plugin managers call `setup()` again.
- [The plugin's mapping is recognised by its description; a user who
  copies that description onto their own mapping would have it removed]
  → The description names the plugin and the action; not a realistic
  collision.
- [The mapping functions behave differently on a Neovim version the
  README supports] → Checked by hand on 0.11; a task runs the key specs
  with a 0.11 release as well.
- [From the tree, the before pane's scroll position after the jump to the
  first change cannot be observed headless] → A case in the real terminal
  checks that the change is on screen in both panes.
