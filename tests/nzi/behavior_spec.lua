local assert = require("luassert");
local engine = require("nzi"); -- This triggers setup and command registration

describe("nzi behavioral commands", function()
  before_each(function()
    require("nzi").setup({
      litellm_cmd = "echo", -- Mock CLI
    });
  end);

  it("should execute Nzi command and modify buffer for shell directives", function()
    local bufnr = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_set_current_buf(bufnr);
    
    -- Inject a shell directive
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "nzi! echo 'SUCCESS'" });
    vim.api.nvim_win_set_cursor(0, {1, 0});

    -- Call the actual user command
    vim.cmd("Nzi");

    -- Wait for the async vim.system to return and vim.schedule to run
    vim.wait(1000, function()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
      return #lines > 1 and lines[2] == "SUCCESS";
    end);

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
    assert.are.equal("nzi! echo 'SUCCESS'", lines[1]);
    assert.are.equal("SUCCESS", lines[2]);
    
    vim.api.nvim_buf_delete(bufnr, { force = true });
  end);

  it("should handle Nzi! (bang) correctly as a shell shortcut", function()
    local bufnr = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_set_current_buf(bufnr);
    
    -- Simulate the logic called by the command
    -- line_idx defaults to cursor line (1)
    require("nzi.shell").run("echo 'BANG_SUCCESS'", bufnr);

    vim.wait(1000, function()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
      -- shell.run inserts *after* the line_idx
      return #lines > 1 and lines[2] == "BANG_SUCCESS";
    end);

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
    assert.are.equal("BANG_SUCCESS", lines[2]);
    
    vim.api.nvim_buf_delete(bufnr, { force = true });
  end);

  it("should handle direct command-line arguments as directives with : prefix", function()
    local bufnr = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_set_current_buf(bufnr);
    
    local directive_mod = require("nzi.directive");
    local directive_spy = require("luassert.spy").on(directive_mod, "run");
    
    -- Simulate the command handler logic for :Nzi :Hello World
    require("nzi.directive").run("Hello World", bufnr, false);

    assert.spy(directive_spy).was_called_with("Hello World", bufnr, false);
    
    directive_spy:revert();
    vim.api.nvim_buf_delete(bufnr, { force = true });
  end);
end);
