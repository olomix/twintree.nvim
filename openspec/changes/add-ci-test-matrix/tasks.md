# Tasks

## 1. The workflow

- [x] 1.1 Look up, from GitHub, the latest release of `actions/checkout` and of `rhysd/action-setup-vim` with the commit hash each tag points at, the head commit of plenary.nvim's default branch, and the newest 0.11 release of Neovim; verify by noting the four values and where each came from in the pull request
- [x] 1.2 Write `.github/workflows/test.yml` as in design decisions 1 to 5: one job on `ubuntu-latest` named `nvim ${{ matrix.role }}`, the three matrix entries with `role`, `version` and `experimental`, `fail-fast` off, `continue-on-error` from the flag, the six steps in their order with both checkouts using `persist-credentials: false`, both actions and plenary pinned by hash with the version in a comment, `PLENARY_DIR` as an absolute path under the workspace, read-only permissions, the concurrency group that is per ref for pull requests and per run on `main`, the job timeout, and the four triggers; verify that `actionlint` reports nothing for the file
- [x] 1.3 Add `.deps/` to `.gitignore`; verify with `git check-ignore .deps/plenary.nvim`
- [x] 1.4 Check the step that guards the plenary path locally: run the same test with `PLENARY_DIR` pointing at a directory without plenary; verify that it exits non-zero at once
- [x] 1.5 Check that no tracked file gained a path, user name or host name of a developer machine; verify by reading the staged diff

## 2. Runs before the merge

- [x] 2.1 Push the workflow on a branch and open a pull request so that it runs; verify with `gh run view` that the three jobs `nvim oldest`, `nvim stable` and `nvim nightly` started and that each log names its Neovim build
- [x] 2.2 Read the log of each job. For each one verify that every spec file printed its summary line, and list every failure and error. Find the cause of each failing spec and correct the spec when it depends on the developer's machine (design decision 7), without changing anything under `lua/` or `plugin/`; when the known 0.11 case fails on `nvim stable` too, stop and report
- [x] 2.3 For each of the three jobs, find out whether the cases of `tests/resize_spec.lua` ran or were skipped: verify by the skip lines in the log, or their absence, not by the summary of the file, and quote the result per Neovim version in the pull request
- [x] 2.4 With the fixes of 2.2 in, decide the `oldest` entry from its log by the table of design decision 4; verify that the entry and its comment match the row that applies, and stop and report for the last row
- [ ] 2.5 Run the whole workflow at least three times in total with `gh run rerun` on the pull request's run, waiting for each to finish. For every run verify that `nvim stable` passed, and read the failures of `nvim oldest` whatever its flag: they are none, or exactly the known case. A case that passes in one run and fails in another is handled by decisions 4 and 7 before going on

## 3. Documentation

- [x] 3.1 Add the workflow's status badge to `README.md`, and say in its Development section: that CI runs `make test` on the oldest supported, the stable and the nightly Neovim; which of the three fail the run, and that a red `nvim nightly` check on a pull request is expected at times and blocks nothing; whether the specs that need a terminal run there, per the result of 2.3; how to reproduce a red job locally with `PLENARY_DIR`; and that GitHub disables the whole workflow after sixty days without activity and how to enable it again. Verify that the badge URL names this repository's workflow file and that the section matches the workflow
- [x] 3.2 Remove the CI item from `TODO.md` and change the Neovim 0.11 item to what 2.4 found: that the `nvim oldest` job covers it, or that the job is informational until the item is settled, or that CI skips the case and a run by hand is still needed. When a spec difference found in group 2 was left unfixed, add it as an item. Verify by reading the file

## 4. Checks

- [ ] 4.1 Run `make test` locally with the stable or the nightly Neovim, `actionlint`, and `openspec validate add-ci-test-matrix --strict`; verify all three pass and that the last run of the workflow on the branch is green
- [ ] 4.2 After the pull request is merged: verify that the run for the push to `main` is green, that `gh workflow run test.yml` starts a run, and that the badge in the README shows the state of `main`. This task stays open until the merge
