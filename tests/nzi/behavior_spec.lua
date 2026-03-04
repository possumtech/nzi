local assert = require("luassert");
local engine = require("nzi"); -- This triggers setup and command registration

describe("AI behavioral commands", function()
  before_each(function()
    require("nzi").setup({});
  end);

  it("should execute AI command and modify buffer for shell directives", function()
    local bufnr = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_set_current_buf(bufnr);
    
    -- Inject a shell directive in buffer
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "ai! echo 'SUCCESS'" });
    vim.api.nvim_win_set_cursor(0, {1, 0});

    -- Call the actual user command
    vim.cmd("AI");

    -- Wait up to 10s for the async shell execution
    local success = vim.wait(10000, function()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
      for _, line in ipairs(lines) do
        if line:match("SUCCESS") then return true end
      end
      return false
    end);

    assert.is_true(success, "Shell output 'SUCCESS' never appeared in buffer.");
    
    vim.api.nvim_buf_delete(bufnr, { force = true });
  end);

  it("should handle the 'AI !' shell shortcut correctly and show in modal with tags", function()
    local bufnr = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_set_current_buf(bufnr);
    
    local modal = require("nzi.modal");
    modal.clear();

    -- Execute the shortcut command
    vim.cmd("AI ! echo 'BANG_SUCCESS'");

    -- Wait up to 10s
    local success = vim.wait(10000, function()
      local lines = vim.api.nvim_buf_get_lines(modal.bufnr, 0, -1, false);
      local text = table.concat(lines, "\n");
      return text:match("<agent:shell_output>.-BANG_SUCCESS") ~= nil
    end);

    assert.is_true(success, "Modal never showed BANG_SUCCESS with correct tags.");

    local lines = vim.api.nvim_buf_get_lines(modal.bufnr, 0, -1, false);
    local text = table.concat(lines, "\n");
    assert.match("<agent:shell_output>", text, 1, true);
    assert.match("BANG_SUCCESS", text, 1, true);    vim.api.nvim_buf_delete(bufnr, { force = true });
  end);

  it("should handle direct command-line arguments as directives", function()
    local bufnr = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_set_current_buf(bufnr);
    
    -- Directives are now treated as handle_question
    local engine_mod = require("nzi.engine");
    local question_spy = require("luassert.spy").on(engine_mod, "handle_question");
    
    -- Simulate :AI :Hello World
    vim.cmd("AI :Hello World");

    assert.spy(question_spy).was_called_with("Hello World", true);
    
    question_spy:revert();
    vim.api.nvim_buf_delete(bufnr, { force = true });
  end);
end);
