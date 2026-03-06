local assert = require("luassert");
local parser = require("nzi.engine.parser");

describe("AI parser", function()
  it("should parse :AI: instruct at BOL", function()
    local type, content = parser.parse_line(":AI: Hello world");
    assert.are.equal("instruct", type);
    assert.are.equal("Hello world", content);
  end);

  it("should parse :AI? ask at BOL", function()
    local type, content = parser.parse_line(":AI? What is this?");
    assert.are.equal("ask", type);
    assert.are.equal("What is this?", content);
  end);

  it("should NOT parse :AI: if preceded by whitespace or comments", function()
    assert.is_nil(parser.parse_line("  :AI: fail"));
    assert.is_nil(parser.parse_line("-- :AI: fail"));
    assert.is_nil(parser.parse_line("// :AI: fail"));
  end);

  it("should parse :AI! shell commands at BOL", function()
    local type, content = parser.parse_line(":AI! ls -la");
    assert.are.equal("run", type);
    assert.are.equal("ls -la", content);
  end);

  it("should parse :AI/ internal commands at BOL", function()
    local type, content = parser.parse_line(":AI/undo");
    assert.are.equal("internal", type);
    assert.are.equal("undo", content);
  end);

  it("should be case-insensitive", function()
    local t1, c1 = parser.parse_line(":ai: lowercase");
    assert.are.equal("instruct", t1);
    assert.are.equal("lowercase", c1);
  end);

  it("should clean up closing comment tags", function()
    local type, content = parser.parse_line(":AI: refactor this */");
    assert.are.equal("instruct", type);
    assert.are.equal("refactor this", content);
  end);

  it("should return nil for non-AI lines", function()
    local type, content = parser.parse_line("local x = 1");
    assert.is_nil(type);
    assert.is_nil(content);
  end);

  it("should NOT parse :AI: in the middle of a line (e.g. after code)", function()
    local type, content = parser.parse_line("local x = 1 -- :AI: this is a comment, not a instruct");
    assert.is_nil(type, "Should not parse :AI: if preceded by code");
  end);
end);
