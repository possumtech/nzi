local M = {};

--- Run a shell command and inject its output into the modal (and optionally buffer)
--- @param command string: The shell command to run
--- @param bufnr number: The buffer where the command was triggered
--- @param line_idx number | nil: The 1-based line index
--- @param inject boolean | nil: Whether to inject output into the buffer (defaults to true)
function M.run(command, bufnr, line_idx, inject)
  local modal = require("nzi.modal");
  if inject == nil then inject = true; end
  
  -- Open modal and show what we are running
  modal.open();
  modal.write("Running: " .. command, "system", false);

  if not line_idx then
    line_idx = vim.api.nvim_win_get_cursor(0)[1];
  end

  -- Execute via sh -c to allow for pipes and redirects
  vim.system({ "sh", "-c", command }, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code == 0 then
        -- 1. Dump output to modal (The Chat)
        if obj.stdout and obj.stdout ~= "" then
          modal.write(obj.stdout, "shell", false);
        else
          modal.write("(Command returned no output)", "system", false);
        end
        
        -- 2. Inject into source buffer only if requested and safe
        if inject and bufnr ~= modal.bufnr then
          local output_lines = vim.split(obj.stdout or "", "\n");
          if #output_lines > 0 and output_lines[#output_lines] == "" then
            table.remove(output_lines);
          end
          if #output_lines > 0 then
            vim.api.nvim_buf_set_lines(bufnr, line_idx, line_idx, false, output_lines);
          end
        end
      else
        local err = (obj.stderr and obj.stderr ~= "") and obj.stderr or "Command exited with code " .. obj.code;
        modal.write("ERROR: " .. err, "system", false);
        vim.notify("AI!: " .. err, vim.log.levels.ERROR);
      end
    end);
  end);
end

return M;
