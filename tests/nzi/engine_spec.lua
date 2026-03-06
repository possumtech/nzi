local assert = require("luassert");
local engine = require("nzi.engine.engine");
local shell = require("nzi.tools.shell");

describe("AI engine dispatcher", function()
  it("should warn if no instruct is found on current line", function()
    -- Create a clean buffer with no instructs
    local bufnr = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_set_current_buf(bufnr);
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local x = 1" });
    
    -- In engine.lua it calls print()
    local original_print = _G.print;
    local printed_msg = nil;
    _G.print = function(msg) printed_msg = msg; end
    
    engine.execute_current_line();
    
    _G.print = original_print;
    assert.are.equal("No AI instruct found on current line.", printed_msg);
    
    vim.api.nvim_buf_delete(bufnr, { force = true });
  end);

  it("should find and execute shell instruct in range", function()
    local bufnr = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_set_current_buf(bufnr);
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { ":ai! echo 'hello'", "line 2" });
    
    -- Mock the shell run DIRECTLY on the module that engine.lua required
    local original_run = shell.run;
    local run_args = nil;
    shell.run = function(...) run_args = {...}; end
    
    engine.execute_range(1, 2);
    
    shell.run = original_run;
    assert.is_not_nil(run_args);
    assert.are.equal("echo 'hello'", run_args[1]);
    
    vim.api.nvim_buf_delete(bufnr, { force = true });
  end);
end);
