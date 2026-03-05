local assert = require("luassert");
local prompts = require("nzi.prompts");

describe("AI prompts module", function()
  it("should build a standard system prompt containing only global rules", function()
    local parts = {
      global = "Global Directive",
      project = "Project State"
    };
    local result = prompts.build_system_prompt(parts, "test-alias");
    assert.match("Global Directive", result);
    assert.match("## SCHEMA", result);
    -- Project State should NOT be in system prompt rules
    assert.is_nil(result:find("Project State"))
  end);

  it("should format context correctly and skip AGENTS.md", function()
    local ctx = {
      { bufnr = 1, name = "test.lua", state = "active", content = "print('hi')", size = 10 },
      { bufnr = 2, name = "AGENTS.md", state = "active", content = "plan", size = 4 }
    };
    local result = prompts.format_context(ctx, false);
    
    assert.match("<agent:file name=\"test.lua\" state=\"active\" size=\"10 bytes\">", result, 1, true);
    assert.match("print%('hi'%)", result);
    assert.match("</agent:file>", result);
    
    -- Ensure AGENTS.md is NOT in context
    assert.is_nil(result:find("AGENTS.md"))
  end);

  it("should correctly extract the first unchecked task (next_task_suggest)", function()
    -- Mocking filesystem and nvim calls in gather() might be complex, 
    -- but we can test the regex logic if we extract it or mock vim.fn.readfile
    -- For now, let's verify that the messages contain next_task_suggest if present.
    
    -- We can temporarily mock prompts.gather() for this test
    local old_gather = prompts.gather;
    prompts.gather = function()
      return { 
        project = "Checklist:\n- [x] Task 1\n- [ ] Task 2\n- [ ] Task 3",
        next_task_suggest = "Task 2"
      }
    end
    
    local result = prompts.build_messages("test", "question", nil, false);
    local last_msg = result[#result].content;
    
    assert.match("<agent:next_task_suggest>", last_msg);
    assert.match("Task 2", last_msg);
    
    prompts.gather = old_gather;
  end);

  it("should preserve full AGENTS.md content in gather()", function()
    local mock_content = {
      "Arbitrary Content",
      "- [ ] Next Task",
      "More Content"
    };
    
    local old_readfile = vim.fn.readfile;
    local old_filereadable = vim.fn.filereadable;
    vim.fn.readfile = function() return mock_content end;
    vim.fn.filereadable = function() return 1 end;
    
    local parts = prompts.gather();
    
    assert.match("Arbitrary Content", parts.project);
    assert.match("- %[ %] Next Task", parts.project);
    assert.match("More Content", parts.project);
    assert.equal("Next Task", parts.next_task_suggest);
    
    vim.fn.readfile = old_readfile;
    vim.fn.filereadable = old_filereadable;
  end);

  it("should build a code modification directive prompt", function()
    local result, _, _, ctx = prompts.build_messages(
      "Refactor this",
      "directive",
      "main.lua",
      false
    );
    assert.is_table(result);
    assert.is_table(ctx);
    -- Message 1: System (Rules)
    -- Message 2: System/User (Context)
    -- Message 3: User (New Directive)
    local last_msg = result[#result].content;
    assert.match("Refactor this", last_msg);
    assert.match("main.lua", last_msg);
    assert.match("<agent:project_state>", last_msg);
    assert.match("<agent:user>", last_msg);
  end);
end);
