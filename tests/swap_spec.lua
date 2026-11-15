local swap = require("twintree.swap")

local INFO = {
  version = "VIM 9.0",
  user = "someone",
  host = "machine",
  fname = "~/project/a.txt",
  pid = 0,
  mtime = 1700000000,
  dirty = 0,
}

local function info(overrides)
  return vim.tbl_extend("force", INFO, overrides or {})
end

describe("swap.describe", function()
  it("lays the facts out like Neovim's message", function()
    local text = swap.describe("/swap/a.txt.swp", info(), "/project/a.txt", 1700000100)
    assert.same({
      "E325: ATTENTION",
      'Found a swap file by the name "/swap/a.txt.swp"',
      "          owned by: someone   dated: " .. os.date("%a %b %d %H:%M:%S %Y", 1700000000),
      "         file name: ~/project/a.txt",
      "          modified: no",
      "         user name: someone   host name: machine",
      "        process ID: no longer running",
      'While opening file "/project/a.txt"',
      "             dated: " .. os.date("%a %b %d %H:%M:%S %Y", 1700000100),
    }, vim.split(text, "\n"))
  end)

  it("says when the process is still running", function()
    local text = swap.describe("s.swp", info({ pid = 4242 }), "/project/a.txt")
    assert.truthy(text:find("        process ID: 4242 (STILL RUNNING)", 1, true))
    assert.is_nil(text:find("dated: ", text:find("While opening", 1, true), true))
  end)

  it("says when the file was modified", function()
    local text = swap.describe("s.swp", info({ dirty = 1 }), "/project/a.txt")
    assert.truthy(text:find("          modified: YES", 1, true))
  end)

  it("reports a swap file that cannot be read", function()
    local text = swap.describe("s.swp", { error = "Cannot read file" }, "/project/a.txt")
    assert.same({
      "E325: ATTENTION",
      'Found a swap file by the name "s.swp"',
      "        Cannot read file",
      'While opening file "/project/a.txt"',
    }, vim.split(text, "\n"))
  end)
end)

describe("swap.choices", function()
  it("offers Neovim's six choices with their letters", function()
    local labels, letters = swap.choices(false)
    assert.same({
      "&Open Read-Only",
      "&Edit anyway",
      "&Recover",
      "&Delete it",
      "&Quit",
      "&Abort",
    }, labels)
    assert.same({ "o", "e", "r", "d", "q", "a" }, letters)
  end)

  it("does not offer to delete the swap file of a running process", function()
    local labels, letters = swap.choices(true)
    assert.same({ "&Open Read-Only", "&Edit anyway", "&Recover", "&Quit", "&Abort" }, labels)
    assert.same({ "o", "e", "r", "q", "a" }, letters)
  end)
end)

describe("swap.letter", function()
  it("maps an answer to its letter and no answer to Abort", function()
    local _, letters = swap.choices(false)
    assert.equals("o", swap.letter(letters, 1))
    assert.equals("d", swap.letter(letters, 4))
    assert.equals("a", swap.letter(letters, 6))
    assert.equals("a", swap.letter(letters, 0))
    assert.equals("a", swap.letter(letters, 9))

    local _, running = swap.choices(true)
    assert.equals("q", swap.letter(running, 4))
  end)
end)

describe("swap.ask", function()
  it("shows the text and the choices with confirm()", function()
    local original = vim.fn.confirm
    local seen
    vim.fn.confirm = function(...)
      seen = { ... }
      return 2
    end
    local answer = swap.ask("the text", { "&One", "&Two" })
    vim.fn.confirm = original

    assert.equals(2, answer)
    assert.same({ "the text", "&One\n&Two", 1, "Question" }, seen)
  end)
end)
