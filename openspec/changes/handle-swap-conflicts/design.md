# Design

## Context

See proposal.md for motivation. Current state:

- `session.show_pair` records the new pair in the session state, then puts
  each buffer into its pane: with `keepalt buffer N` inside `nvim_win_call`
  for the pane whose alternate file must be kept, with `nvim_win_set_buf`
  otherwise. It is called by `session.show` (selection in the tree), by
  `session.follow` and `move_to_own_pane` (navigation in a pane) and by
  `reset_layout`.
- The state is saved before the windows change on purpose: the events fired
  while a buffer enters a pane find the pair recorded and do not follow it
  again.
- Files of cached worktrees have `swapfile` off. Files of the checkout are
  ordinary editable buffers with swap files.

Measured in real terminals with two Neovim instances:

| How the file is put into the pane | Owner running | Leftover swap file |
|---|---|---|
| `nvim_win_set_buf` (today) | ATTENTION text, `E325`, traceback | same |
| `:buffer`, no handler of ours | opens, `W325` warning | `E325` as a catchable error |
| `:buffer`, `SwapExists` handler with `confirm()` | opens, `W325` warning | prompt shown, answer applied |

On the API path Neovim does not run `SwapExists` at all. On the command
path it does, and Neovim's default handler chooses "edit" for a swap file
owned by a running Neovim. Neovim's own dialog is not available either way:
called from plugin code the ATTENTION message becomes an error.

## Goals / Non-Goals

**Goals:**

- No traceback and no inconsistent session, whatever the answer.
- Behave like Neovim does for a file opened by hand: same default for a
  running owner, same information and choices otherwise.
- Keep the question out of the way of everything the plugin does not open.

**Non-Goals:**

- Reproducing Neovim's dialog byte for byte.
- Swap handling for files the user opens.
- A configuration option for a default answer.

## Decisions

### 1. Buffers enter a pane through `:buffer`

`swap.open(win, buf, keepalt)` in a new `lua/twintree/swap.lua` runs
`buffer N` or `keepalt buffer N` inside `nvim_win_call`, under `pcall`, and
returns `true`, or `false` and a reason. It replaces both branches in
`show_pair`. The file counts as opened when the command did not raise and
afterwards the window shows the buffer and the buffer is loaded; Quit makes
Neovim leave the buffer unloaded without raising.

Alternative: `vim.fn.bufload` before `nvim_win_set_buf`. It loads without
any question, which is "Edit anyway" for every swap file, including one
with unsaved work in it. Rejected: the user asked to be asked.

### 2. A `SwapExists` handler that acts only for the plugin

`plugin/twintree.lua` registers one `SwapExists` autocommand that calls
`swap.on_swap_exists()`. It returns at once unless both hold:

- the plugin is opening a file: a module-local flag that `swap.open` sets
  around its command and clears in every case;
- `v:swapchoice` is still empty, meaning no earlier handler decided.

Autocommands run in the order they were defined. Neovim's default handler
is defined at startup, before any plugin file, so it runs first; for a
running owner it sets "edit" and prints `W325`, and the plugin stays
silent. The order still holds after `:Lazy reload`, which defines the
plugin's autocommand again, later.

### 3. The prompt

`swap.describe(swapname, info, path, file_mtime)` is pure: from the name of
the swap file and the table that `swapinfo()` returns it builds the text,
in the layout of Neovim's message:

```
E325: ATTENTION
Found a swap file by the name "<swap file>"
          owned by: <user>   dated: <date>
         file name: <file name>
          modified: <YES or no>
         user name: <user>   host name: <host>
        process ID: <pid> (STILL RUNNING)
While opening file "<path>"
             dated: <date>
```

`(STILL RUNNING)` is shown when the process exists. `swapinfo()` reports no
process id once the process is gone, so the line then reads
`process ID: no longer running`. `swap.choices(running)`
returns the labels and the letters Neovim expects in `v:swapchoice`:

| Label | Letter |
|---|---|
| Open Read-Only | `o` |
| Edit anyway | `e` |
| Recover | `r` |
| Delete it | `d` (left out while the process is running, as Neovim does) |
| Quit | `q` |
| Abort | `a` |

`swap.ask(text, labels)` shows them with `vim.fn.confirm` and returns the
index; dismissing the prompt returns 0, which is treated as Abort. `ask` is
a field of the module so that tests can replace it.

A `swapinfo()` result with an `error` field (an unreadable swap file) gives
a shorter text with the swap file name and the error.

### 4. No user interface

When `nvim_list_uis()` is empty the handler does not ask and leaves
`v:swapchoice` empty. Neovim then raises `E325`, `swap.open` reports the
file as not opened, and the rest follows decision 5. Nothing waits for
input.

### 5. Undoing a failed attempt

`show_pair` keeps what it needs to undo: the previous `pair`, `selected`
and `bufs`, and the list of panes whose buffer it changed. When
`swap.open` fails for a pane:

1. Every pane in that list gets its previous buffer back with
   `nvim_win_set_buf`; those buffers are loaded, so no swap file is
   consulted. A pane that had no previous buffer gets the placeholder.
2. The previous `pair`, `selected` and `bufs` are stored again.
3. Diff mode is set for each pane that shows its recorded buffer and
   switched off for any other. A pane the user navigated is not in the
   list; it keeps the user's file and becomes a plain window, the same
   state the panes already have for buffers that are not files.
4. The tree is drawn again and `show_pair` returns `false` with
   `"<file name> was not opened: <reason>"`.

The state is still saved before the windows change, as today, so the events
fired during the attempt do not follow again. The undo is what makes the
recorded pair true again.

Two things the implementation showed:

- A failed attempt can leave the buffer in the window anyway (Neovim shows
  it read-only after raising `E325`), so the pane whose opening failed is
  in the list of panes to put back as well.
- When a swap file is declined, Neovim puts the window back to its old
  buffer and fires the events for that. `follow` would take it for a jump
  by the user and move the other pane in the middle of the attempt. A
  module-local flag is set while `show_pair` runs, and `follow` does
  nothing while it is set.

A jump fires its events more than once, and each would ask again. The
session therefore records, per pane, the buffer whose counterpart was
declined (`declined`); `follow` leaves that buffer alone until the pane
shows another one. Going back to the file later asks again, and so does
selecting it in the tree.

Abort and Quit give the same result for a jump: the pane keeps the file the
user went to. Neovim's Abort interrupts the command that was opening the
counterpart, not the user's own command, which had already completed.

Callers: `session.show` already returns the error to the tree's key
handler, which reports it. `session.follow` and `move_to_own_pane` report
it themselves with `vim.notify`. `reset_layout` reports it as well and
completes with the layout rebuilt and the panes empty or showing what could
be opened.

Alternative: load both files first in a hidden window and only then touch
the panes. Rejected: it needs a throwaway window in the user's tab, and
events fired there would have to be kept from following.

### 6. One reason text

The reason is derived from what happened: `"the swap file question was
declined"` for Quit, Abort and a dismissed prompt; the first line of
Neovim's error otherwise. Messages are one line; the ATTENTION block is
never passed through.

### 7. Tests

- `tests/swap_spec.lua`, pure: `describe` for a running and a dead owner, a
  modified file and an unreadable swap file; `choices` with and without
  Delete it; the mapping from the answer to the letter, including 0.
- `tests/swap_ui_spec.lua`, headless with `swapfile` on and a private swap
  directory:
  - a leftover swap file is made by a second headless Neovim that edits the
    file and is killed;
  - a running owner is a second headless Neovim kept alive;
  - `swap.ask` is replaced by a function that returns a fixed answer and
    records its arguments, and `nvim_list_uis` is stubbed where a prompt is
    expected, since the specs run without a user interface.
  Cases: each of the six answers after a selection; a running owner (no
  question, editable, warning); an earlier handler that decided; a file the
  user opens with `:edit` (the plugin's prompt function is not called); a
  worktree file; the undo for a selection, for the second pane, for a jump
  and for returning after a declined jump; selecting again; no user
  interface; `reset_layout` with a declined file.
- `tests/resize_spec.lua`, in a real terminal: a leftover swap file, a
  selection in the tree, the prompt text on the screen, a key as the answer
  and the result; and the same after a jump made with `:edit`, to cover the
  prompt from the following path.

## Risks / Trade-offs

- [`:buffer` differs from `nvim_win_set_buf` in small ways, such as the
  alternate file and the jump list] → The pane-following specs pin these;
  they run unchanged and decide whether `keepalt` or `keepjumps` is needed.
- [The user's configuration removed Neovim's default handler] → Then the
  plugin asks for a running owner too, with Delete it left out. Correct,
  only more questions.
- [A handler defined after the plugin's could change the choice] → It runs
  later and wins, as it would for any file. Nothing to do.
- [`confirm()` from a scheduled callback or a nested autocommand, the paths
  navigation takes] → Covered by the real-terminal test for a jump.
- [Recover leaves a modified buffer in a diff] → That is what the user
  asked for; the diff shows the recovered text.
- [The prompt is not Neovim's text word for word] → Same facts, same
  choices; the explanatory paragraphs of the original are left out.

## Open Questions

None.
