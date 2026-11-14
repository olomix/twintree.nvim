local git = require("twintree.git")
local h = require("tests.helpers")

describe("git", function()
  local repo, first

  before_each(function()
    repo, first = h.repo({ ["a.txt"] = "a\n", ["src/b.txt"] = "b\n" })
  end)

  it("finds the toplevel from a subdirectory", function()
    assert.equals(repo, git.toplevel(repo .. "/src"))
  end)

  it("reports a directory that is not a repository", function()
    local dir = h.tmpdir()
    local top, err = git.toplevel(dir)
    assert.is_nil(top)
    assert.equals("not a git repository: " .. dir, err)
  end)

  it("reports a directory that does not exist", function()
    local top, err = git.toplevel("/nonexistent/twintree")
    assert.is_nil(top)
    assert.truthy(err)
  end)

  it("returns an absolute common dir", function()
    assert.equals(repo .. "/.git", git.common_dir(repo))
  end)

  it("resolves revisions to commits", function()
    assert.equals(first, git.resolve(repo, "HEAD"))
    assert.equals(first, git.resolve(repo, "main"))
  end)

  it("reports an unknown revision", function()
    local sha, err = git.resolve(repo, "no-such-rev")
    assert.is_nil(sha)
    assert.equals("cannot resolve revision: no-such-rev", err)

    sha, err = git.resolve(repo, "--all")
    assert.is_nil(sha)
    assert.equals("cannot resolve revision: --all", err)
  end)

  it("finds the merge-base of diverged branches", function()
    h.git(repo, "checkout", "-q", "-b", "feature")
    h.write(repo, "f.txt", "f\n")
    local feature = h.commit(repo, "feature")
    h.git(repo, "checkout", "-q", "main")
    h.write(repo, "m.txt", "m\n")
    local main = h.commit(repo, "main")

    assert.equals(first, git.merge_base(repo, main, feature))
  end)

  it("reports unrelated histories", function()
    h.git(repo, "checkout", "-q", "--orphan", "other")
    h.git(repo, "rm", "-rfq", ".")
    h.write(repo, "o.txt", "o\n")
    h.commit(repo, "orphan")

    local sha, err = git.merge_base(repo, "main", "other")
    assert.is_nil(sha)
    assert.equals("no common ancestor of main and other", err)

    local range
    range, err = git.resolve_range(repo, { "main", "other" })
    assert.is_nil(range)
    assert.equals("no common ancestor of main and other", err)
  end)

  describe("resolve_range", function()
    local feature, main

    before_each(function()
      h.git(repo, "checkout", "-q", "-b", "feature")
      h.write(repo, "f.txt", "f\n")
      feature = h.commit(repo, "feature")
      h.git(repo, "checkout", "-q", "main")
      h.write(repo, "m.txt", "m\n")
      main = h.commit(repo, "main")
    end)

    it("uses HEAD against the working tree without arguments", function()
      assert.same({ before = main }, git.resolve_range(repo, {}))
    end)

    it("uses the merge-base with HEAD for one revision", function()
      assert.same({ before = first }, git.resolve_range(repo, { "feature" }))
      assert.same({ before = first }, git.resolve_range(repo, { "HEAD~1" }))
    end)

    it("uses the merge-base against the second of two revisions", function()
      assert.same(
        { before = first, after = feature },
        git.resolve_range(repo, { "main", "feature" })
      )
    end)

    it("does not need HEAD when two revisions are given", function()
      h.git(repo, "checkout", "-q", "--orphan", "unborn")
      assert.same(
        { before = first, after = feature },
        git.resolve_range(repo, { "main", "feature" })
      )

      local range, err = git.resolve_range(repo, { "main" })
      assert.is_nil(range)
      assert.equals("cannot resolve revision: HEAD", err)
    end)

    it("rejects more than two revisions", function()
      local range, err = git.resolve_range(repo, { "a", "b", "c" })
      assert.is_nil(range)
      assert.equals("expected at most two revisions", err)
    end)

    it("names the revision that cannot be resolved", function()
      local range, err = git.resolve_range(repo, { "main", "nope" })
      assert.is_nil(range)
      assert.equals("cannot resolve revision: nope", err)
    end)
  end)

  describe("changed_files", function()
    it("lists differences between two commits", function()
      h.write(repo, "a.txt", "changed\n")
      h.write(repo, "new file.txt", "n\n")
      h.git(repo, "rm", "-q", "src/b.txt")
      local second = h.commit(repo, "second")

      assert.same({
        { status = "M", path = "a.txt" },
        { status = "A", path = "new file.txt" },
        { status = "D", path = "src/b.txt" },
      }, git.changed_files(repo, first, second))
    end)

    it("detects renames", function()
      h.git(repo, "mv", "src/b.txt", "src/c.txt")
      local second = h.commit(repo, "rename")

      assert.same(
        { { status = "R", old_path = "src/b.txt", path = "src/c.txt" } },
        git.changed_files(repo, first, second)
      )
    end)

    it("lists staged, unstaged and untracked changes of the working tree", function()
      h.write(repo, ".gitignore", "*.log\n")
      local base = h.commit(repo, "ignore")

      h.write(repo, "a.txt", "staged\n")
      h.git(repo, "add", "a.txt")
      h.write(repo, "src/b.txt", "unstaged\n")
      h.write(repo, "docs/файл.md", "untracked\n")
      h.write(repo, "debug.log", "ignored\n")

      assert.same({
        { status = "M", path = "a.txt" },
        { status = "A", path = "docs/файл.md" },
        { status = "M", path = "src/b.txt" },
      }, git.changed_files(repo, base))
    end)

    it("skips an untracked nested repository", function()
      local inner = repo .. "/inner"
      vim.fn.mkdir(inner, "p")
      h.git(inner, "init", "-q", "-b", "main")
      h.write(inner, "x.txt", "x\n")
      h.commit(inner, "inner")
      h.write(repo, "plain/y.txt", "y\n")

      assert.same(
        { { status = "A", path = "plain/y.txt" } },
        git.changed_files(repo, first)
      )
    end)

    it("returns nothing when the sides are equal", function()
      assert.same({}, git.changed_files(repo, first))
      assert.same({}, git.changed_files(repo, first, first))
    end)
  end)

  it("lists ref names for completion", function()
    h.git(repo, "tag", "v1")
    h.git(repo, "branch", "feature")
    local refs = git.ref_names(repo)
    table.sort(refs)
    assert.same({ "feature", "main", "v1" }, refs)
  end)
end)
