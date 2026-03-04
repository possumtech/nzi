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

  -- Execute the directive on the current line, selection, or command bar
  vim.api.nvim_create_user_command("Nzi", function(opts)
    local bufnr = vim.api.nvim_get_current_buf();

    -- 1. Handle Bang Shortcut (:Nzi! ls)
    if opts.bang then
      require("nzi.shell").run(opts.args or "", bufnr);
      return;
    end

    -- 2. Handle Command-line Arguments with strict prefixing
    if opts.args and opts.args ~= "" then
      local first_char = opts.args:sub(1,1);
      local content = opts.args:sub(2);

      if first_char == ":" then
        require("nzi.directive").run(content, bufnr, false);
      elseif first_char == "?" then
        engine.handle_question(content, false);
      elseif first_char == "!" then
        require("nzi.shell").run(content, bufnr);
      elseif first_char == "/" then
        require("nzi.commands").run(content);
      else
        vim.notify("nzi: Command arguments must start with :, ?, !, or /", vim.log.levels.ERROR);
      end
      return;
    end

    -- 3. Fallback: Interpolated Directive in Buffer (Line or Range)
    if opts.range > 0 then
      engine.execute_range(opts.line1, opts.line2);
    else
      engine.execute_current_line();
    end
  end, { 
    range = true, 
    bang = true, 
    nargs = "*",
    desc = "Execute nzi: [ :?|/! args ] or line/selection" 
  });
  -- Toggle the read-only modal window
  vim.api.nvim_create_user_command("NziToggle", function()
    modal.toggle();
  end, { desc = "Toggle the nzi read-only modal" });

  -- Status bar (command-line) versions of directives
  vim.api.nvim_create_user_command("NziQuestion", function(opts)
    engine.handle_question(opts.args, false); -- Global: no LSP
  end, { nargs = 1, desc = "Ask nzi a question" });

  vim.api.nvim_create_user_command("NziDirective", function(opts)
    local bufnr = vim.api.nvim_get_current_buf();
    require("nzi.directive").run(opts.args, bufnr, false); -- Global: no LSP
  end, { nargs = 1, desc = "Send a directive to nzi" });

  vim.api.nvim_create_user_command("NziShell", function(opts)
    local bufnr = vim.api.nvim_get_current_buf();
    local cursor = vim.api.nvim_win_get_cursor(0);
    require("nzi.shell").run(opts.args, bufnr, cursor[1]);
  end, { nargs = 1, desc = "Run shell command and inject output" });

  -- Placeholder for subsequent commands (NziStatus, etc.)
end

return M;
