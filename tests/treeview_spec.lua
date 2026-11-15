local h = require("tests.helpers")
local icons = require("twintree.icons")
local session = require("twintree.session")
local treeview = require("twintree.treeview")
local twintree = require("twintree")

local api = vim.api

local function cells(text)
  return vim.fn.strdisplaywidth(text)
end

local mini = {
  get = function(category, name)
    return "m", "MiniHl:" .. category .. ":" .. name, false
  end,
}

local devicons = {
  get_icon = function(name, ext, opts)
    return "d", ("DevHl_%s_%s_%s"):format(name:gsub("%W", ""), tostring(ext), tostring(opts.default))
  end,
}

local function stub(modules)
  package.loaded["mini.icons"] = modules.mini
  package.loaded["nvim-web-devicons"] = modules.devicons
end

describe("icons.source", function()
  local cache

  before_each(function()
    cache = h.reset()
    stub({})
  end)

  after_each(function()
    stub({})
    twintree.setup({ cache_dir = cache })
  end)

  it("is nil without an icon plugin", function()
    assert.is_nil(icons.source())
  end)

  it("uses mini.icons", function()
    stub({ mini = mini })
    local icon = assert(icons.source())
    assert.same({ "m", "MiniHl:file:a.lua" }, { icon("a.lua", "file") })
  end)

  it("uses nvim-web-devicons with the extension and a default icon", function()
    stub({ devicons = devicons })
    local icon = assert(icons.source())
    assert.same({ "d", "DevHl_alua_lua_true" }, { icon("a.lua", "file") })
    assert.same({ "d", "DevHl_Makefile_nil_true" }, { icon("Makefile", "file") })
  end)

  it("prefers mini.icons when both are installed", function()
    stub({ mini = mini, devicons = devicons })
    local icon = assert(icons.source())
    assert.equals("m", (icon("a.lua", "file")))
  end)

  it("gives different folder glyphs for open and folded directories", function()
    stub({ devicons = devicons })
    local icon = assert(icons.source())
    local open, open_hl = icon("src", "dir_open")
    local closed, closed_hl = icon("src", "dir_closed")
    assert.equals(icons.FOLDER_OPEN, open)
    assert.equals(icons.FOLDER_CLOSED, closed)
    assert.are_not.equal(open, closed)
    assert.equals("TwintreeDirectory", open_hl)
    assert.equals("TwintreeDirectory", closed_hl)
  end)

  it("is nil when icons are switched off", function()
    stub({ mini = mini, devicons = devicons })
    twintree.setup({ cache_dir = cache, icons = false })
    assert.is_nil(icons.source())
  end)

  it("gives no icon when the plugin raises an error", function()
    stub({
      mini = {
        get = function()
          error("not set up")
        end,
      },
    })
    local icon = assert(icons.source())
    assert.is_nil(icon("a.lua", "file"))
  end)

  it("ignores a module that is not an icon plugin", function()
    stub({ mini = true, devicons = { setup = function() end } })
    assert.is_nil(icons.source())
  end)
end)

describe("tree view", function()
  local cache, repo, tab
  local LONG = "a_file_with_quite_a_long_name_indeed.txt"

  local function state()
    return assert(session.get(tab))
  end

  local function tree_win()
    local win = session.tree_win(state())
    assert.truthy(win)
    return win
  end

  local function lines()
    return h.buf_lines(state().tree_buf)
  end

  ---Every file line is exactly `width` cells and ends with a status letter.
  local function assert_fits(width)
    local seen = 0
    for _, line in ipairs(lines()) do
      assert.is_true(cells(line) <= width, ("%q at %d"):format(line, width))
      if line:match(" [AMDR]$") then
        assert.equals(width, cells(line), line)
        seen = seen + 1
      end
    end
    assert.is_true(seen > 0)
  end

  before_each(function()
    cache = h.reset()
    stub({})
    vim.o.columns = 160
    repo = h.repo({
      ["a.lua"] = "one\ntwo\n",
      ["src/deep/b.lua"] = "b\n",
      [LONG] = "x\n",
    })
    h.write(repo, "a.lua", "one\nTWO\nthree\n")
    h.write(repo, "src/deep/b.lua", "B\n")
    h.write(repo, LONG, "y\n")
    api.nvim_set_current_dir(repo)
    tab = assert(twintree.open())
  end)

  after_each(function()
    stub({})
    twintree.setup({ cache_dir = cache })
    vim.o.columns = 80
  end)

  it("draws lines as wide as the tree window", function()
    assert.equals(35, treeview.text_width(state()))
    assert.equals(35, vim.b[state().tree_buf].twintree_width)
    assert_fits(35)
    assert.same({
      "▾ src/deep/",
      "│ b.lua +1 -1 M",
      "a.lua +2 -1 M",
      "a_file_with_q…me_indeed.txt +1 -1 M",
    }, h.tree_lines(state().tree_buf))
  end)

  it("uses the text area of a window the user made", function()
    api.nvim_win_close(tree_win(), false)
    vim.cmd("botright vsplit")
    local win = api.nvim_get_current_win()
    api.nvim_win_set_buf(win, state().tree_buf)
    vim.wo[win].number = true
    vim.wo[win].signcolumn = "yes"
    api.nvim_win_set_width(win, 40)
    local textoff = vim.fn.getwininfo(win)[1].textoff
    assert.is_true(textoff > 0)

    treeview.redraw_if_resized(tab)
    assert.equals(40 - textoff, treeview.text_width(state()))
    assert_fits(40 - textoff)
  end)

  it("uses the configured width while no window shows the tree", function()
    twintree.setup({ cache_dir = cache, tree_width = 22 })
    assert(twintree.toggle_tree())
    assert.equals(22, treeview.text_width(state()))
    treeview.draw(tab)
    assert_fits(22)
  end)

  it("applies the highlight groups of the pieces", function()
    local buf = state().tree_buf
    local ns = api.nvim_get_namespaces().twintree
    local found = {}
    for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, ns, { 1, 0 }, { 1, -1 }, { details = true })) do
      local text = api.nvim_buf_get_text(buf, 1, mark[3], 1, mark[4].end_col, {})[1]
      found[mark[4].hl_group] = text
    end
    assert.same({
      TwintreeGuide = "│ ",
      TwintreeAdded = "+1",
      TwintreeDeleted = "-1",
      TwintreeModified = "M",
    }, found)
    for _, group in ipairs({ "TwintreeGuide", "TwintreeOrigin" }) do
      assert.truthy(api.nvim_get_hl(0, { name = group }).link)
    end
  end)

  describe("redraw", function()
    it("follows the width of the tree window", function()
      api.nvim_win_set_width(tree_win(), 60)
      assert_fits(35)
      treeview.redraw_if_resized(tab)
      assert_fits(60)
      assert.truthy(vim.tbl_contains(h.tree_lines(state().tree_buf), LONG .. " +1 -1 M"))

      api.nvim_win_set_width(tree_win(), 18)
      treeview.redraw_if_resized(tab)
      assert_fits(18)
    end)

    it("does nothing when the width did not change", function()
      local tick = api.nvim_buf_get_changedtick(state().tree_buf)
      treeview.redraw_if_resized(tab)
      assert.equals(tick, api.nvim_buf_get_changedtick(state().tree_buf))
    end)

    it("happens through the size autocommand", function()
      api.nvim_win_set_width(tree_win(), 28)
      api.nvim_exec_autocmds("WinResized", { group = "twintree" })
      assert_fits(28)
    end)

    ---Set a window option. Neovim does not fire OptionSet while it is
    ---starting, which is when these specs run, so the event is fired here;
    ---`tests/resize_spec.lua` covers the real event.
    local function set_option(option, value)
      api.nvim_set_option_value(option, value, { win = tree_win() })
      api.nvim_exec_autocmds("OptionSet", { group = "twintree", pattern = option })
    end

    for option, value in pairs({
      number = true,
      relativenumber = true,
      signcolumn = "yes",
      foldcolumn = "2",
    }) do
      it(("happens when '%s' shrinks the text area"):format(option), function()
        set_option(option, value)
        local textoff = vim.fn.getwininfo(tree_win())[1].textoff
        assert.is_true(textoff > 0)
        assert_fits(35 - textoff)
      end)
    end

    it("happens when 'numberwidth' changes", function()
      set_option("number", true)
      set_option("numberwidth", 8)
      assert_fits(35 - 8)
    end)

    it("is registered for every option that changes the text area", function()
      local patterns = vim.tbl_map(function(autocmd)
        return autocmd.pattern
      end, api.nvim_get_autocmds({ group = "twintree", event = "OptionSet" }))
      table.sort(patterns)
      assert.same(
        { "foldcolumn", "number", "numberwidth", "relativenumber", "signcolumn" },
        patterns
      )
    end)

    it("happens when a hidden tree is shown at another width", function()
      assert(twintree.toggle_tree())
      local s = state()
      s.layout.tree_width = 48
      session.save(tab, s)

      assert(twintree.toggle_tree())
      assert.equals(48, api.nvim_win_get_width(tree_win()))
      assert_fits(48)
    end)

    it("happens when the layout is reset", function()
      api.nvim_win_set_width(tree_win(), 60)
      treeview.redraw_if_resized(tab)
      assert(twintree.reset_layout())
      assert_fits(35)
    end)

    it("is a no-op in a tab without a session", function()
      vim.cmd.tabnew()
      treeview.redraw_if_resized()
      assert.is_nil(session.get())
    end)
  end)

  it("selects the file of a line whose name is cut", function()
    api.nvim_win_set_width(tree_win(), 18)
    treeview.redraw_if_resized(tab)
    assert.is_nil(table.concat(lines(), "\n"):find(LONG, 1, true))

    h.goto_line(tree_win(), "a_fil")
    h.keys("<CR>")
    assert.equals(LONG, state().selected)
    assert.equals(repo .. "/" .. LONG, api.nvim_buf_get_name(api.nvim_win_get_buf(state().wins.after)))
  end)

  describe("with an icon plugin", function()
    it("shows file icons and folder glyphs", function()
      stub({ devicons = devicons })
      treeview.draw(tab)
      assert.same({
        icons.FOLDER_OPEN .. " src/deep/",
        "│ d b.lua +1 -1 M",
        "d a.lua +2 -1 M",
        "d a_file_with_…e_indeed.txt +1 -1 M",
      }, h.tree_lines(state().tree_buf))
      assert_fits(35)

      h.goto_line(tree_win(), "src/deep/")
      h.keys("<CR>")
      assert.equals(icons.FOLDER_CLOSED .. " src/deep/", lines()[1])
    end)

    it("looks as without one when icons are switched off", function()
      stub({ devicons = devicons })
      twintree.setup({ cache_dir = cache, icons = false })
      treeview.draw(tab)
      assert.equals("▾ src/deep/", lines()[1])
      assert.truthy(vim.startswith(lines()[3], "a.lua "))
    end)
  end)
end)
