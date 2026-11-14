# Notes

## End-to-end check with gopls (task 7.2)

Run headless against a full lazy.nvim-based Neovim config (Neovim
0.13.0-dev-2052, gopls) in a throwaway Go module with two commits, opened with `Twintree HEAD~1`. The steps were scripted, not done by
hand in a UI, so the look of the diff highlighting was not inspected.

Observed:

- The session used the first tab: 1 tab, 3 windows.
- The tree listed `M main.go` and `M util.go`; selecting `main.go` put both
  panes in diff mode.
- Two gopls clients were running: one rooted at the cached worktree (before
  pane), one at the checkout (after pane).
- `textDocument/definition` on `helper()` jumped to `util.go` inside the
  worktree from the before pane and to `util.go` of the checkout from the
  after pane.
- After each jump diff mode was off in that pane; returning to the selected
  buffer switched it on again.
- Worktree buffers were `readonly` and `nomodifiable`; checkout buffers were
  modifiable.
- `:TwintreeClean` removed the worktree.

Finding: lazy.nvim resets the runtimepath, so `nvim --cmd "set rtp+=..."` does
not load the plugin with that config. Without a lazy.nvim spec for the
plugin, use
`nvim -c "set rtp+=<plugin dir>" -c "runtime plugin/twintree.lua" -c "Twintree"`.
