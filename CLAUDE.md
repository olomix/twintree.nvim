# twintree.nvim

Neovim diff viewer where both sides of the diff are browsable code. Lua
sources are in `lua/twintree/`, commands and autocommands in
`plugin/twintree.lua`, behaviour specs in `openspec/specs/`.

Run the tests with `make test`.

## No personal information in the repository

This is a public repository. Never write personal or machine-specific
information into any tracked file or commit message. That covers code,
comments, tests, docs, README, `TODO.md`, and everything under `openspec/`
(proposals, designs, tasks, notes, specs).

Do not include:

* Absolute paths or paths under a home directory that name a real user,
  machine or private setup (home directories, personal config or data
  directories, `NVIM_APPNAME` values, temp or scratch directories).
* Names of private repositories, companies, internal hosts, projects or
  branches, even as examples.
* Names, usernames, email addresses, hostnames, process IDs or other details
  of the person or machine the work was done on.
* Verbatim terminal output or error messages that contain any of the above.

Write generically instead: `<plugin dir>`, `stdpath("cache")`,
`~/.config/nvim`, "a Go repository", "the Neovim configuration". When a note
records how something was verified, describe the setup in general terms
(Neovim version, tool names), not the environment it ran in.

Changes to a personal Neovim configuration or to any other repository are not
part of this project; do not record them here.

Before committing, check the staged diff for such details. If some are
already in unpushed commits, rewrite those commits before pushing.
