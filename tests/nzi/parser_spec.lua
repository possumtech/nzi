local assert = require("luassert");
local parser = require("nzi.parser");

describe("AI parser", function()
  it("should parse ai: directives", function()
    local type, content = parser.parse_line("-- ai: Hello world");
    assert.are.equal("directive", type);
    assert.are.equal("Hello world", content);
  end);

  it("should parse ai? questions", function()
    local type, content = parser.parse_line("  // ai? What is this?");
    assert.are.equal("question", type);
    assert.are.equal("What is this?", content);
  end);

  it("should parse ai! shell commands", function()
    local type, content = parser.parse_line("# ai! ls -la");
    assert.are.equal("shell", type);
    assert.are.equal("ls -la", content);
  end);

  it("should parse ai/ internal commands", function()
    local type, content = parser.parse_line("ai/undo");
    assert.are.equal("command", type);
    assert.are.equal("undo", content);
  end);

  it("should clean up closing comment tags", function()
    local type, content = parser.parse_line("/* ai: refactor this */");
    assert.are.equal("directive", type);
    assert.are.equal("refactor this", content);
  end);

  it("should return nil for non-AI lines", function()
    local type, content = parser.parse_line("local x = 1");
    assert.is_nil(type);
    assert.is_nil(content);
  end);
end);
