# Notes

## Check with a real icon plugin

A headless run with `nvim-web-devicons` installed, in a throwaway repository
with a nested directory, a long file name and untracked files, drew every
line of the tree exactly as wide as the tree window (35 cells), with file
icons, a folder glyph, counts and the status letter in the last column.

## Check by hand (task 6.3)

Done by the maintainer in a real terminal with an icon plugin and a Nerd
Font, after reloading the plugin: icons and folder glyphs, the colours of
counts and status letters, the column at the right edge, cut names, the
rename origin, indent guides and resizing the tree. Everything worked.

## Found while implementing

- The right-hand block ` +1 -1 M` is eight cells, so at the default width a
  top-level name has 27 cells before it is cut.
- A highlight group name returned by an icon plugin is passed to Neovim as
  it is. A name with characters Neovim does not accept in a group name
  makes drawing fail; real plugins return valid names.
