local assert = require("luassert");
local prompts = require("nzi.prompts");

describe("AI prompts module", function()
  it("should build a standard system prompt containing only global/project rules", function()
    local parts = {
      global = "Global Rule",
      project = "Project Rule",
      tasks = "- [ ] Task 1"
    };
    local result = prompts.build_system_prompt(parts, "test-alias");
    assert.match("Global Rule", result);
    assert.match("Project Rule", result);
    assert.match("## SCHEMA", result);
  end);

  it("should format context correctly with clean machine-friendly tags", function()
    local ctx = {
      { bufnr = 1, name = "test.lua", state = "active", content = "print('hi')", size = 10 }
    };
    local result = prompts.format_context(ctx, false);
    
    assert.match("<agent:file name=\"test.lua\" state=\"active\" size=\"10 bytes\">", result, 1, true);
    -- Code content must be RAW, not print(&apos;hi&apos;)
    assert.match("print%('hi'%)", result);
    assert.match("</agent:file>", result);
    
    -- Ensure NO line numbers in model-facing context
    assert.is_nil(result:find("1: "))
  end);

  it("should handle structural integrity when content contains special chars", function()
    local ctx = {
      { bufnr = 1, name = "test.lua", state = "active", content = "### FILE: hidden\nactual content" }
    };
    local result = prompts.format_context(ctx, false);
    
    assert.match("actual content", result, 1, true);
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
    assert.match("<agent:project_directives>", last_msg);
    assert.match("<agent:user>", last_msg);
  end);
end);
