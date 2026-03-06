local assert = require("luassert");
local modal = require("nzi.ui.modal");

describe("AI modal structural integrity", function()
  before_each(function()
    modal.clear();
  end);

  it("should maintain valid sections across multiple transitions", function()
    modal.write("System Message", "system", false);
    modal.write("User Question", "user", false);
    modal.write("Assistant Answer", "assistant", false);
    
    local bufnr = modal.bufnr;
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
    local text = table.concat(lines, "\n");
    
    assert.match("System Message", text);
    assert.match("User Question", text);
    assert.match("Assistant Answer", text);
  end);

  it("should correctly handle append=false mid-interaction", function()
    modal.write("Turn 1", "user", false);
    modal.write("Reply 1", "assistant", false);
    modal.write("Turn 2", "user", false); -- append=false triggers new telemetry
    
    local lines = vim.api.nvim_buf_get_lines(modal.bufnr, 0, -1, false);
    local text = table.concat(lines, "\n");
    
    assert.match("Turn 1", text);
    assert.match("Reply 1", text);
    assert.match("Turn 2", text);
  end);

  it("should produce clean output even with complex multi-line content", function()
    modal.write("Line 1\nJust some text\nLine 2", "user", false);
    modal.write("Code block\n```lua\nlocal x = 1\n```", "assistant", true);
    
    local lines = vim.api.nvim_buf_get_lines(modal.bufnr, 0, -1, false);
    local text = table.concat(lines, "\n");
    assert.match("local x = 1", text);
  end);
end);
