local assert = require("luassert")
local agent = require("nzi.service.llm.actions")
local diff = require("nzi.ui.diff")
local context = require("nzi.service.vim.watcher")
local history = require("nzi.dom.session")
local xml_helper = require("tests.xml_helper")

describe("6. Protocol & Actions", function()
  before_each(function()
    history.clear()
    diff.active_views = {}
    context.states = {}
  end)

  it("should process <model:read> and add file to active context", function()
    local actions = {
      { name = "read", attr = "file=\"dummy.lua\"", content = "" }
    }
    
    local orig_resolve = require("nzi.dom.resolver").resolve
    require("nzi.dom.resolver").resolve = function(f) return f, nil end
    
    local called_back = false
    agent.dispatch_actions(actions, "instruct", function(resp)
      called_back = true
      assert.match("<agent:context", resp)
    end)
    
    assert.True(called_back)
    local bufnr = vim.fn.bufadd("dummy.lua")
    assert.equals("active", context.get_state(bufnr))
    
    require("nzi.dom.resolver").resolve = orig_resolve
  end)

  it("should process <model:delete> and register a pending deletion", function()
    local actions = {
      { name = "delete", attr = "file=\"delete_me.lua\"", content = "" }
    }
    
    local orig_resolve = require("nzi.dom.resolver").resolve
    require("nzi.dom.resolver").resolve = function(f) return f, nil end
    
    local orig_yolo = require("nzi.core.config").options.yolo
    require("nzi.core.config").options.yolo = false
    
    -- Manually add the turn to history as engine would do
    history.add("instruct", "<agent:user>delete file</agent:user>", "<model:delete file='delete_me.lua'/>")

    local called_back = false
    agent.dispatch_actions(actions, "instruct", function(resp)
      called_back = true
      assert.match("Proposed deletion", resp)
    end)
    
    assert.True(called_back)
    -- Derive from XML
    assert.equals(1, diff.get_count())
    
    require("nzi.core.config").options.yolo = orig_yolo
    require("nzi.dom.resolver").resolve = orig_resolve
  end)

  it("AI/accept should confirm deletion and AI/reject should discard it", function()
    -- 1. Setup pending deletion in XML
    history.add("instruct", "<agent:user>delete file</agent:user>", "<model:delete file='target.lua'/>")
    assert.equals(1, diff.get_count())
    
    -- 2. Reject
    local mock_bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(mock_bufnr, "target.lua")
    
    diff.reject(mock_bufnr)
    
    -- Verification: History should now have a status='denied' turn
    local turns = history.get_all()
    local last_turn = turns[#turns]
    assert.match("status='denied'", last_turn.user)
    
    -- and count should be 0 because it's resolved
    -- In some test environments, we might need a tiny nudge or just check immediately if synchronous
    local success = false
    for i = 1, 10 do
      if diff.get_count() == 0 then
        success = true
        break
      end
      vim.cmd("sleep 10m")
    end
    assert.True(success, "Diff count did not drop to 0 after reject")
    
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
    
    -- Setup history
    history.add("instruct", "<agent:user>create</agent:user>", "<model:create file='new_file.lua'>print('hello')</model:create>")

    local called_back = false
    agent.dispatch_actions(actions, "instruct", function(resp)
      called_back = true
      assert.match("Proposed new file content", resp)
    end)
    
    assert.True(called_back)
    assert.equals(1, diff.get_count())
    
    vim.fn.confirm = orig_confirm
    require("nzi.core.config").options.yolo = orig_yolo
  end)
end)
