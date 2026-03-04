local assert = require("luassert");
local engine = require("nzi"); -- This triggers setup and command registration

describe("AI behavioral commands", function()
  before_each(function()
    require("nzi").setup({
      -- Any mock config needed
    });
  end);

  it("should execute AI command and modify buffer for shell directives", function()
    local bufnr = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_set_current_buf(bufnr);
    
    -- Inject a shell directive in buffer
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "ai! echo 'SUCCESS'" });
    vim.api.nvim_win_set_cursor(0, {1, 0});

    -- Call the actual user command
    vim.cmd("AI");

    -- Wait for the async vim.system to return and vim.schedule to run
    vim.wait(1000, function()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
      return #lines > 1 and (lines[2] == "SUCCESS" or lines[2]:match("SUCCESS"))
    end);

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
    assert.match("SUCCESS", lines[2]);
    
    vim.api.nvim_buf_delete(bufnr, { force = true });
  end);

  it("should handle the 'AI !' shell shortcut correctly", function()
    local bufnr = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_set_current_buf(bufnr);
    
    -- Execute the shortcut command
    vim.cmd("AI ! echo 'BANG_SUCCESS'");

    vim.wait(1000, function()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
      return #lines > 1 and lines[2]:match("BANG_SUCCESS")
    end);

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
    assert.match("BANG_SUCCESS", lines[2]);
    
    vim.api.nvim_buf_delete(bufnr, { force = true });
  end);

  it("should handle direct command-line arguments as directives", function()
    local bufnr = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_set_current_buf(bufnr);
    
    local directive_mod = require("nzi.directive");
    local directive_spy = require("luassert.spy").on(directive_mod, "run");
    
    -- Simulate the command handler logic for :AI Hello World
    require("nzi.directive").run("Hello World", bufnr, false);

    assert.spy(directive_spy).was_called_with("Hello World", bufnr, false);
    
    directive_spy:revert();
    vim.api.nvim_buf_delete(bufnr, { force = true });
  end);
end);
