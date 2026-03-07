local assert = require("luassert");
local prompt = require("nzi.service.llm.prompt");
local dom = require("nzi.dom.session");
local xml = require("tests.xml_helper");

describe("AI prompts module", function()
  before_each(function()
    dom.clear();
  end)

  it("should build a standard system prompt containing only global rules", function()
    local parts = {
      global = "Global Directive"
    };
    local result = prompt.build_system_prompt(parts, "test-alias");
    assert.truthy(result:find("Global Directive"));
    assert.truthy(result:find("## TURN PROTOCOL"));
  end);

  it("should format context correctly and skip roadmap file", function()
    local cwd = vim.fn.getcwd() .. "/"
    local ctx = {
      { bufnr = 1, name = cwd .. "test.lua", state = "active", content = "print('hi')", size = 10 },
      { bufnr = 2, name = cwd .. "AGENTS.md", state = "active", content = "plan", size = 4 }
    };
    -- roadmap_content must be provided for the tag to appear
    local result = dom.format_context(ctx, false, "Plan: Fix bugs", "AGENTS.md");
    
    assert.truthy(result:find("<agent:file name=\"test.lua\""));
    assert.truthy(result:find("print('hi')", 1, true));
    
    -- Ensure AGENTS.md is NOT in context as a regular file tag
    assert.falsy(result:match("<agent:file name=\"AGENTS.md\""))
    -- But it IS in context as a roadmap tag
    assert.truthy(result:find("<agent:project_roadmap file=\"AGENTS.md\">", 1, true))
    assert.truthy(result:find("Plan: Fix bugs"))
  end);

  it("should build messages from the DOM state", function()
    -- 1. Setup DOM
    dom.add_turn("instruct", "Update val", "<model:summary>Done</model:summary>");
    
    -- 2. Build
    local messages = prompt.build_messages();
    
    -- System + Context + User + Assistant
    assert.equals(4, #messages);
    assert.equals("system", messages[1].role);
    assert.equals("user", messages[3].role);
    assert.equals("assistant", messages[4].role);
    assert.match("Update val", messages[3].content);
  end);

  it("should build a code modification instruct block", function()
    local result = prompt.build_user_block("Refactor this", "main.lua", nil);
    assert.truthy(result:find("Refactor this"));
    assert.truthy(result:find("Target File: main.lua"));
    assert.truthy(result:find("<agent:next_task_suggest"));
  end);
end);
