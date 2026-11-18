# Design

## Context

The tree buffer is created in `treeview.create_buf()`. It sets the
filetype `twintree` and then two buffer-local keys, `<CR>`
(`treeview.activate()`) and `R`; in that order a key the user maps in a
`FileType` autocommand is replaced by the plugin's. `activate()` reads
the line of the cursor of the current window from `lines_of(state)`: a
line is a directory (`type = "dir"`, `path`), a file (`type = "file"`,
`entry`) or the message "No changes". A directory line can stand for a
chain of nested directories; its `path` is the innermost one.

The session of a tab keeps the roots of both sides, `pair` (the absolute
paths of the files the panes show, one of them missing for an added or
deleted file) and `selected` (the path of the tree entry the pair is the
comparison of). `selected` is nil while the panes show a file the tree
does not list, such as an unchanged file reached by navigation.
`session.side_of()` gives the side and the relative path of a file, or
nil for a file outside both roots; `session.entry_pair()` gives the
files of an entry that exist, with the old path on the before side.
The tree shows control characters of a name escaped.

Commands are defined in `plugin/twintree.lua` and call functions of
`lua/twintree/init.lua` that return a value or `nil, err`; the command
reports the error. Autocommand callbacks require their module when they
run. `session.NO_SESSION` is the message for a tab without a diff.

Checked on Neovim 0.11 and nightly, the clipboard also on 0.12:

- The menu of the right mouse button is the global menu `PopUp`. Neovim
  fills it at startup and enables its own items in a `MenuPopup`
  autocommand. `:popup PopUp` shows the menu without that event.
- A submenu is shown as one line; choosing it closes the menu and runs
  nothing. A disabled item is not shown; a disabled separator is, as an
  empty line.
- In `nnoremenu 500.10 PopUp.Name`, 500 is the priority of the menu and
  10 that of the item. Items with a low priority are shown above the
  built-in ones.
- With `'mousemodel'` `popup_setpos` a right click moves the cursor, and
  the focus, to the clicked line before `MenuPopup`, unless the click is
  inside a visual selection. With `popup` nothing moves.
- A buffer-local `<2-LeftMouse>` mapping also fires for a double click on
  the status line, the separator, the tab line and the command line
  while that buffer is current; `getmousepos()` then gives line 0 or
  another window.
- Without a clipboard provider `setreg("+", …)` raises nothing and the
  text is lost; `has("clipboard")` is 0. A copy tool that exits with an
  error raises nothing either. `g:clipboard` accepts Lua functions.

See proposal.md for the motivation.

## Goals / Non-Goals

**Goals:**

- The mouse opens and folds, without taking the cursor movement and the
  selection away.
- One code path for copying: the menu items run the command.
- The menu of the user is unchanged outside the tree.
- No spec writes the clipboard of the machine it runs on.

**Non-Goals:**

- A default key for the command, other menu items, a submenu.
- Word selection by double click in the tree; the double click is taken.
  A triple click still selects the line.
- The menu items in visual mode.
- Any change to `'mouse'` or `'mousemodel'`.

## Decisions

### 1. `<2-LeftMouse>` runs `activate()` when the click is on the text

`create_buf()` maps `<2-LeftMouse>` in normal mode, buffer-local, as an
expression mapping without remapping. When `getmousepos()` names the
current window and a line above 0, it gives the command that runs
`treeview.activate()`; otherwise it gives `<2-LeftMouse>` itself, which
is Neovim's own handling. The first click of the pair is not mapped, so
Neovim has already moved the cursor, and focused the tree window, when
the mapping runs. `<LeftMouse>`, `<LeftDrag>`, `<LeftRelease>`,
`<3-LeftMouse>` and `<4-LeftMouse>` stay unmapped.

`activate()` acts only when the current buffer is the tree of the
current tab. In a tree buffer the user opened in another tab, the lines
are those of another diff, or the tab has no diff at all; there `<CR>`
and the double click report that the diff of the tree is in another tab.
Until now `<CR>` did nothing in a tab without a diff, and acted on the
wrong diff in another diff tab.

Alternative: act on a single click that did not drag. Rejected by the
owner: a click that only gives the tree the focus would open a file.

Alternative: ignore the third click. Rejected by the owner: a triple
click selects the line as in any buffer.

### 2. Keys before the filetype

`create_buf()` sets its keys first and the filetype last. A `FileType`
autocommand of the user then runs after the plugin's keys exist, and its
buffer-local mapping for the same key replaces the plugin's. This also
changes `<CR>` and `R`, for which the plugin's key won until now.

### 3. One module for what is copied

A new module, `lua/twintree/path.lua`, without effects on windows.

The target is a relative path (or none) and an absolute path:

- The current buffer is a tree buffer: the session is the one of the tab
  whose `tree_buf` it is, found by looking through the tab pages, so
  that it also works in a window of another tab. The line of the cursor
  of the current window gives the target. A file line: the relative path
  is `entry.path`; the absolute path is the after file of
  `session.entry_pair()`, else `before.root` joined with the old path or
  the path. A directory line: its `path`; the absolute path is under
  `after.root` when a directory is there, else under `before.root`. Any
  other line: no target.
- Otherwise the session is the one of the current tab, and the target is
  the file of `state.pair`: its after file, else its before file, as the
  absolute path. The relative path is `state.selected` when set, else
  what `session.side_of()` gives, else none (a file outside both roots).
  No pair: no target.

The form: `relative` is the relative path, an error when there is none;
`absolute` is the absolute path; `name` is the last component of the
relative path, or of the absolute path when there is none. Roots are
resolved paths, so the absolute path is one too.

`treeview` gets a function that returns the line of the cursor for a
state, and `activate()` uses it as well, so that `<CR>`, the double
click, the command and the menu read a line in one way.

`init.lua` gets `copy_path(form)`: it validates the form (default
`relative`), asks for the target and the text, refuses when
`vim.fn.has("clipboard") == 0`, writes characterwise with
`pcall(vim.fn.setreg, "+", text, "c")` and returns the text, or
`nil, err`. Without the type, a name that ends in a line break would be
taken as a whole line and get one more.
The command has `nargs = "?"` and no range or bang; Neovim hands two
words over as one argument, which is then an unknown form. Its
completion filters the three forms by the typed prefix. It reports `twintree: copied <text>`, with control
characters escaped as in the tree, or the error.

Messages: `session.NO_SESSION` without a session; "no file to copy the
path of"; "the file is not in the repository, it has no relative path";
"unknown form '<x>': use relative, absolute or name"; "no clipboard
provider, see :help clipboard"; "could not write the clipboard:
<reason>".

A copy tool that fails after it was started cannot be noticed: Neovim
prints its own message and raises nothing. With `g:clipboard` set to
false, `+` is a plain register. The help file says both.

Alternative: use `state.selected` outside the tree. Rejected: it is nil
while the panes show a file the tree does not list.

Alternative: three commands. Rejected by the owner.

### 4. The menu items exist only while they apply

A module function, called from autocommands in `plugin/twintree.lua`,
keeps the four entries in step:

    nnoremenu 500.10 PopUp.Copy\ relative\ path <Cmd>TwintreeCopyPath relative<CR>
    nnoremenu 500.11 PopUp.Copy\ absolute\ path <Cmd>TwintreeCopyPath absolute<CR>
    nnoremenu 500.12 PopUp.Copy\ file\ name     <Cmd>TwintreeCopyPath name<CR>
    nnoremenu 500.13 PopUp.-twintree-           <Nop>

- Removing: for each of the four names, when `menu_get()` (in `pcall`,
  it raises when `PopUp` does not exist) shows a normal-mode item that
  runs `TwintreeCopyPath`, or the separator of that name, `nunmenu` it.
  An item of the user with the same name runs something else and is
  left alone.
- Adding, after removing: only on `MenuPopup` in normal mode, when
  `getmousepos()` names the current window, the current buffer is a tree
  buffer with a session, the mouse is on a line (not on the separator of
  the window), and the line of the cursor is a file or a directory. A name the user already uses is not defined again.
- Removing alone: on `BufLeave` of a tree buffer, so that a menu opened
  by `:popup` elsewhere, or after the tab was closed, has no items; and
  when the plugin file is sourced.

With `popup_setpos` the cursor is on the clicked line when the event
fires, so the items act on it. With `popup` the items appear only when
the click is in the tree window that is current, and act on the line of
the cursor, which is what that option means.

An unexpected error in the function is reported with `vim.notify`, not
raised: a right click must not end in a traceback.

Alternative: define the items once and enable or disable them, as Neovim
does for its own. Rejected: a disabled separator leaves an empty line at
the top of every menu.

Alternative: items for visual mode as well. Rejected by the owner: a
right click in a selection keeps Neovim's menu for a selection.

### 5. Specs

`tests/minimal_init.lua` sets `g:clipboard` to Lua functions that keep
the text in a global variable. Every spec, and every child Neovim that
loads that file, then writes there and never the system clipboard, and
the real code path runs, the provider check included. Only the write
that raises is stubbed.

Headless specs trigger the mouse mapping with the key `<2-LeftMouse>`
after placing the cursor and stub `getmousepos()`, which holds a stale
position without a screen. The menu is checked by firing `MenuPopup` and
reading `menu_get("PopUp")` in `pcall`.

Specs on a pseudo terminal, built like the resize specs, send real mouse
input as SGR sequences with `chansend`: the same cell twice for a double
click. While a menu is open the child answers no request, so the menu is
driven with input only (`<Down><CR>` chooses the first item) and the
clipboard is read afterwards through the global variable.

### 6. Documentation

`doc/twintree.txt` and `README.md`: the double click in the list of tree
keys; that a key mapped for the `twintree` filetype replaces the
plugin's; the command with its three forms and what it acts on; the
three menu items, that they need `'mousemodel'` `popup` or
`popup_setpos` and normal mode; the two clipboard limits of decision 3.

## Risks / Trade-offs

- [The double click no longer selects a word in the tree] → Accepted by
  the owner; a drag and a triple click still select.
- [After a double click that folds a directory, a quick third click
  starts a line selection] → Accepted by the owner.
- [A user relied on the plugin's `<CR>` winning over their own filetype
  mapping] → Unlikely to be wanted; the help file states the new order.
- [A user rebuilt the menu with item priorities below 10] → Their items
  are above the plugin's. Harmless.
- [The menu API is old Vimscript and differs between UIs] → Only the
  terminal UI is checked; a GUI that draws its own menu gets the same
  items through the same commands.
- [The message says "copied" although the copy tool failed] → Cannot be
  detected; documented.

## Open Questions

None.
