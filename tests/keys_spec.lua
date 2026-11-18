local h = require("tests.helpers")
local session = require("twintree.session")
local twintree = require("twintree")

local api = vim.api

local NEXT, PREV = "]<C-f>", "[<C-f>"
local OURS_NEXT = "Twintree: next changed file"
local OURS_PREV = "Twintree: previous changed file"

describe("keys", function()
  local cache, repo, messages, notify
  -- Every key a spec may map, so that none of them outlives its spec.
  local USED = { NEXT, PREV, "<F7>", "<F8>", "<Tab>", "<C-I>" }

  ---The global normal-mode mapping on a key.
  local function global(lhs)
    local code = vim.keycode(lhs)
    for _, mapping in ipairs(api.nvim_get_keymap("n")) do
      if vim.keycode(mapping.lhs) == code then
        return mapping
      end
    end
    return nil
  end

  local function desc(lhs)
    local mapping = global(lhs)
    return mapping and mapping.desc
  end

  ---What makes a mapping the one it was: everything but where it was set.
  local function essence(mapping)
    if not mapping then
      return nil
    end
    return {
      desc = mapping.desc,
      rhs = mapping.rhs,
      callback = mapping.callback,
      expr = mapping.expr,
      noremap = mapping.noremap,
      silent = mapping.silent,
      nowait = mapping.nowait,
      script = mapping.script,
    }
  end

  local function press(keys)
    h.keys(keys)
  end

  local function open()
    local tab = assert(twintree.open())
    messages = {}
    return tab
  end

  ---The changed file the after pane of a diff tab shows.
  local function shown(tab)
    local s = assert(session.get(tab))
    return vim.fs.basename(api.nvim_buf_get_name(api.nvim_win_get_buf(s.wins.after)))
  end

  ---A mapping of the user that counts how often it ran.
  local function user_map(lhs, name, opts)
    vim.keymap.set("n", lhs, function()
      vim.g.hits = (vim.g.hits or 0) + 1
      vim.g.hit_count = vim.v.count1
    end, vim.tbl_extend("force", { desc = name }, opts or {}))
  end

  ---Reload the Lua modules of the plugin, as a plugin manager does, run
  ---`fn`, and put the original modules back: other specs hold them.
  local function reloaded(with_setup, fn)
    local originals = {}
    for module, value in pairs(package.loaded) do
      if module:match("^twintree") then
        originals[module] = value
      end
    end
    for module in pairs(originals) do
      package.loaded[module] = nil
    end
    local ok, err = pcall(function()
      vim.cmd.runtime("plugin/twintree.lua")
      if with_setup then
        require("twintree").setup({ cache_dir = cache })
      end
      fn()
    end)
    for module in pairs(package.loaded) do
      if module:match("^twintree") then
        package.loaded[module] = nil
      end
    end
    for module, value in pairs(originals) do
      package.loaded[module] = value
    end
    vim.cmd.runtime("plugin/twintree.lua")
    assert(ok, err)
  end

  before_each(function()
    cache = h.reset()
    vim.o.columns = 160
    vim.g.hits, vim.g.hit_count, vim.g.mode = nil, nil, nil
    repo = h.repo({ ["a.txt"] = "a\n", ["b.txt"] = "b\n", ["c.txt"] = "c\n" })
    for _, file in ipairs({ "a.txt", "b.txt", "c.txt" }) do
      h.write(repo, file, "changed\n")
    end
    api.nvim_set_current_dir(repo)
    messages = {}
    notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(messages, { msg = msg, level = level })
    end
  end)

  after_each(function()
    vim.notify = notify
    vim.o.columns = 80
    -- Releases what the plugin bound, then removes what the spec mapped.
    h.reset()
    for _, lhs in ipairs(USED) do
      pcall(vim.keymap.del, { "n", "x", "o" }, lhs)
      pcall(vim.keymap.del, "n", lhs, { buffer = 0 })
    end
    -- Keys of the leader specs, under every leader they use.
    for _, lhs in ipairs({ " n", ",n", "\\n" }) do
      pcall(api.nvim_del_keymap, "n", lhs)
    end
    vim.g.mapleader = nil
    assert.same({}, vim.g.twintree_keys)
  end)

  describe("in a diff tab", function()
    it("move between the changed files", function()
      local tab = open()
      assert.equals(2, #api.nvim_list_tabpages())
      assert.equals(OURS_NEXT, desc(NEXT))
      assert.equals(OURS_PREV, desc(PREV))

      press(NEXT)
      assert.equals("b.txt", shown(tab))
      press(PREV)
      assert.equals("a.txt", shown(tab))
      assert.same({}, messages)
    end)

    it("take a count", function()
      local tab = open()
      press("2" .. NEXT)
      assert.equals("c.txt", shown(tab))
      press("5" .. PREV)
      assert.equals("a.txt", shown(tab))
    end)

    it("report the end of the list as information", function()
      local tab = open()
      press(PREV)
      assert.same({
        { msg = "twintree: no more changed files", level = vim.log.levels.INFO },
      }, messages)
      assert.equals("a.txt", shown(tab))
    end)

    it("work in each of two diff tabs", function()
      local one = open()
      local two = open()
      assert.equals(3, #api.nvim_list_tabpages())
      press(NEXT)
      assert.equals("b.txt", shown(two))
      assert.equals("a.txt", shown(one))

      api.nvim_set_current_tabpage(one)
      press("2" .. NEXT)
      assert.equals("c.txt", shown(one))
      assert.equals("b.txt", shown(two))
    end)

    it("are bound at once when the first file of a diff is not shown", function()
      -- Stands in for an autocommand of the user that closes a pane.
      local treeview = require("twintree.treeview")
      local set_entries = treeview.set_entries
      treeview.set_entries = function(tab, entries)
        set_entries(tab, entries)
        api.nvim_win_close(session.get(tab).wins.after, true)
      end
      local ok, tab, err = pcall(twintree.open)
      treeview.set_entries = set_entries
      assert.is_true(ok, tostring(tab))
      assert.equals(session.BROKEN_LAYOUT, err)
      assert.equals(2, #api.nvim_list_tabpages())
      assert.equals(OURS_NEXT, desc(NEXT))
      assert.equals(OURS_PREV, desc(PREV))
    end)
  end)

  describe("of the user", function()
    it("come back after the diff tab is left and after it is closed", function()
      user_map(NEXT, "user callback", { silent = true, nowait = true })
      vim.cmd([[nnoremap <expr> [<C-f> execute('let g:hits = get(g:, "hits", 0) + 10') ? '' : '']])
      local before = { essence(global(NEXT)), essence(global(PREV)) }

      vim.cmd.edit(repo .. "/a.txt")
      local tab = open()
      assert.equals(2, #api.nvim_list_tabpages())
      assert.equals(OURS_NEXT, desc(NEXT))
      assert.equals(OURS_PREV, desc(PREV))

      vim.cmd.tabprevious()
      assert.same(before, { essence(global(NEXT)), essence(global(PREV)) })
      press("3" .. NEXT)
      assert.equals(1, vim.g.hits)
      assert.equals(3, vim.g.hit_count)
      press(PREV)
      assert.equals(11, vim.g.hits)
      assert.equals("a.txt", shown(tab))

      vim.cmd.tabnext()
      assert.equals(OURS_NEXT, desc(NEXT))
      press(NEXT)
      assert.equals("b.txt", shown(tab))
      assert.equals(11, vim.g.hits)

      vim.cmd.tabclose()
      assert.same(before, { essence(global(NEXT)), essence(global(PREV)) })
    end)

    it("stay unmapped when they were not mapped", function()
      vim.cmd.edit(repo .. "/a.txt")
      open()
      vim.cmd.tabprevious()
      assert.is_nil(global(NEXT))
      assert.is_nil(global(PREV))
      vim.cmd.tabnext()
      vim.cmd.tabclose()
      assert.is_nil(global(NEXT))
      assert.is_nil(global(PREV))
    end)

    it("for several modes keep working in every mode", function()
      vim.cmd([[map ]<C-f> <Cmd>let g:mode = mode(1)<CR>]])
      vim.cmd.edit(repo .. "/a.txt")
      local tab = open()

      -- In the diff tab: the plugin's in normal mode, the user's elsewhere.
      press(NEXT)
      assert.equals("b.txt", shown(tab))
      assert.is_nil(vim.g.mode)
      press("v" .. NEXT .. "<Esc>")
      assert.equals("v", vim.g.mode)
      press("d" .. NEXT .. "<Esc>")
      assert.equals("no", vim.g.mode)

      vim.cmd.tabprevious()
      for keys, mode in pairs({ [NEXT] = "n", ["v" .. NEXT .. "<Esc>"] = "v", ["d" .. NEXT .. "<Esc>"] = "no" }) do
        vim.g.mode = nil
        press(keys)
        assert.equals(mode, vim.g.mode)
      end
      assert.equals("b.txt", shown(tab))
    end)

    it("keep a change the user made in another mode during the diff", function()
      vim.cmd([[map ]<C-f> <Cmd>let g:mode = mode(1)<CR>]])
      vim.cmd.edit(repo .. "/a.txt")
      open()
      vim.cmd([[xnoremap ]<C-f> <Cmd>let g:mode = "newer"<CR>]])

      vim.cmd.tabprevious()
      press("v" .. NEXT .. "<Esc>")
      assert.equals("newer", vim.g.mode)
      press(NEXT)
      assert.equals("n", vim.g.mode)
    end)

    it("are saved and restored past a buffer-local mapping", function()
      user_map(NEXT, "user global")
      local before = essence(global(NEXT))
      vim.cmd.edit(repo .. "/c.txt")
      local outside = api.nvim_get_current_buf()
      vim.keymap.set("n", NEXT, "<Nop>", { buffer = outside, desc = "local outside" })

      local tab = open()
      local pane = api.nvim_win_get_buf(session.get(tab).wins.after)
      vim.keymap.set("n", NEXT, "<Nop>", { buffer = pane, desc = "local in pane" })
      assert.equals(pane, api.nvim_get_current_buf())
      assert.equals("local in pane", vim.fn.maparg(NEXT, "n", false, true).desc)

      -- Binds again, with the buffer-local mapping in the current buffer.
      twintree.setup({ cache_dir = cache })
      assert.equals(OURS_NEXT, desc(NEXT))

      -- Releases, with one in the buffer that becomes current.
      vim.cmd.tabprevious()
      assert.equals(outside, api.nvim_get_current_buf())
      assert.same(before, essence(global(NEXT)))
      assert.equals("local outside", vim.fn.maparg(NEXT, "n", false, true).desc)
      assert.equals(1, #vim.tbl_filter(function(mapping)
        return vim.keycode(mapping.lhs) == vim.keycode(NEXT)
      end, api.nvim_buf_get_keymap(pane, "n")))
      assert.is_nil(global(PREV))
    end)
  end)

  describe("mapped again while a diff tab is current", function()
    it("are left alone on leaving, on coming back and in a second diff tab", function()
      vim.cmd.edit(repo .. "/a.txt")
      open()
      user_map(NEXT, "newer")

      vim.cmd.tabprevious()
      assert.equals("newer", desc(NEXT))
      assert.is_nil(global(PREV))
      vim.cmd.tabnext()
      assert.equals("newer", desc(NEXT))
      assert.equals(OURS_PREV, desc(PREV))

      open()
      assert.equals(3, #api.nvim_list_tabpages())
      assert.equals("newer", desc(NEXT))
      assert.equals(OURS_PREV, desc(PREV))
    end)

    it("are left alone when the user unmapped them", function()
      vim.cmd.edit(repo .. "/a.txt")
      user_map(NEXT, "older")
      open()
      vim.keymap.del("n", NEXT)

      vim.cmd.tabprevious()
      assert.is_nil(global(NEXT))
      vim.cmd.tabnext()
      assert.is_nil(global(NEXT))
      assert.equals(OURS_PREV, desc(PREV))
    end)

    it("are bound again by setup, which keeps the newer mapping for later", function()
      vim.cmd.edit(repo .. "/a.txt")
      user_map(NEXT, "older")
      local tab = open()
      user_map(NEXT, "newer")

      -- No tab change in between: setup itself has to notice the mapping.
      twintree.setup({ cache_dir = cache })
      assert.equals(OURS_NEXT, desc(NEXT))
      press(NEXT)
      assert.equals("b.txt", shown(tab))

      vim.cmd.tabprevious()
      assert.equals("newer", desc(NEXT))
    end)

    it("stay given up after a setup that is not accepted", function()
      vim.cmd.edit(repo .. "/a.txt")
      open()
      user_map(NEXT, "newer")
      vim.cmd.tabprevious()
      vim.cmd.tabnext()

      twintree.setup({ keys = { next_file = "" } })
      assert.equals(1, #messages)
      assert.equals(vim.log.levels.ERROR, messages[1].level)
      assert.equals("newer", desc(NEXT))
      assert.equals(OURS_PREV, desc(PREV))
      vim.cmd.tabprevious()
      assert.equals("newer", desc(NEXT))
    end)
  end)

  describe("after a tab change that fired no event", function()
    it("are released by the first press and are the user's from the second", function()
      user_map(NEXT, "user")
      local tab = open()
      vim.cmd("noautocmd tabnew")
      assert.is_nil(session.get())
      assert.equals(OURS_NEXT, desc(NEXT))

      press(NEXT)
      assert.equals("a.txt", shown(tab))
      assert.is_nil(vim.g.hits)
      assert.same({}, messages)
      assert.equals("user", desc(NEXT))
      assert.is_nil(global(PREV))

      press(NEXT)
      assert.equals(1, vim.g.hits)
      press(PREV)
      assert.is_nil(global(PREV))
      assert.equals("a.txt", shown(tab))

      -- An event binds them again.
      vim.cmd.tabprevious()
      assert.equals(OURS_NEXT, desc(NEXT))
      assert.equals(OURS_PREV, desc(PREV))
      press(NEXT)
      assert.equals("b.txt", shown(tab))
    end)

    it("are released by a press after the modules were reloaded", function()
      user_map(NEXT, "user")
      local tab = open()
      reloaded(true, function()
        assert.equals(OURS_NEXT, desc(NEXT))
        vim.cmd("noautocmd tabnew")
        press(NEXT)
        assert.equals("user", desc(NEXT))
        assert.is_nil(global(PREV))
        assert.is_nil(vim.g.hits)
        press(NEXT)
        assert.equals(1, vim.g.hits)
      end)
      assert.equals("a.txt", shown(tab))
    end)

    it("are missing in a diff tab until the next event, and the commands work", function()
      vim.cmd.edit(repo .. "/a.txt")
      local tab = open()
      vim.cmd.tabprevious()
      assert.is_nil(global(NEXT))

      vim.cmd("noautocmd tabnext")
      assert.truthy(session.get())
      assert.is_nil(global(NEXT))
      vim.cmd("TwintreeNextFile")
      assert.equals("b.txt", shown(tab))

      vim.cmd.tabprevious()
      vim.cmd.tabnext()
      assert.equals(OURS_NEXT, desc(NEXT))
      press(NEXT)
      assert.equals("c.txt", shown(tab))
    end)
  end)

  describe("after a reload", function()
    it("keep working, and the user's mapping comes back on leaving", function()
      user_map(NEXT, "user")
      vim.cmd.edit(repo .. "/a.txt")
      local tab = open()
      reloaded(true, function()
        assert.equals(OURS_NEXT, desc(NEXT))
        press(NEXT)
        assert.equals("b.txt", shown(tab))
        vim.cmd.tabprevious()
        assert.equals("user", desc(NEXT))
        assert.is_nil(global(PREV))
        vim.cmd.tabnext()
        assert.equals(OURS_NEXT, desc(NEXT))
      end)
    end)

    it("fall back to the default keys until setup is called again", function()
      twintree.setup({ cache_dir = cache, keys = { next_file = "<F7>", prev_file = false } })
      vim.cmd.edit(repo .. "/a.txt")
      local tab = open()
      assert.equals(OURS_NEXT, desc("<F7>"))
      assert.is_nil(global(NEXT))

      reloaded(false, function()
        -- The mapping set before the reload runs the reloaded code.
        press("<F7>")
        assert.equals("b.txt", shown(tab))
        vim.cmd.tabprevious()
        vim.cmd.tabnext()
        assert.is_nil(global("<F7>"))
        assert.equals(OURS_NEXT, desc(NEXT))
        assert.equals(OURS_PREV, desc(PREV))
      end)
    end)
  end)

  it("exchange keys in one pass when the configuration changes under them", function()
    user_map(NEXT, "user next")
    user_map(PREV, "user prev")
    twintree.setup({ cache_dir = cache, keys = { next_file = PREV, prev_file = NEXT } })
    vim.cmd.edit(repo .. "/a.txt")
    local tab = open()
    assert.equals(OURS_NEXT, desc(PREV))

    -- A reload brings the defaults back, which are the two keys exchanged.
    reloaded(false, function()
      -- In the diff tab, so that both keys change hands in one pass.
      require("twintree.keys").sync()
      assert.equals(OURS_NEXT, desc(NEXT))
      assert.equals(OURS_PREV, desc(PREV))
      press(NEXT)
      assert.equals("b.txt", shown(tab))
      vim.cmd.tabprevious()
      assert.equals("user next", desc(NEXT))
      assert.equals("user prev", desc(PREV))
    end)
  end)

  it("release a key recorded without its stored form", function()
    user_map(NEXT, "user")
    vim.cmd.edit(repo .. "/a.txt")
    open()
    -- As a record written by a version that did not keep that form.
    local records = vim.g.twintree_keys
    records.next_file.raw, records.prev_file.raw = nil, nil
    vim.g.twintree_keys = records

    vim.cmd.tabprevious()
    assert.equals("user", desc(NEXT))
    assert.is_nil(global(PREV))
    assert.same({}, vim.g.twintree_keys)
  end)

  describe("with the leader in them", function()
    ---The description of the global mapping whose key is shown as `lhs`.
    local function shown_as(lhs)
      for _, mapping in ipairs(api.nvim_get_keymap("n")) do
        if mapping.lhs == lhs then
          return mapping.desc or "(no description)"
        end
      end
      return nil
    end

    it("use the leader of the moment they are bound, not of setup", function()
      vim.g.mapleader = nil
      twintree.setup({ cache_dir = cache, keys = { next_file = "<Leader>n", prev_file = false } })
      -- As in a configuration that sets the leader after the plugins.
      vim.g.mapleader = " "
      vim.keymap.set("n", "<Leader>n", "<Nop>", { desc = "user" })
      assert.equals("user", shown_as(" n"))

      vim.cmd.edit(repo .. "/a.txt")
      local tab = open()
      assert.equals(OURS_NEXT, shown_as(" n"))
      assert.equals("user", vim.g.twintree_keys.next_file.saved.desc)
      press(" n")
      assert.equals("b.txt", shown(tab))

      vim.cmd.tabprevious()
      assert.equals("user", shown_as(" n"))
      assert.same({}, vim.g.twintree_keys)
      vim.cmd.tabnext()
      assert.equals(OURS_NEXT, shown_as(" n"))
      vim.cmd.tabclose()
      assert.equals("user", shown_as(" n"))
    end)

    it("are released under the leader they were bound with", function()
      vim.g.mapleader = ","
      twintree.setup({ cache_dir = cache, keys = { next_file = "<Leader>n", prev_file = false } })
      vim.keymap.set("n", ",n", "<Nop>", { desc = "user comma" })
      vim.cmd.edit(repo .. "/a.txt")
      local tab = open()
      assert.equals(OURS_NEXT, shown_as(",n"))

      -- The leader changes while the key is bound.
      vim.g.mapleader = " "
      vim.cmd.tabprevious()
      assert.equals("user comma", shown_as(",n"))
      assert.is_nil(shown_as(" n"))
      assert.same({}, vim.g.twintree_keys)

      -- From now on the key is the one of the new leader.
      vim.cmd.tabnext()
      assert.equals(OURS_NEXT, shown_as(" n"))
      assert.equals("user comma", shown_as(",n"))
      press(" n")
      assert.equals("b.txt", shown(tab))
      vim.cmd.tabclose()
      assert.is_nil(shown_as(" n"))
      assert.equals("user comma", shown_as(",n"))
    end)

    it("move to the new leader at the next tab change when it changes in a diff tab", function()
      vim.g.mapleader = ","
      twintree.setup({ cache_dir = cache, keys = { next_file = "<Leader>n", prev_file = false } })
      vim.cmd.edit(repo .. "/a.txt")
      open()
      vim.g.mapleader = " "
      require("twintree.keys").sync()
      assert.is_nil(shown_as(",n"))
      assert.equals(OURS_NEXT, shown_as(" n"))
      vim.cmd.tabprevious()
      assert.is_nil(shown_as(" n"))
      assert.is_nil(shown_as(",n"))
    end)
  end)

  describe("configured", function()
    it("are the keys of setup, not the defaults", function()
      twintree.setup({ cache_dir = cache, keys = { next_file = "<F7>", prev_file = "<F8>" } })
      local tab = open()
      assert.is_nil(global(NEXT))
      assert.is_nil(global(PREV))
      press("<F7>")
      assert.equals("b.txt", shown(tab))
      press("<F8>")
      assert.equals("a.txt", shown(tab))
    end)

    it("are not taken for another key that only reads the same", function()
      -- Neovim keeps <Tab> and <C-I> as two mappings.
      vim.keymap.set("n", "<Tab>", function()
        vim.g.hits = (vim.g.hits or 0) + 1
      end, { desc = "user tab" })
      local function tab_mapping()
        for _, mapping in ipairs(api.nvim_get_keymap("n")) do
          if mapping.lhs == "<Tab>" then
            return mapping
          end
        end
      end
      local before = essence(tab_mapping())
      assert.truthy(before)

      twintree.setup({ cache_dir = cache, keys = { next_file = "<C-I>", prev_file = false } })
      vim.cmd.edit(repo .. "/a.txt")
      open()
      assert.is_nil(vim.g.twintree_keys.next_file.saved)
      assert.same(before, essence(tab_mapping()))

      vim.cmd.tabprevious()
      vim.cmd.tabnext()
      vim.cmd.tabprevious()
      -- Not given up over the other key, and not left behind.
      assert.same({}, vim.g.twintree_keys)
      assert.same(before, essence(tab_mapping()))
      local ours = vim.tbl_filter(function(mapping)
        return mapping.desc == OURS_NEXT
      end, api.nvim_get_keymap("n"))
      assert.same({}, ours)
    end)

    it("leave an action without a key for false", function()
      twintree.setup({ cache_dir = cache, keys = { next_file = false } })
      local tab = open()
      assert.is_nil(global(NEXT))
      assert.equals(OURS_PREV, desc(PREV))
      vim.cmd("TwintreeNextFile")
      assert.equals("b.txt", shown(tab))
      press(PREV)
      assert.equals("a.txt", shown(tab))
    end)

    it("switch at once when setup is called in a diff tab", function()
      user_map(NEXT, "user")
      local tab = open()
      twintree.setup({ cache_dir = cache, keys = { next_file = "<F7>", prev_file = "<F8>" } })
      assert.equals("user", desc(NEXT))
      assert.is_nil(global(PREV))
      press(NEXT)
      assert.equals(1, vim.g.hits)
      assert.equals("a.txt", shown(tab))
      press("<F7>")
      assert.equals("b.txt", shown(tab))
    end)

    it("exchange the two keys without leaving a mapping behind", function()
      user_map(NEXT, "user next")
      user_map(PREV, "user prev")
      vim.cmd.edit(repo .. "/a.txt")
      local tab = open()
      twintree.setup({ cache_dir = cache, keys = { next_file = PREV, prev_file = NEXT } })
      assert.equals(OURS_NEXT, desc(PREV))
      assert.equals(OURS_PREV, desc(NEXT))
      press(PREV)
      assert.equals("b.txt", shown(tab))
      press(NEXT)
      assert.equals("a.txt", shown(tab))

      vim.cmd.tabprevious()
      assert.equals("user next", desc(NEXT))
      assert.equals("user prev", desc(PREV))
    end)

    it("change nothing for a second identical setup", function()
      user_map(NEXT, "user")
      vim.cmd.edit(repo .. "/a.txt")
      open()
      local record = vim.g.twintree_keys
      twintree.setup({ cache_dir = cache })
      assert.equals(OURS_NEXT, desc(NEXT))
      assert.equals(record.next_file.saved.desc, vim.g.twintree_keys.next_file.saved.desc)
      assert.is_nil(vim.g.twintree_keys.prev_file.saved)
      vim.cmd.tabprevious()
      assert.equals("user", desc(NEXT))
      assert.is_nil(global(PREV))
    end)
  end)
end)
