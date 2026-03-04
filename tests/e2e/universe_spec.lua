-- tests/e2e/universe_spec.lua
local assert = require("luassert")
local helper = require("tests.universe_helper")
local context = require("nzi.context")

describe("Universe Mapping E2E", function()
  local test_repo_root = nil
  local old_cwd = vim.fn.getcwd()
  local project_root = vim.fn.fnamemodify(old_cwd, ":p")

  before_each(function()
    -- Ensure nzi is in RTP since we'll be cd-ing
    vim.opt.runtimepath:prepend(project_root)
    
    test_repo_root = helper.setup_test_repo()
    vim.cmd("cd " .. test_repo_root)
    -- Reset context states for each test
    context.states = {}
  end)

  after_each(function()
    vim.cmd("cd " .. old_cwd)
    if test_repo_root then
      helper.teardown_test_repo(test_repo_root)
    end
    -- Wipe all buffers
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("should include tracked and untracked git files as 'map' state", function()
    local ctx = context.gather()
    
    -- In helper repo: main.lua (tracked), src/utils.lua (tracked), feat_new.lua (untracked), staged.lua (staged)
    -- .env is ignored.
    
    local names = {}
    for _, item in ipairs(ctx) do
      names[item.name] = item.state
    end
    
    assert.are.equal("map", names["main.lua"])
    assert.are.equal("map", names["src/utils.lua"])
    assert.are.equal("map", names["feat_new.lua"])
    assert.are.equal("map", names["staged.lua"])
    
    -- .env should be missing
    assert.is_nil(names[".env"])
  end)

  it("should promote 'map' to 'active' when a buffer is opened", function()
    local buf = vim.fn.bufadd(test_repo_root .. "/main.lua")
    vim.fn.bufload(buf)
    vim.api.nvim_set_option_value("buflisted", true, { buf = buf })

    local ctx = context.gather()
    local main_item = nil
    for _, item in ipairs(ctx) do
      if item.name == "main.lua" then main_item = item end
    end
    
    assert.is_not_nil(main_item)
    assert.are.equal("active", main_item.state)
    assert.is_not_nil(main_item.content)
  end)

  it("should respect :AI/ignore for open buffers (hiding them from universe too)", function()
    local buf = vim.fn.bufadd(test_repo_root .. "/main.lua")
    vim.fn.bufload(buf)
    vim.api.nvim_set_option_value("buflisted", true, { buf = buf })
    
    context.set_state(buf, "ignore")
    
    local ctx = context.gather()
    local names = {}
    for _, item in ipairs(ctx) do
      names[item.name] = item.state
    end

    -- main.lua should be gone completely
    assert.is_nil(names["main.lua"])
    
    -- The rest of the universe should still be present as 'map'
    assert.are.equal("map", names["src/utils.lua"])
    assert.are.equal("map", names["feat_new.lua"])
  end)

  it("should include Tree-sitter skeletons for 'map' files", function()
    local ctx = context.gather()
    local main_item = nil
    for _, item in ipairs(ctx) do
      if item.name == "main.lua" then main_item = item end
    end
    
    assert.is_not_nil(main_item)
    assert.are.equal("map", main_item.state)
    -- Metadata should contain the function name from universe_helper
    assert.match("Symbols:.*main_task", main_item.content)
  end)
end)
