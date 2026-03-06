local assert = require("luassert");
local prompts = require("nzi.engine.prompts");
local xml_helper = require("tests.xml_helper");

describe("AI prompts module", function()
  it("should build a standard system prompt containing only global rules", function()
    local parts = {
      global = "Global Directive",
      project = "Project State"
    };
    local result = prompts.build_system_prompt(parts, "test-alias");
    assert.match("Global Directive", result);
    assert.match("## TURN PROTOCOL", result);
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
    
    -- SYSTEMATIC XML VALIDATION
    local ok, err = xml_helper.validate_xml(result)
    assert.is_true(ok, "Context XML is invalid: " .. (err or ""))

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
    
    assert.match("<agent:next_task_suggest>", last_msg);
    assert.match("Task 2", last_msg);
    
    -- SYSTEMATIC XML VALIDATION
    local ok, err = xml_helper.validate_xml(last_msg)
    assert.is_true(ok, "Full prompt XML is invalid: " .. (err or ""))
    
    local ok2, err2 = xml_helper.validate_xml(turn_block)
    assert.is_true(ok2, "Turn block XML is invalid: " .. (err2 or ""))

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
    assert.match("Refactor this", last_msg);
    assert.match("main.lua", last_msg);
    assert.match("<agent:project_state>", last_msg);
    assert.match("<agent:user>", last_msg);

    -- SYSTEMATIC XML VALIDATION
    local ok, err = xml_helper.validate_xml(last_msg)
    assert.is_true(ok, "Instruct prompt XML is invalid: " .. (err or ""))
  end);
end);
