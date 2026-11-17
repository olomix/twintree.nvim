# Proposal

## Why

The suite only runs where a developer runs it, on whatever Neovim that
machine has. The README promises Neovim 0.11 or newer, and a spec that
fails on 0.11 went unnoticed until the suite was run there by hand.

## What Changes

- A GitHub Actions workflow runs `make test` for every pull request and
  for every push to `main`, on three Neovim versions: the newest 0.11
  release (the oldest version the README supports), the latest stable
  release, and nightly.
- A failing job for the stable release makes the run fail, and with it
  the badge in the README. The nightly job is informational: Neovim's
  development branch can break for reasons outside this repository, and
  that must not turn `main` red. No rule on GitHub blocks a merge; the
  result is there to be read.
- A weekly run on `main` catches breakage that arrives with a new stable
  release of Neovim while nothing is pushed here.
- The README shows the state of the workflow and says how the suite is
  run in CI.
- The CI item leaves `TODO.md`, and the Neovim 0.11 item no longer asks
  for a run by hand.

No behaviour of the plugin changes, so no spec changes: the change is
marked `skip_specs`.

Not part of this change:

- Fixing the spec that fails on Neovim 0.11 (its own item in `TODO.md`).
  How the 0.11 job is treated until then is decided by its first run, see
  design.md.
- Runs on macOS or Windows.
- Linting or formatting of the Lua sources.
- A release workflow.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None.

## Impact

- `.github/workflows/test.yml` (new).
- `README.md`: a badge and the Development section.
- `TODO.md`.
- `.gitignore`: the directory the workflow checks plenary out into.
- `tests/`: only if a spec turns out to depend on the developer's machine
  and fails on a runner for that reason.
- No change under `lua/` or `plugin/`.
