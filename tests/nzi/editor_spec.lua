local assert = require("luassert");
local editor = require("nzi.editor");

describe("AI Surgical Editor", function()
  local test_buf;

  before_each(function()
    test_buf = vim.api.nvim_create_buf(false, true);
  end);

  after_each(function()
    vim.api.nvim_buf_delete(test_buf, { force = true });
  end);

  it("should find an exact block match", function()
    local lines = { "line 1", "line 2", "line 3" };
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, lines);
    
    local s, e = editor.find_block(test_buf, { "line 2" });
    assert.equals(2, s);
    assert.equals(2, e);
  end);

  it("should find a match with normalized indentation", function()
    local lines = { "  local x = 1", "  if true then", "    print(1)", "  end" };
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, lines);
    
    -- Model sends different indentation
    local search = { "local x = 1", "if true then" };
    local s, e = editor.find_block(test_buf, search);
    assert.equals(1, s);
    assert.equals(2, e);
  end);

  it("should find a match with anchor lines (Stage 3)", function()
    local lines = { "function start()", "  -- many lines", "  -- here", "  return end" };
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, lines);
    
    -- Model only sends first and last line of a block
    local search = { "function start()", "return end" };
    local s, e = editor.find_block(test_buf, search);
    assert.equals(1, s);
    assert.equals(4, e);
  end);

  it("should apply a replacement", function()
    local lines = { "old" };
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, lines);
    
    editor.apply(test_buf, 1, 1, { "new" });
    local res = vim.api.nvim_buf_get_lines(test_buf, 0, -1, false);
    assert.equals("new", res[1]);
  end);
end);
