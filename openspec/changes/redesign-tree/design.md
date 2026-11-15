# Design

## Context

See proposal.md for motivation. Current state:

- `tree.lines(entries, collapsed, selected, dir_status)` is a pure function
  that returns lines with text and byte-range highlights. A file line is
  `indent, status letter, name`, a renamed file appends ` ← old/path`, a
  directory line is `indent, arrow, name/` plus a trailing marker when the
  directory exists on one side only. Lines do not depend on any width.
- `treeview.draw` writes those lines into the tree buffer and applies the
  highlights. It is called when entries change and on folding, and by the
  session whenever the pair of files the panes compare changes, also when
  that happens through navigation in a pane. The session then moves the
  cursor of the tree to the marked line.
- `git.changed_files` runs `git diff --name-status -z -M` (plus
  `git ls-files --others` for the working tree) and returns entries
  `{ status, path, old_path }`, stored in the buffer variable
  `twintree_entries`.
- Since the layout change, one autocommand on `WinResized`, `VimResized`
  and `TabEnter` calls `layout.sync`, and the tree can be hidden, shown again
  and displayed in a window the user made.

Constraints: no required dependencies; the project rule that the tab belongs
to the user; `WinResized` is not delivered in a headless Neovim.

## Goals / Non-Goals

**Goals:**

- The line builder stays pure: all inputs are plain values or injected
  functions, so every layout case is a unit test.
- One place decides what fits on a line.
- Icons are optional and their absence costs nothing.

**Non-Goals:**

- Status glyphs, configurable columns, per-user templates for a line.
- Virtual text for the right-hand block (see decision 2).
- Changing how entries are found, nested, sorted or folded.

## Decisions

### 1. The line builder takes options, a width and an icon source

`tree.lines(entries, opts)` with
`opts = { collapsed, selected, dir_status, width, icon }`:

- `width`: display cells available for a line.
- `icon(name, kind)`: returns `glyph, highlight` or nil. `kind` is `"file"`,
  `"dir_open"` or `"dir_closed"`. nil for a file means no icon; nil for a
  directory means the arrow.

Every existing call site and test moves to the options table.

### 2. The whole line is buffer text, padded to the width

A line is built as one string: left part, padding, right block. The right
block is not virtual text.

Alternative considered: put counts and status in right-aligned virtual text.
It would follow the window edge without a redraw, but the middle cut of the
name needs the width anyway, so a redraw on width change is required in
both designs. One mechanism is simpler, searchable with `/`, and testable
as plain strings.

### 3. Anatomy of a line and what gives way

```
<guides><icon> <name>[ ← <origin>]<pad>[ +A -D] <S>
```

- `guides`: `│ ` per nesting level, highlighted `TwintreeGuide`.
- `icon`: glyph and one space; omitted for a file without icon. A directory
  always has a glyph or an arrow.
- right block: ` +A -D S` with counts, ` S` without. For a directory the
  block is ` S` when it has a marker and empty otherwise.
- `pad`: spaces so that the line is exactly `width` cells when it has a
  right block.

`fit(parts, width)` chooses, first match wins:

| # | Shown | Condition |
|---|---|---|
| 1 | full name, origin, counts | everything fits |
| 2 | full name, counts | fits |
| 3 | name cut to at least `MIN_NAME` cells, counts | fits |
| 4 | name cut to the remaining cells, no counts | otherwise |

`MIN_NAME` is 10 cells, or the full name when it is shorter. In case 4 the
name gets whatever is left after guides, icon and status letter, at least
one cell; when not even that is available the line is the status letter
alone, cut to the width.

This deviates from the order named during exploration ("counts are dropped
before the name is cut"): the reference layout keeps the counts and cuts
the name, and dropping the counts whenever a name is long would hide them
for most nested files at the default width. The counts are still dropped
before the name becomes unreadable.

### 4. Cutting a name in the middle

`cut(name, cells)` keeps `cells - 1` cells of the name around one `…`. The
tail gets half of them, but at least the extension (from the last dot) when
that still leaves one cell for the head. Head and tail are taken character
by character with `vim.fn.strdisplaywidth`, so a wide character is never
split and the result may be one cell short; the padding absorbs that.

All measuring uses display cells; highlight ranges are computed in bytes
from the pieces as they are concatenated. Control characters are escaped
before measuring, as today.

### 5. Rename origin

`origin = old basename` when `dirname(old_path) == dirname(path)`, else
`old_path`. It is shown as ` ← origin` with highlight `TwintreeOrigin`, only
in case 1 of decision 3.

### 6. Line counts come from `--numstat`

`git.changed_files` makes a second call with the same revisions:
`git diff --numstat -z -M <before> [<after>] --`. A pure
`changes.parse_numstat(out)` returns `path -> { added, deleted }`; for a
rename the record is `A\tD\t\0old\0new\0` and is keyed by the new path;
`-\t-` (binary) yields no counts. The counts are joined onto the entries as
`added` and `deleted`.

Untracked files are not in the diff. `git.count_lines(path)` reads the file
and returns its number of lines, or nil when it contains a NUL byte in its
first 8000 bytes (git's own test for binary), is larger than 5 MB, or cannot
be read. An entry that was removed from the index but is still on disk
(reported as modified today) keeps the deleted count from git and gets the
file's line count as added.

Alternative: `git diff --no-index --numstat /dev/null <file>` per untracked
file. Rejected: one process per file.

### 7. Icons

`lua/twintree/icons.lua` exposes `source()`, which returns an
`icon(name, kind)` function or nil:

- nil when `config.options.icons` is false or neither plugin can be
  required.
- `mini.icons`: `MiniIcons.get("file", name)`; `nvim-web-devicons`:
  `get_icon(name, ext, { default = true })`. `mini.icons` is tried first
  when both are present.
- Directories: fixed Nerd Font folder glyphs for open and closed, with
  highlight `TwintreeDirectory`. `nvim-web-devicons` has no folder icons,
  and using fixed glyphs with both plugins keeps the two states distinct.

The provider is looked up at each draw with `pcall(require, ...)`, so
installing or removing a plugin needs no restart, and a provider that
raises is treated as absent.

New option `icons = true` in `config.lua`.

### 8. Width and redraw

`treeview.text_width(state)` is the text width (window width minus
`textoff` from `getwininfo`) of the session's tree window, else of the
first window in the tab that shows the tree buffer, else
`config.options.tree_width`.

`treeview.draw` passes that width and stores it in the buffer variable
`twintree_width`. `treeview.redraw_if_resized(tab)` draws again when the
current text width differs from the stored one. It is called from the
existing size autocommand after `layout.sync`, and after
`layout.reapply` in `toggle_tree` and `reset_layout`.

Draws that the session triggers when the panes follow navigation use the
same width lookup. They cost one icon lookup per line and no git call.

`<CR>` maps the cursor row to a line by building the lines again. The
number and order of lines do not depend on the width, so any width gives
the same row mapping.

### 9. Highlights

New default links: `TwintreeGuide` to `NonText`, `TwintreeOrigin` to
`Comment`. Counts use the existing `TwintreeAdded` and `TwintreeDeleted`;
the status letter keeps its group; an icon uses the highlight its plugin
returns.

### 10. Tests

- `tests/tree_spec.lua`: the layout as strings for a fixed width and a fake
  icon function: columns, each row of the table in decision 3, cutting
  (ASCII, wide characters, extension kept, directory chain), origin rules,
  guides, highlight ranges, widths down to 1.
- `tests/changes_spec.lua`: `parse_numstat` for normal, binary and renamed
  records and odd names.
- `tests/git_spec.lua`: counts for two commits, the working tree, untracked,
  binary and large files.
- `tests/treeview_spec.lua` (new): icon source with a stubbed plugin, with
  none and with icons off; width taken from the window; redraw when the
  width changes, through the function and through the autocommand.
- `tests/resize_spec.lua`: one case in the real terminal: widen the tree by
  key and see the lines follow.
- Existing specs that assert tree lines are updated:
  `tests/session_spec.lua`, `tests/layout_ui_spec.lua` and
  `tests/follow_spec.lua`.

## Risks / Trade-offs

- [Glyph width differs between fonts and terminals] → Widths come from
  `strdisplaywidth`; a terminal that draws a glyph wider than Neovim thinks
  shifts that line by a cell. `icons = false` is the way out.
- [Reading every untracked file on each refresh] → One read per file, a
  5 MB cap, and only for files git does not ignore.
- [A second git call per refresh] → Same cost class as the first; both are
  synchronous, as all git calls are today.
- [The right-hand block is buffer text] → `/` finds `+5` and letters at
  line ends; accepted for the simpler design.
- [Every tree-line assertion in the tests changes] → Mechanical; the pure
  specs carry the precise expectations, the UI specs match on names.
- [The counts of a rename with a path cut in the middle are hard to relate
  to the old file] → The origin is shown whenever there is room.

## Open Questions

- Is 10 cells the right minimum for a cut name? It is one constant and can
  be tuned after use.
