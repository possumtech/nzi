local M = {};

--- Run a shell command and interactively ask to add to context
--- @param command string: The shell command to run
--- @param bufnr number: The buffer where the command was triggered
--- @param line_idx number | nil: The 1-based line index
--- @param inject boolean | nil: Whether to inject output into the buffer
function M.run(command, bufnr, line_idx, inject)
  local modal = require("nzi.modal");
  local history = require("nzi.history");
  
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

        -- 3. INTERACTIVE PROMPT: Add to Context?
        modal.write("Add this output to AI Context? [y]es / [n]o", "system", false);
        
        local m_buf = modal.bufnr;
        local function cleanup_keys()
          pcall(vim.keymap.del, "n", "y", { buffer = m_buf });
          pcall(vim.keymap.del, "n", "n", { buffer = m_buf });
          modal.pending_cleanup = nil;
          modal.close_tag(); -- Close system prompt tag after choice
        end

        -- Register cleanup with modal so subsequent commands can "Auto-No"
        modal.pending_cleanup = function()
          modal.write("(Prompt cancelled by new interaction)", "system", true);
          cleanup_keys();
        end

        vim.keymap.set("n", "y", function()
          history.add("shell", "Executed command: " .. command, obj.stdout or "(no output)");
          modal.write("Added to context.", "system", false);
          cleanup_keys();
        end, { buffer = m_buf, silent = true });

        vim.keymap.set("n", "n", function()
          modal.write("Ignored.", "system", false);
          cleanup_keys();
        end, { buffer = m_buf, silent = true });

      else
        local err = (obj.stderr and obj.stderr ~= "") and obj.stderr or "Command exited with code " .. obj.code;
        modal.write(err, "error", false);
        modal.close_tag();
        vim.notify("AI!: " .. err, vim.log.levels.ERROR);
      end
    end);
  end);
end

return M;
