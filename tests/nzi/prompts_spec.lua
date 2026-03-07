local assert = require("luassert");
local prompts = require("nzi.engine.prompts");
local xml = require("tests.xml_helper");

describe("AI prompts module", function()
  it("should build a standard system prompt containing only global rules", function()
    local parts = {
      global = "Global Directive",
      project = "Project State"
    };
    local result = prompts.build_system_prompt(parts, "test-alias");
    assert.truthy(result:find("Global Directive"));
    assert.truthy(result:find("## TURN PROTOCOL"));
    -- Project State should NOT be in system prompt rules
    assert.is_nil(result:find("Project State"))
  end);

  it("should format context correctly and skip AGENTS.md", function()
    local ctx = {
      { bufnr = 1, name = "test.lua", state = "active", content = "print('hi')", size = 10 },
      { bufnr = 2, name = "AGENTS.md", state = "active", content = "plan", size = 4 }
    };
    local result = prompts.format_context(ctx, false);
    
    assert.truthy(result:find("<agent:file name=\"test.lua\""));
    assert.truthy(result:find("print('hi')", 1, true));
    assert.truthy(result:find("</agent:file>"));
    
    -- Ensure AGENTS.md is NOT in context
    assert.is_nil(result:find("AGENTS.md"))
  end);

  it("should correctly extract the first unchecked task (next_task_suggest)", function()
    local old_gather = prompts.gather;
    prompts.gather = function()
      return { 
        project = "Checklist:\n- [x] Task 1\n- [ ] Task 2\n- [ ] Task 3",
        next_task_suggest = "Task 2"
      }
    end
    
    local result, _, _, _, turn_block = prompts.build_messages("test", "ask", nil, false);
    local last_msg = result[#result].content;
    
    assert.truthy(last_msg:find("<agent:next_task_suggest>"));
    assert.truthy(last_msg:find("Task 2"));
    
    -- Full session validation
    local session_wrap = string.format([[
<agent:turn id="0" model="system"><agent:user>pre</agent:user></agent:turn>
<agent:turn id="1" model="unknown">
%s
</agent:turn>
]], last_msg);
    xml.assert_valid(session_wrap);

    prompts.gather = old_gather;
  end);

  it("should build a code modification instruct prompt", function()
    local result, _, _, ctx, turn_block = prompts.build_messages(
      "Refactor this",
      "instruct",
      "main.lua",
      false
    );
    assert.is_table(result);
    assert.is_table(ctx);
    
    local last_msg = result[#result].content;
    assert.truthy(last_msg:find("Refactor this"));
    assert.truthy(last_msg:find("main.lua"));
    assert.truthy(last_msg:find("<agent:project_state>"));
    assert.truthy(last_msg:find("<agent:user>"));

    -- Full session validation
    local session_wrap = string.format([[
<agent:turn id="0" model="system"><agent:user>pre</agent:user></agent:turn>
<agent:turn id="1" model="unknown">
%s
</agent:turn>
]], last_msg);
    xml.assert_valid(session_wrap);
  end);
end);
