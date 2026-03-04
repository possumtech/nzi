local assert = require("luassert");
local engine = require("nzi.engine");
local parser = require("nzi.parser");

describe("AI engine dispatcher", function()
  it("should warn if no directive is found on current line", function()
    -- Create a clean buffer with no directives
    local bufnr = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_set_current_buf(bufnr);
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local x = 1" });
    
    local spy = require("luassert.spy");
    local notify_spy = spy.on(vim, "notify");
    
    engine.execute_current_line();
    
    assert.spy(notify_spy).was_called_with("No AI directive found on current line.", vim.log.levels.WARN);
    
    vim.api.nvim_buf_delete(bufnr, { force = true });
    notify_spy:revert();
  end);

  it("should find and execute shell directive in range", function()
    local bufnr = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_set_current_buf(bufnr);
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "ai! echo 'hello'", "line 2" });
    
    -- Mock the shell run
    local shell = require("nzi.shell");
    local shell_spy = require("luassert.spy").on(shell, "run");
    
    engine.execute_range(1, 2);
    
    assert.spy(shell_spy).was_called_with("echo 'hello'", bufnr, 1);
    
    shell_spy:revert();
    vim.api.nvim_buf_delete(bufnr, { force = true });
  end);
end);
