local assert = require("luassert");
local parser = require("nzi.parser");

describe("nzi parser", function()
  it("should parse nzi: directives", function()
    local type, content = parser.parse_line("-- nzi: Hello world");
    assert.are.equal("directive", type);
    assert.are.equal("Hello world", content);
  end);

  it("should parse nzi? questions", function()
    local type, content = parser.parse_line("  // nzi? What is this?");
    assert.are.equal("question", type);
    assert.are.equal("What is this?", content);
  end);

  it("should parse nzi! shell commands", function()
    local type, content = parser.parse_line("# nzi! ls -la");
    assert.are.equal("shell", type);
    assert.are.equal("ls -la", content);
  end);

  it("should parse nzi/ internal commands", function()
    local type, content = parser.parse_line("nzi/undo");
    assert.are.equal("command", type);
    assert.are.equal("undo", content);
  end);

  it("should clean up closing comment tags", function()
    local type, content = parser.parse_line("/* nzi: refactor this */");
    assert.are.equal("directive", type);
    assert.are.equal("refactor this", content);
  end);

  it("should return nil for non-nzi lines", function()
    local type, content = parser.parse_line("local x = 1");
    assert.is_nil(type);
    assert.is_nil(content);
  end);
end);
