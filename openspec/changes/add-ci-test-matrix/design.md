# Design

## Context

`make test` runs `nvim --headless -u tests/minimal_init.lua` with
`PlenaryBustedDirectory tests/` and exits non-zero when a spec fails.
`tests/minimal_init.lua` takes plenary.nvim from `$PLENARY_DIR`, or from
the data directory of a lazy.nvim installation, and puts it on the
runtime path as given. It points git at an empty global configuration and
sets the author itself, so the specs need no git setup. They do need
`git` and `make`, which GitHub's Ubuntu runners have.

Most specs change the current directory to a repository they create in a
temporary directory, and plenary loads some of its modules only when they
are first used. A relative `$PLENARY_DIR` therefore stops working in the
middle of a run: checked in headless Neovim, a module not yet loaded is
no longer found after the directory changed.

When `$PLENARY_DIR` points at nothing, `PlenaryBustedDirectory` is not a
command, and headless Neovim stays open after the error instead of
exiting.

plenary finds spec files with `find tests/`, runs each in its own
Neovim, and kills one that takes longer than its per-file timeout of 50
seconds; such a file prints no summary line.

`tests/resize_spec.lua` starts a second Neovim in a pseudo-terminal. When
none can be opened, each of its cases prints that it was skipped and then
counts as passed. Locally the file takes about 22 seconds, much of it in
fixed waits. `tests/swap_ui_spec.lua` starts and kills further Neovim
processes.

Checked when this was written:

- `rhysd/action-setup-vim`, latest release v1.6.1, installs Neovim with
  `neovim: true` and a `version` of `stable`, `nightly`, or a tag that
  must match exactly, such as `v0.11.7`. On Linux it unpacks a release
  archive. When the nightly asset is missing it builds from source.
- `actions/checkout`, latest release v7.0.1. Its default `clean` removes
  untracked files of the workspace, and by default it leaves the token in
  the git configuration of what it checked out.
- plenary.nvim publishes no releases; its default branch is `master`.
- The newest 0.11 release of Neovim is v0.11.7; the latest stable release
  is v0.12.6.
- With Neovim 0.11.7 on a developer machine (macOS) the whole suite
  passes except one case of `tests/resize_spec.lua`, "asks about a swap
  file of the first file and opens without it on Abort". Whether it also
  fails on a Linux runner is not known.
- The repository is public, so Actions minutes cost nothing.
- `actionlint` is available for checking the workflow file.

Facts about GitHub Actions that shape the decisions:

- The name of a matrix job, which is also the name of its check on a pull
  request, lists the matrix values unless the job has a `name` of its
  own.
- `continue-on-error` on a job keeps a failure from failing the run. The
  job's own check on a pull request is still shown as failed.
- A concurrency group holds one running and one pending run; a newer run
  replaces the pending one, whatever `cancel-in-progress` says.
- `workflow_dispatch` only starts a workflow whose file is on the default
  branch.
- GitHub disables a scheduled workflow in a public repository after sixty
  days without activity in the repository. The whole workflow is then
  disabled, for every trigger, until it is enabled again by hand.
- GitHub sends a notification for a failed run, not for a failed job of a
  run that succeeded.

See proposal.md for the motivation.

## Goals / Non-Goals

**Goals:**

- CI runs the same command a developer runs, so a red job can be
  reproduced with `make test` and the Neovim build the log names.
- A failure says which Neovim version it happened on.
- The actions and plenary are pinned. The stable and nightly Neovim and
  the runner image move on purpose: following them is what the jobs are
  for.

**Non-Goals:**

- Hiding a failing spec. A spec is fixed, or its job is marked as
  informational with the reason next to it; a spec is not skipped per
  version.
- A rule on GitHub that blocks merging on a red check. One person merges
  here; the run and the badge are the signal.
- Retrying failed runs.
- Caching. The Neovim download and the plenary checkout take seconds.
- Being told about a broken nightly. See decision 4.

## Decisions

### 1. One workflow, one job, a matrix over Neovim versions

`.github/workflows/test.yml` has one job on `ubuntu-latest` with three
matrix entries. Each entry has a `role`, the `version` to install, and an
`experimental` flag:

| role | version | experimental |
|---|---|---|
| `oldest` | the newest 0.11 release, as an exact tag | see decision 4 |
| `stable` | `stable` | no |
| `nightly` | `nightly` | yes |

The job's `name` is `nvim ${{ matrix.role }}`. The check on a pull
request is then `nvim oldest`, `nvim stable` or `nvim nightly`, and keeps
that name when the 0.11 tag is bumped or the flag of an entry changes.

`fail-fast` is off, so one failing version does not cancel the others.

Alternative: one job per version. Rejected: three copies of the same
steps.

Alternative: a matrix over operating systems as well. Rejected for now:
it triples the runs, and nothing in the plugin is specific to a platform
beyond what git and Neovim hide. macOS is where the suite runs during
development anyway.

### 2. The steps

In this order:

1. `actions/checkout` for the repository, with `persist-credentials:
   false`.
2. `actions/checkout` for `nvim-lua/plenary.nvim` at a fixed commit, into
   `.deps/plenary.nvim` inside the workspace, with `persist-credentials:
   false`. After step 1, which would otherwise remove it.
3. `rhysd/action-setup-vim` with `neovim: true` and the version of the
   matrix entry.
4. `nvim --version`, so the log names the exact build, which matters for
   stable and nightly.
5. A check that `$PLENARY_DIR/plugin/plenary.vim` exists, so that a wrong
   path fails at once instead of leaving Neovim open until the job's
   timeout.
6. `make test`.

`PLENARY_DIR` is set for the job to `${{ github.workspace
}}/.deps/plenary.nvim`: an absolute path, because the specs change
directory.

The checkout inside the workspace does not reach the tests: plenary only
searches `tests/`, and no spec runs git in the workspace. `.deps/` goes
into `.gitignore`, for a developer who uses the same layout to reproduce
a job.

Alternative: install Neovim by downloading a release archive in a shell
step. Rejected: the action already handles the asset names, which differ
between releases, and the fallback for nightly.

Alternative: change the Makefile so that it fetches plenary itself.
Rejected: a developer already has plenary through a plugin manager, and
`$PLENARY_DIR` is the documented way to point at another copy.

### 3. Pinning

Both actions are referenced by the full commit hash of their latest
release, with the version as a comment, and plenary by a commit hash of
its default branch. A tag can be moved; a hash cannot. The hashes are
looked up from GitHub when the workflow is written, not copied from this
document.

The `oldest` entry names a patch release because the action needs an
exact tag. When a newer 0.11 release appears the entry is changed by
hand.

### 4. Which jobs fail the run

The job sets `continue-on-error` from the `experimental` flag of its
entry. A job that is not experimental fails the run when it fails; that
is all "has to pass" means here. Nothing on GitHub is configured to block
a merge.

- `nvim stable` is never experimental.
- `nvim nightly` is always experimental. Its check on a pull request can
  be red while the run is green; the README says that this is expected.
  A broken nightly on the weekly run produces no notification, because
  the run succeeds. That is accepted: the maintainer works on nightly and
  meets such a break first.
- `nvim oldest` is decided by what its job does on the runner, read from
  the log after the fixes of decision 7 are in:

| What the log of `nvim oldest` shows | Entry |
|---|---|
| Every spec file printed its summary, none reports a failure or an error, and the known case ran, that is, it did not print that it was skipped | Not experimental |
| The same, but the known case was skipped for lack of a pseudo-terminal | Not experimental; the `TODO.md` item keeps asking for a run by hand, because CI does not exercise the case |
| The only failure is the known case of `tests/resize_spec.lua` | Experimental, with a comment naming the `TODO.md` item |
| The known case passes in one run and fails in another | Experimental, as above; an unsteady case is not a required one |
| Any other failure, or a spec file without a summary, that decision 7 does not resolve | Stop and report; the workflow is not merged in that state |

While the entry is experimental, no failure on 0.11 fails the run, so the
README's "0.11 or newer" is not enforced by CI. To keep that from hiding
something new, the log of `nvim oldest` is read in every run made before
the merge, and its failures are compared with the one that is known. The
flag is removed by the change that settles the `TODO.md` item.

When the known case fails on `nvim stable` as well, it is not a matter of
0.11: stop and report. This change does not alter the plugin.

Alternative: skip the known case when the version is 0.11. Rejected: it
would also hide a real difference in the plugin's behaviour on 0.11,
which is exactly what that TODO item is there to find out.

Alternative: make nightly fail the run. Rejected: Neovim's development
branch would decide whether `main` is green.

### 5. Triggers and housekeeping

- `pull_request`, `push` to `main`, `workflow_dispatch`, and a weekly
  `schedule`.
- `permissions: contents: read`; the workflow writes nothing.
- Concurrency: runs for a pull request share a group per ref and cancel
  the run a newer push supersedes. Every run on `main` gets a group of
  its own, built from the run id, so that none is replaced while it
  waits.
- `timeout-minutes: 15` on the job. The suite takes about two minutes;
  the limit is for a spec that waits for input. On nightly the limit can
  also be reached by the installation, when the action has to build
  Neovim from source.

### 6. Specs that need a terminal

Nothing is configured for them. The first run shows, for each Neovim
version, whether a runner can open a pseudo-terminal. A green summary of
`tests/resize_spec.lua` does not answer that, because a skipped case
counts as passed: the answer is whether the log has skip lines for that
file. The outcome is written into the README's Development section, so
that nobody assumes those cases are covered by CI when they are not.

### 7. A spec that fails on a runner only

When a spec passes locally and fails on a runner, the cause is found
first. A spec that depends on the developer's machine (a wait too short
for a slower machine, an assumption about the terminal, a path) is
corrected in `tests/`. A spec file whose output stops without a summary
was killed by plenary's per-file timeout; `tests/resize_spec.lua`, with
its fixed waits, is the first candidate. The plugin is not changed in
this change; a real difference in behaviour becomes an item in `TODO.md`.

## Risks / Trade-offs

- [Specs with waits of a few seconds are flaky on a slow runner] →
  Decision 7; the workflow is run several times before it is merged.
- [Nightly is broken and nobody is told] → Accepted, decision 4. It is
  visible in the run and on every pull request.
- [The pinned hashes go stale] → They are three lines with the version in
  a comment; updating them is a routine change.
- [The `oldest` entry stays experimental and forgotten] → The comment in
  the workflow and the `TODO.md` item point at each other.
- [GitHub disables the workflow after sixty days without activity] → It
  then runs for no trigger at all until it is enabled again with `gh
  workflow enable test.yml` or in the Actions tab. The README's
  Development section says so.
- [Parts of the plan can only be checked after the merge: the run for a
  push to `main`, a manual run, the badge] → A task after the merge.

## Open Questions

- Whether the known 0.11 failure reproduces on Linux, and whether a
  runner can open a pseudo-terminal. Both are answered by the first run;
  decisions 4 and 6 say what follows from each answer.
