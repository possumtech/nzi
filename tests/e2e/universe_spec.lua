-- tests/e2e/universe_spec.lua
local assert = require("luassert")
local helper = require("tests.universe_helper")
local context = require("nzi.context.context")

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

  it("should include tracked and staged git files as 'map' state", function()
    local ctx = context.gather()
    
    -- In helper repo: main.lua (tracked), src/utils.lua (tracked), staged.lua (staged)
    -- feat_new.lua is untracked (NOT in map). .env is ignored.
    
    local names = {}
    for _, item in ipairs(ctx) do
      names[item.name] = item.state
    end
    
    assert.are.equal("map", names["main.lua"])
    assert.are.equal("map", names["src/utils.lua"])
    assert.are.equal("map", names["staged.lua"])
    
    -- feat_new.lua and .env should be missing
    assert.is_nil(names["feat_new.lua"], "Untracked file should be passively ignored (not in map)")
    assert.is_nil(names[".env"], "Git-ignored file should be actively ignored (not in map)")
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

  it("should ignore git-ignored files even if opened as buffers", function()
    -- .env is git-ignored in the helper repo
    local buf = vim.fn.bufadd(test_repo_root .. "/.env")
    vim.fn.bufload(buf)
    vim.api.nvim_set_option_value("buflisted", true, { buf = buf })

    local ctx = context.gather()
    local env_item = nil
    for _, item in ipairs(ctx) do
      if item.name == ".env" then env_item = item end
    end
    
    -- Should be ignored by default because git says so
    assert.is_nil(env_item)
  end)

  it("should allow user override for git-ignored files", function()
    local buf = vim.fn.bufadd(test_repo_root .. "/.env")
    vim.fn.bufload(buf)
    vim.api.nvim_set_option_value("buflisted", true, { buf = buf })

    -- Explicit override
    context.set_state(buf, "active")

    local ctx = context.gather()
    local env_item = nil
    for _, item in ipairs(ctx) do
      if item.name == ".env" then env_item = item end
    end
    
    assert.is_not_nil(env_item)
    assert.are.equal("active", env_item.state)
  end)

  it("should include untracked files ONLY if opened as buffers", function()
    -- feat_new.lua is untracked but NOT git-ignored in helper
    local ctx_before = context.gather()
    local found_before = false
    for _, item in ipairs(ctx_before) do
      if item.name == "feat_new.lua" then found_before = true end
    end
    assert.is_false(found_before, "Untracked file should not be in universe map")

    -- Now open it
    local buf = vim.fn.bufadd(test_repo_root .. "/feat_new.lua")
    vim.fn.bufload(buf)
    vim.api.nvim_set_option_value("buflisted", true, { buf = buf })

    local ctx_after = context.gather()
    local item_after = nil
    for _, item in ipairs(ctx_after) do
      if item.name == "feat_new.lua" then item_after = item end
    end
    
    assert.is_not_nil(item_after)
    assert.are.equal("active", item_after.state)
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
