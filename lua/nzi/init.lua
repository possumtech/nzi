local config = require("nzi.config");
local buffers = require("nzi.buffers");
local engine = require("nzi.engine");
local modal = require("nzi.modal");

local M = {};

--- Setup function for nzi plugin
--- @param opts table | nil: Configuration options
function M.setup(opts)
  config.setup(opts);
  
  -- Register User Commands
  
  -- Manage buffer context states (active, read, ignore)
  vim.api.nvim_create_user_command("NziBuffers", function()
    buffers.open();
  end, { desc = "Manage nzi buffer context" });

  -- Execute the directive on the current line or selection
  vim.api.nvim_create_user_command("Nzi", function(opts)
    if opts.range > 0 then
      engine.execute_range(opts.line1, opts.line2);
    else
      engine.execute_current_line();
    end
  end, { range = true, desc = "Execute nzi directive on line or selection" });

  -- Toggle the read-only modal window
  vim.api.nvim_create_user_command("NziToggle", function()
    modal.toggle();
  end, { desc = "Toggle the nzi read-only modal" });

  -- Status bar (command-line) versions of directives
  vim.api.nvim_create_user_command("NziQuestion", function(opts)
    engine.handle_question(opts.args);
  end, { nargs = 1, desc = "Ask nzi a question" });

  vim.api.nvim_create_user_command("NziDirective", function(opts)
    local bufnr = vim.api.nvim_get_current_buf();
    directive.run(opts.args, bufnr);
  end, { nargs = 1, desc = "Send a directive to nzi" });

  vim.api.nvim_create_user_command("NziShell", function(opts)
    local bufnr = vim.api.nvim_get_current_buf();
    local cursor = vim.api.nvim_win_get_cursor(0);
    require("nzi.shell").run(opts.args, bufnr, cursor[1]);
  end, { nargs = 1, desc = "Run shell command and inject output" });

  -- Placeholder for subsequent commands (NziStatus, etc.)
end

return M;
