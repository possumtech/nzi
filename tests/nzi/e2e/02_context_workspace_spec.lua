local assert = require("luassert")
local context = require("nzi.service.vim.watcher")
local config = require("nzi.core.config")

describe("2. Context & Workspace State", function()
  local test_buf

  before_each(function()
    require("nzi").setup({})
    require("nzi.dom.session").clear()
    context.states = {} -- clear states
    
    test_buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(test_buf, "test_context_file.lua")
    vim.api.nvim_set_current_buf(test_buf)
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(test_buf) then
      vim.api.nvim_buf_delete(test_buf, { force = true })
    end
  end)

  it("should mark a buffer as active with :AI/active", function()
    vim.cmd("AI/active")
    assert.equals("active", context.get_state(test_buf))
  end)

  it("should mark a buffer as read-only context with :AI/read", function()
    vim.cmd("AI/read")
    assert.equals("read", context.get_state(test_buf))
  end)

  it("should remove a buffer from context with :AI/ignore", function()
    vim.cmd("AI/ignore")
    assert.equals("ignore", context.get_state(test_buf))
  end)

  it("should load the project file map into context", function()
    -- Create a mock universe file list
    local orig_get_universe = context.get_universe
    context.get_universe = function()
      return { "file1.lua", "file2.lua" }
    end
    
    -- Mute sitter for the test
    local orig_get_skeleton = require("nzi.service.vim.sitter").get_skeleton
    require("nzi.service.vim.sitter").get_skeleton = function(path)
      return "skeleton code for " .. path, nil
    end

    local ctx = context.gather()
    
    -- Check that map files exist in gather
    local found_file1 = false
    local found_file2 = false
    for _, item in ipairs(ctx) do
      if item.name == "file1.lua" and item.state == "map" then found_file1 = true end
      if item.name == "file2.lua" and item.state == "map" then found_file2 = true end
    end
    
    assert.True(found_file1, "file1.lua should be in map state")
    assert.True(found_file2, "file2.lua should be in map state")
    
    -- restore
    context.get_universe = orig_get_universe
    require("nzi.service.vim.sitter").get_skeleton = orig_get_skeleton
  end)
  
  it("context.gather() should correctly compile file metadata and contents based on states", function()
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, { "line 1", "line 2" })
    vim.cmd("AI/active")
    
    local ctx = context.gather()
    local found = false
    for _, item in ipairs(ctx) do
      if item.bufnr == test_buf then
        found = true
        assert.equals("active", item.state)
        assert.equals("line 1\nline 2", item.content)
      end
    end
    assert.True(found, "Test buffer should be gathered")
  end)
end)
