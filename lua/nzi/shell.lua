local M = {};

--- Run a shell command and inject its output into the buffer
--- @param command string: The shell command to run
--- @param bufnr number: The buffer where the output should be injected
--- @param line_idx number | nil: The 1-based line index (defaults to cursor line)
function M.run(command, bufnr, line_idx)
  local modal = require("nzi.modal");
  modal.open();
  modal.write(command .. "\n", "user", false);

  if not line_idx then
    line_idx = vim.api.nvim_win_get_cursor(0)[1];
  end

  -- Execute via sh -c to allow for pipes and redirects
  vim.system({ "sh", "-c", command }, { text = true }, function(obj)
    -- Schedule the buffer modification back on the main thread
    vim.schedule(function()
      if obj.code == 0 then
        local output_lines = vim.split(obj.stdout, "\n");
        modal.write(obj.stdout, "shell", false);
        
        -- Clean up trailing newline from command output
        if #output_lines > 0 and output_lines[#output_lines] == "" then
          table.remove(output_lines);
        end
        
        -- Insert the output lines directly after the directive
        if #output_lines > 0 then
          vim.api.nvim_buf_set_lines(bufnr, line_idx, line_idx, false, output_lines);
        end
      else
        -- Notify the user of failures via the sign column or notifications
        local err = obj.stderr ~= "" and obj.stderr or "Command exited with code " .. obj.code;
        modal.write("ERROR: " .. err .. "\n", "system", false);
        vim.notify("nzi! failed: " .. err, vim.log.levels.ERROR);
      end
    end);
  end);
end

return M;
