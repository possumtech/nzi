local config = require("nzi.core.config");
local history = require("nzi.dom.session");

local M = {};

--- Run a shell command and optionally capture output to context
--- @param command string: The command to execute
--- @param bufnr number: The buffer to inject output into (optional)
--- @param line number: The line to inject at (optional)
--- @param silent boolean: If true, don't notify
--- @param signal_type string: The type to project as (default "shell")
function M.run_shell(command, bufnr, line, silent, signal_type)
  local s_type = signal_type or "shell";
  
  -- 1. PRE-EXECUTION GATE: Confirm command execution
  local should_run = config.options.yolo;
  if not should_run then
    local choice = vim.fn.confirm("Execute " .. s_type .. " command: " .. command .. "?", "&Yes\n&No", 2);
    should_run = (choice == 1);
  end

  if not should_run then
    if not silent then config.notify(s_type .. " execution cancelled by user.", "warn") end
    -- We still add a "denied" turn so the Assistant knows why it didn't get results
    history.add_turn({
      type = s_type,
      status = "fail",
      command = command,
      content = "User denied execution."
    }, "<status level='error'>Execution denied by user.</status>");
    return;
  end

  if not silent then
    config.notify("Running: " .. command, "info");
  end

  vim.system(vim.split(command, " "), { text = true }, function(obj)
    vim.schedule(function()
      if obj.code == 0 then
        local output = obj.stdout or "";
        
        -- 2. Inject into buffer if requested (no gate for this, as it's a specific UI request)
        if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
          local lines = vim.split(output, "\n");
          local l = line or vim.api.nvim_win_get_cursor(0)[1];
          vim.api.nvim_buf_set_lines(bufnr, l, l, false, lines);
        end

        -- 3. POST-EXECUTION GATE: Add to Context?
        local should_add = config.options.yolo;
        local remark = nil;
        
        if not should_add then
          local choice = vim.fn.confirm("Add " .. s_type .. " output to AI Context?", "&Yes\n&No\n&Remark", 1);
          if choice == 1 then
            should_add = true;
          elseif choice == 3 then
            should_add = true;
            -- Block to get remark
            remark = vim.fn.input("Remark: ");
          end
        end

        if should_add then
          -- Add to DOM via Python SSOT (using structured table for directive projection)
          history.add_turn({
            type = s_type,
            status = "pass",
            command = command,
            content = output,
            instruction = remark -- This maps to the tail text in Python's _project_user_data
          }, "<" .. s_type .. ">\n" .. output .. "</" .. s_type .. ">");
          if not silent then config.notify(s_type .. " output added to context.", "info") end
        else
          if not silent then config.notify(s_type .. " output ignored.", "info") end
        end

      else
        local err = (obj.stderr and obj.stderr ~= "") and obj.stderr or "Command exited with code " .. obj.code;
        config.notify(s_type .. " Error: " .. err, "error");
        
        -- Failed commands also get a gate for context addition
        local should_add = config.options.yolo;
        local remark = nil;

        if not should_add then
          local choice = vim.fn.confirm("Add " .. s_type .. " error to AI Context?", "&Yes\n&No\n&Remark", 1);
          if choice == 1 then
            should_add = true;
          elseif choice == 3 then
            should_add = true;
            remark = vim.fn.input("Remark: ");
          end
        end

        if should_add then
          -- INTERNAL RULE: 'ralph' is projected as 'test' to the model
          local projected_type = (s_type == "ralph") and "test" or s_type;

          history.add_turn({
            type = projected_type,
            status = "fail",
            command = command,
            content = err,
            instruction = remark
          }, "<status level='error'>\n" .. err .. "\n</status>");

          -- Automated Retry Loop (Ralph/Test)
          if config.options.yolo and (s_type == "test" or s_type == "ralph") then
            vim.schedule(function()
              require("nzi.service.llm.bridge").run_loop("Diagnose and resolve the test failure.", "instruct");
            end);
          end
        end
      end
    end);
  end);
end

return M;
