local assert = require("luassert");
local prompts = require("nzi.prompts");

describe("nzi prompts module", function()
  it("should build a standard system prompt", function()
    local parts = {
      global = "Global Rule",
      project = "Project Rule",
      tasks = "- [ ] Task 1"
    };
    local result = prompts.build_system_prompt(parts);
    assert.match("Global Rule", result);
    assert.match("Project Rule", result);
    assert.match("Task 1", result);
  end);

  it("should format context correctly", function()
    local ctx = {
      { name = "test.lua", state = "active", content = "print('hi')" }
    };
    local result = prompts.format_context(ctx);
    assert.match("FILE: test.lua", result, 1, true);
    assert.match("State: active", result, 1, true);
    assert.match("print%('hi'%)", result);
  end);

  it("should build a code modification directive prompt", function()
    local result = prompts.build_directive_prompt(
      "Refactor this",
      "main.lua",
      { global = "Be concise" },
      "FILE: main.lua\n```\nlocal x = 1\n```"
    );
    assert.match("Refactor this", result);
    assert.match("main.lua", result);
    assert.match("Be concise", result);
    assert.match("DO NOT use markdown code blocks", result);
  end);
end);
