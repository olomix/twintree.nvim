local h = require("tests.helpers")
local worktree = require("twintree.worktree")

local function listed(repo, path)
  return h.git(repo, "worktree", "list", "--porcelain"):find(path, 1, true) ~= nil
end

describe("worktree", function()
  local cache, repo, sha

  before_each(function()
    cache = h.reset()
    repo, sha = h.repo({ ["a.txt"] = "a\n" })
  end)

  it("places worktrees under the cache by repository and commit", function()
    local path = worktree.path(repo, sha)
    assert.truthy(vim.startswith(path, cache .. "/"))
    assert.equals(sha, vim.fs.basename(path))
    assert.truthy(vim.fs.basename(vim.fs.dirname(path)):find(vim.fs.basename(repo), 1, true))
  end)

  it("separates repositories that share a directory name", function()
    local a, b = h.tmpdir() .. "/proj", h.tmpdir() .. "/proj"
    for _, dir in ipairs({ a, b }) do
      vim.fn.mkdir(dir, "p")
      h.git(dir, "init", "-q", "-b", "main")
    end
    assert.are_not.equal(worktree.repo_id(a), worktree.repo_id(b))
  end)

  it("shares the location between a checkout and its linked worktree", function()
    local linked = h.tmpdir() .. "/linked"
    h.git(repo, "worktree", "add", "-q", "--detach", linked)
    assert.equals(worktree.path(repo, sha), worktree.path(linked, sha))
  end)

  it("creates a detached worktree on first use", function()
    local path = assert(worktree.ensure(repo, sha))
    assert.equals("a\n", table.concat(vim.fn.readfile(path .. "/a.txt"), "\n") .. "\n")
    assert.equals(sha, h.git(path, "rev-parse", "HEAD"))
    assert.equals("HEAD", h.git(path, "rev-parse", "--abbrev-ref", "HEAD"))
    assert.equals("main", h.git(repo, "branch", "--format=%(refname:short)"))
  end)

  it("reuses an existing worktree", function()
    local path = assert(worktree.ensure(repo, sha))
    h.write(path, "marker", "kept\n")
    assert.equals(path, worktree.ensure(repo, sha))
    assert.truthy(vim.uv.fs_stat(path .. "/marker"))
  end)

  it("replaces a directory that is not a usable worktree", function()
    local path = worktree.path(repo, sha)
    h.write(path, "junk", "junk\n")

    assert.equals(vim.uv.fs_realpath(path), worktree.ensure(repo, sha))
    assert.is_nil(vim.uv.fs_stat(path .. "/junk"))
    assert.truthy(vim.uv.fs_stat(path .. "/a.txt"))
  end)

  it("replaces a worktree that moved to another commit", function()
    local path = assert(worktree.ensure(repo, sha))
    h.write(repo, "b.txt", "b\n")
    local second = h.commit(repo, "second")
    h.git(path, "checkout", "-q", "--detach", second)

    assert.equals(path, worktree.ensure(repo, sha))
    assert.equals(sha, h.git(path, "rev-parse", "HEAD"))
  end)

  it("returns git's error when creation fails", function()
    local path, err = worktree.ensure(repo, ("0"):rep(40))
    assert.is_nil(path)
    assert.truthy(err and err ~= "")
    assert.is_nil(vim.uv.fs_stat(worktree.repo_dir(repo)))
  end)

  it("leaves nothing behind when a checkout hook fails", function()
    local hook = repo .. "/.git/hooks/post-checkout"
    h.write(repo, ".git/hooks/post-checkout", "#!/bin/sh\nexit 1\n")
    vim.uv.fs_chmod(hook, 493)

    local path, err = worktree.ensure(repo, sha)
    assert.is_nil(path)
    assert.truthy(err)
    assert.is_false(worktree.is_ready(repo, sha))
    assert.is_nil(vim.uv.fs_stat(worktree.path(repo, sha)))
    assert.is_nil(vim.uv.fs_stat(worktree.repo_dir(repo)))
    assert.is_false(listed(repo, worktree.path(repo, sha)))
  end)

  it("reports whether a worktree is cached", function()
    assert.is_false(worktree.is_ready(repo, sha))
    assert(worktree.ensure(repo, sha))
    assert.is_true(worktree.is_ready(repo, sha))
  end)

  it("cleans cached worktrees and keeps those in use", function()
    h.write(repo, "b.txt", "b\n")
    local second = h.commit(repo, "second")
    local old = assert(worktree.ensure(repo, sha))
    local new = assert(worktree.ensure(repo, second))
    local both = { old, new }
    table.sort(both)
    assert.same(both, worktree.list(repo))

    assert.equals(1, worktree.clean(repo, { new }))
    assert.is_nil(vim.uv.fs_stat(old))
    assert.is_false(listed(repo, old))
    assert.truthy(vim.uv.fs_stat(new))
    assert.is_true(listed(repo, new))

    assert.equals(1, worktree.clean(repo))
    assert.same({}, worktree.list(repo))
    assert.is_nil(vim.uv.fs_stat(worktree.repo_dir(repo)))
    assert.is_false(listed(repo, new))
    assert.equals(0, worktree.clean(repo))
  end)

  it("opens worktree files without a swap file", function()
    local path = assert(worktree.ensure(repo, sha))
    vim.o.swapfile = true
    vim.o.directory = h.tmpdir() .. "//"

    vim.cmd.edit(repo .. "/a.txt")
    assert.is_true(vim.bo.swapfile)
    assert.are_not.equal("", vim.fn.swapname(""))

    vim.cmd.edit(path .. "/a.txt")
    assert.is_false(vim.bo.swapfile)
    assert.equals("", vim.fn.swapname(""))

    vim.cmd.edit(path .. "/does-not-exist.txt")
    assert.is_false(vim.bo.swapfile)
    vim.o.swapfile = false
  end)

  it("makes worktree buffers read-only and leaves the checkout editable", function()
    local path = assert(worktree.ensure(repo, sha))

    vim.cmd.edit(path .. "/a.txt")
    assert.is_true(vim.bo.readonly)
    assert.is_false(vim.bo.modifiable)
    assert.is_false(pcall(vim.api.nvim_buf_set_lines, 0, 0, -1, false, { "x" }))

    vim.cmd.edit(path .. "/does-not-exist.txt")
    assert.is_false(vim.bo.modifiable)

    vim.cmd.edit(repo .. "/a.txt")
    assert.is_false(vim.bo.readonly)
    assert.is_true(vim.bo.modifiable)
  end)
end)
