local config = require("nzi.core.config");
local history = require("nzi.dom.session");

local M = {};

--- Run a shell command and optionally capture output to context
--- @param command string: The command to execute
--- @param bufnr number: The buffer to inject output into (optional)
--- @param line number: The line to inject at (optional)
--- @param silent boolean: If true, don't notify
function M.run_shell(command, bufnr, line, silent)
  if not silent then
    config.notify("Running: " .. command, "info");
  end

  vim.system(vim.split(command, " "), { text = true }, function(obj)
    vim.schedule(function()
      if obj.code == 0 then
        local output = obj.stdout or "";
        
        -- 1. Inject into buffer if requested
        if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
          local lines = vim.split(output, "\n");
          local l = line or vim.api.nvim_win_get_cursor(0)[1];
          vim.api.nvim_buf_set_lines(bufnr, l, l, false, lines);
        end

        -- 2. INTERACTIVE PROMPT: Add to Context?
        local should_add = config.options.yolo;
        if not should_add then
          local choice = vim.fn.confirm("Add shell output to AI Context?", "&Yes\n&No", 2);
          should_add = (choice == 1);
        end

        if should_add then
          -- Add to DOM via Python SSOT (using schema-compliant <shell> tag)
          history.add_turn("shell", "Executed command: " .. command, "<shell>\n" .. output .. "</shell>");
          if not silent then config.notify("Shell output added to context.", "info") end
        else
          if not silent then config.notify("Shell output ignored.", "info") end
        end

      else
        local err = (obj.stderr and obj.stderr ~= "") and obj.stderr or "Command exited with code " .. obj.code;
        config.notify("Shell Error: " .. err, "error");
        
        local should_add = config.options.yolo;
        if not should_add then
          local choice = vim.fn.confirm("Add shell error to AI Context?", "&Yes\n&No", 1);
          should_add = (choice == 1);
        end

        if should_add then
          history.add_turn("error", "Failed command: " .. command, "<status level='error'>\n" .. err .. "\n</status>");
        end
      end
    end);
  end);
end

return M;
