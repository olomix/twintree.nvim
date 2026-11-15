# Notes

## Found while implementing

- Putting buffers into the panes with `:buffer` needed no change for the
  alternate file or the jump list: the pane-following specs pass as they
  were.
- A declined swap file makes Neovim return the window to its old buffer and
  fire the usual events. The plugin took that for a jump by the user and
  moved the other pane. `follow` now does nothing while a pair is being
  shown.
- A jump fires its events more than once; without a record of the declined
  file the prompt came up once per event.
- After `E325` with nobody to ask, Neovim still leaves the buffer in the
  window, read-only. The undo puts that pane back as well.
- `OptionSet` aside, `SwapExists` does fire in the headless specs, so the
  outcomes are tested there with the prompt function replaced; the real
  prompt and key presses are covered in the pseudo-terminal spec.
- After an answer, Neovim can leave a "Press ENTER" prompt on the screen,
  because the prompt text and the message that follows take several lines.

## What was verified automatically

`tests/resize_spec.lua`, in a real terminal with a swap file left by a
killed Neovim: the prompt appears with the ATTENTION text, Open Read-Only
opens the file read-only in diff mode, Abort leaves the panes as they were
with a one-line message, and after a jump made with `:edit` in the before
pane Edit anyway shows the counterpart. No traceback in any of them.

## Check by hand (task 6.3)

Done by the maintainer for a file that is open in a second running Neovim:
the file opens with Neovim's warning and no question.

The case of a swap file left by a crash was not checked by hand. The
maintainer accepted it on the strength of the pseudo-terminal spec above,
which drives a real Neovim with a real prompt and key presses.
