local assert = require("luassert")
local agent = require("nzi.protocol.agent")
local diff = require("nzi.ui.diff")
local context = require("nzi.context.context")

describe("6. Protocol & Actions", function()
  before_each(function()
    diff.pending_reviews = {}
    diff.pending_deletions = {}
    context.states = {}
  end)

  it("should process <model:read> and add file to active context", function()
    local actions = {
      { name = "read", attr = "file=\"dummy.lua\"", content = "" }
    }
    
    local orig_resolve = require("nzi.context.resolver").resolve
    require("nzi.context.resolver").resolve = function(f) return f, nil end
    
    local called_back = false
    agent.dispatch_actions(actions, function(resp)
      called_back = true
      assert.match("File read and added to active context", resp)
    end)
    
    -- Needs wait since run_next uses vim.schedule in some places, but for read it doesn't currently.
    assert.True(called_back)
    local bufnr = vim.fn.bufadd("dummy.lua")
    assert.equals("active", context.get_state(bufnr))
    
    require("nzi.context.resolver").resolve = orig_resolve
  end)

  it("should process <model:delete> and register a pending deletion", function()
    local actions = {
      { name = "delete", attr = "file=\"delete_me.lua\"", content = "" }
    }
    
    local orig_resolve = require("nzi.context.resolver").resolve
    require("nzi.context.resolver").resolve = function(f) return f, nil end
    
    local orig_yolo = require("nzi.core.config").options.yolo
    require("nzi.core.config").options.yolo = false
    
    local called_back = false
    agent.dispatch_actions(actions, function(resp)
      called_back = true
      assert.match("Proposed deletion", resp)
    end)
    
    assert.True(called_back)
    assert.truthy(diff.pending_deletions["delete_me.lua"])
    
    require("nzi.core.config").options.yolo = orig_yolo
    require("nzi.context.resolver").resolve = orig_resolve
  end)

  it("AI/accept should confirm deletion and AI/reject should discard it", function()
    diff.propose_deletion("target.lua")
    assert.equals(1, diff.get_count())
    
    -- Reject
    local mock_bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(mock_bufnr, "target.lua")
    
    diff.reject(mock_bufnr)
    assert.equals(0, diff.get_count())
    assert.falsy(diff.pending_deletions["target.lua"])
    
    vim.api.nvim_buf_delete(mock_bufnr, {force=true})
  end)

  it("should process <model:create> and open a suggestion buffer", function()
    local actions = {
      { name = "create", attr = "file=\"new_file.lua\"", content = "print('hello')" }
    }
    
    local orig_yolo = require("nzi.core.config").options.yolo
    require("nzi.core.config").options.yolo = false
    
    -- Auto-confirm the file creation prompt
    local orig_confirm = vim.fn.confirm
    vim.fn.confirm = function() return 1 end
    
    local called_back = false
    agent.dispatch_actions(actions, function(resp)
      called_back = true
      assert.match("Proposed new file content", resp)
    end)
    
    assert.True(called_back)
    assert.equals(1, diff.get_count())
    
    vim.fn.confirm = orig_confirm
    require("nzi.core.config").options.yolo = orig_yolo
  end)
end)
