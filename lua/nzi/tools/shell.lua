local M = {};

--- Run a shell command and interactively ask to add to context
--- @param command string: The shell command to run
--- @param bufnr number: The buffer where the command was triggered
--- @param line_idx number | nil: The 1-based line index
--- @param inject boolean | nil: Whether to inject output into the buffer
function M.run(command, bufnr, line_idx, inject)
  local history = require("nzi.dom.session");
  local config = require("nzi.core.config");
  
  bufnr = bufnr or vim.api.nvim_get_current_buf();
  if inject == nil then inject = true; end

  if not line_idx then
    line_idx = vim.api.nvim_win_get_cursor(0)[1];
  end

  config.notify("Running: " .. command, "info");

  -- Execute via sh -c to allow for pipes and redirects
  vim.system({ "sh", "-c", command }, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code == 0 then
        local output = obj.stdout or "";
        
        -- 1. Inject into source buffer only if requested and safe
        if inject and vim.api.nvim_buf_is_valid(bufnr) then
          local output_lines = vim.split(output, "\n");
          if #output_lines > 0 and output_lines[#output_lines] == "" then
            table.remove(output_lines);
          end
          if #output_lines > 0 then
            vim.api.nvim_buf_set_lines(bufnr, line_idx, line_idx, false, output_lines);
          end
        end

        -- 2. INTERACTIVE PROMPT: Add to Context?
        local choice = vim.fn.confirm("Add shell output to AI Context?", "&Yes\n&No", 2);
        if choice == 1 then
          -- Add to DOM via Python SSOT
          history.add_turn("shell", "Executed command: " .. command, "<shell>\n" .. output .. "</shell>");
          config.notify("Shell output added to context.", "info");
        else
          config.notify("Shell output ignored.", "info");
        end

      else
        local err = (obj.stderr and obj.stderr ~= "") and obj.stderr or "Command exited with code " .. obj.code;
        config.notify("Shell Error: " .. err, "error");
        
        local choice = vim.fn.confirm("Add shell error to AI Context?", "&Yes\n&No", 1);
        if choice == 1 then
          history.add_turn("error", "Failed command: " .. command, "<status level='error'>\n" .. err .. "\n</status>");
        end
      end
    end);
  end);
end

return M;
