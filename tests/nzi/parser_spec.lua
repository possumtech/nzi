local assert = require("luassert");
local parser = require("nzi.parser");

describe("AI parser", function()
  it("should parse AI: directives", function()
    local type, content = parser.parse_line("-- AI: Hello world");
    assert.are.equal("directive", type);
    assert.are.equal("Hello world", content);
  end);

  it("should parse AI? questions", function()
    local type, content = parser.parse_line("  // AI? What is this?");
    assert.are.equal("question", type);
    assert.are.equal("What is this?", content);
  end);

  it("should parse AI! shell commands", function()
    local type, content = parser.parse_line("# AI! ls -la");
    assert.are.equal("shell", type);
    assert.are.equal("ls -la", content);
  end);

  it("should parse AI/ internal commands", function()
    local type, content = parser.parse_line("AI/undo");
    assert.are.equal("command", type);
    assert.are.equal("undo", content);
  end);

  it("should be case-insensitive", function()
    local t1, c1 = parser.parse_line("-- ai: lowercase");
    assert.are.equal("directive", t1);
    assert.are.equal("lowercase", c1);
  end);

  it("should clean up closing comment tags", function()
    local type, content = parser.parse_line("/* AI: refactor this */");
    assert.are.equal("directive", type);
    assert.are.equal("refactor this", content);
  end);

  it("should return nil for non-AI lines", function()
    local type, content = parser.parse_line("local x = 1");
    assert.is_nil(type);
    assert.is_nil(content);
  end);
end);
