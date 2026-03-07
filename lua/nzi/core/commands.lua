local config = require("nzi.core.config");
local modal = require("nzi.ui.modal");
local history = require("nzi.context.history");
local buffers = require("nzi.ui.buffers");
local diff = require("nzi.ui.diff");

local M = {};

--- Execute an internal AI/ command
--- @param cmd string: The subcommand (e.g. "model", "clear")
function M.run(cmd)
  config.log(cmd, "CMD");
  if not cmd or cmd == "" then
    buffers.open_ui();
    return;
  end

  local parts = vim.split(cmd, " ");
  local subcommand = parts[1];
  local args = table.concat(parts, " ", 2);

  if subcommand == "model" then
    if args == "" then
      -- Show model selection menu
      local model_aliases = {};
      for alias, _ in pairs(config.options.models) do table.insert(model_aliases, alias) end
      table.sort(model_aliases);
      
      vim.ui.select(model_aliases, {
        prompt = "Select Active AI Model:",
      }, function(choice)
        if choice then
          config.options.active_model = choice;
          config.notify("Active model set to " .. choice, vim.log.levels.INFO);
        end
      end);
    else
      if config.options.models[args] then
        config.options.active_model = args;
        config.notify("Active model set to " .. args, vim.log.levels.INFO);
      else
        config.notify("Unknown model alias: " .. args, vim.log.levels.ERROR);
      end
    end

  elseif subcommand == "clear" then
    history.clear();
    modal.clear();
    config.notify("History and modal cleared.", vim.log.levels.INFO);

  elseif subcommand == "undo" then
    if history.pop() then
      config.notify("Last turn removed from history.", vim.log.levels.INFO);
    else
      config.notify("History is empty.", vim.log.levels.WARN);
    end

  elseif subcommand == "status" then
    local model = config.options.active_model;
    local turns = #history.get_all();
    local diffs = diff.get_count();
    config.notify(string.format("Model: %s | Turns: %d | Pending Diffs: %d", model, turns, diffs), vim.log.levels.INFO);

  elseif subcommand == "toggle" then
    modal.toggle();

  elseif subcommand == "stop" then
    local engine = require("nzi.engine.engine");
    local queue = require("nzi.core.queue");
    if engine.current_job then
      engine.current_job:kill(15);
      engine.current_job = nil;
      engine.is_busy = false;
      require("nzi.ui.visuals").stop_thinking();
      modal.set_thinking(false);
      modal.write("\n[STOPPED BY USER]\n", "error", true);

      -- Clear any pending ACTIONS from the model
      queue.clear_actions();

      -- AUTO-DRAIN: Move to the next user instruction if any
      local next_work = queue.pop_instruction();
      if next_work then
        config.notify("Skipping to next queued instruction...", vim.log.levels.INFO);
        vim.schedule(function()
          engine.run_loop(next_work.instruction, next_work.type, false, next_work.target_file, next_work.selection);
        end);
      else
        config.notify("Generation stopped.", vim.log.levels.WARN);
      end
    else
      -- Force reset state even if no job handle exists
      engine.is_busy = false;
      require("nzi.ui.visuals").stop_thinking();
      modal.set_thinking(false);
      config.notify("Reset idle state.", vim.log.levels.INFO);
    end

  elseif subcommand == "yank" then
    local all = history.get_all();
    if #all > 0 then
      local last = all[#all];
      local text = history.strip_line_numbers(last.assistant or "");
      vim.fn.setreg('+', text);
      vim.fn.setreg('"', text);
      config.notify("Last response yanked to clipboard.", vim.log.levels.INFO);
    else
      config.notify("Nothing to yank.", vim.log.levels.WARN);
    end

  elseif subcommand == "next" then
    -- Navigate to next pending diff
    local bufs = vim.api.nvim_list_bufs();
    local current = vim.api.nvim_get_current_buf();
    local found = false;
    for i, b in ipairs(bufs) do
      if b == current then
        for j = 1, #bufs do
          local next_b = bufs[(i + j - 1) % #bufs + 1];
          if diff.pending_diffs[next_b] then
            vim.api.nvim_set_current_buf(next_b);
            found = true;
            break;
          end
        end
        break;
      end
    end
    if not found then config.notify("No pending diffs found.", vim.log.levels.WARN) end

  elseif subcommand == "prev" then
    -- Navigate to previous pending diff
    local bufs = vim.api.nvim_list_bufs();
    local current = vim.api.nvim_get_current_buf();
    local found = false;
    for i, b in ipairs(bufs) do
      if b == current then
        for j = 1, #bufs do
          local prev_b = bufs[(i - j - 1) % #bufs + 1];
          if diff.pending_diffs[prev_b] then
            vim.api.nvim_set_current_buf(prev_b);
            found = true;
            break;
          end
        end
        break;
      end
    end
    if not found then config.notify("No pending diffs found.", vim.log.levels.WARN) end

  elseif subcommand == "accept" then
    local bufnr = vim.api.nvim_get_current_buf();
    local name = vim.api.nvim_buf_get_name(bufnr);
    local short_name = vim.fn.fnamemodify(name, ":.");
    diff.accept(bufnr);
    require("nzi.core.queue").add_passive(string.format("<agent:ack status='success' tool='edit' file='%s'>User accepted and saved changes.</agent:ack>", short_name));

  elseif subcommand == "reject" then
    local bufnr = vim.api.nvim_get_current_buf();
    local name = vim.api.nvim_buf_get_name(bufnr);
    local short_name = vim.fn.fnamemodify(name, ":.");
    diff.reject(bufnr);
    require("nzi.core.queue").add_passive(string.format("<agent:ack status='denied' tool='edit' file='%s'>User rejected the proposed changes.</agent:ack>", short_name));

  elseif subcommand == "yolo" then
    config.options.yolo = not config.options.yolo;
    local mode = config.options.yolo and "ON (Autopilot)" or "OFF (Safe Mode)";
    config.notify("YOLO Mode is " .. mode, vim.log.levels.INFO);

  elseif subcommand == "ralph" then
    -- AI/ralph runs the test with ralph active for this run
    local test_cmd = config.options.test_command or "./run_tests.sh";
    if args ~= "" then
      test_cmd = test_cmd .. " " .. args;
    end
    
    local engine = require("nzi.engine.engine");
    local agent = require("nzi.protocol.agent");
    modal.open();
    
    -- Temporarily set ralph to true for this operation
    local old_ralph = config.options.ralph;
    config.options.ralph = true;
    
    agent.verify_state(function(failure_response)
      config.options.ralph = old_ralph; -- Restore
      if failure_response then
        engine.run_loop(failure_response, "ask", false);
      end
    end, test_cmd);

  elseif subcommand == "reset" then
    local queue = require("nzi.core.queue");
    history.clear();
    modal.clear();
    diff.pending_diffs = {};
    -- We can't easily clear all context states without iterating all bufs
    require("nzi.context.context").states = {};
    
    -- FLUSH ALL QUEUES
    queue.clear();
    queue.clear_actions();
    
    config.notify("Session and queues fully reset.", vim.log.levels.INFO);

  elseif subcommand == "test" then
    local test_cmd = config.options.test_command or "./run_tests.sh";
    if args ~= "" then
      test_cmd = test_cmd .. " " .. args;
    end
    require("nzi.tools.shell").run(test_cmd);

  elseif subcommand == "save" or subcommand == "load" then
    local session_name = args ~= "" and args or "default";
    local data_dir = vim.fn.stdpath("data") .. "/nzi/sessions";
    vim.fn.mkdir(data_dir, "p");
    local file_path = data_dir .. "/" .. session_name .. ".json";

    if subcommand == "save" then
      local data = {
        history = history.get_all(),
        model = config.options.active_model
      };
      local f = io.open(file_path, "w");
      if f then
        f:write(vim.json.encode(data));
        f:close();
        config.notify("Session saved to '" .. session_name .. "'", vim.log.levels.INFO);
      else
        config.notify("Failed to save session.", vim.log.levels.ERROR);
      end
    else
      -- load
      local f = io.open(file_path, "r");
      if f then
        local content = f:read("*a");
        f:close();
        local ok, data = pcall(vim.json.decode, content);
        if ok and data then
          history.clear();
          for _, turn in ipairs(data.history or {}) do
            history.add(turn.type, history.strip_line_numbers(turn.user), history.strip_line_numbers(turn.assistant));
          end
          if data.model and config.options.models[data.model] then
            config.options.active_model = data.model;
          end
          config.notify("Session '" .. session_name .. "' loaded (" .. #history.get_all() .. " turns)", vim.log.levels.INFO);
        else
          config.notify("Failed to parse session file.", vim.log.levels.ERROR);
        end
      else
        config.notify("Session '" .. session_name .. "' not found.", vim.log.levels.WARN);
      end
    end

  elseif subcommand == "config" then
    print(vim.inspect(config.options));
    
  else
    -- Fallback: treat as buffer context commands if not a known subcommand
    local context = require("nzi.context.context");
    if subcommand == "active" or subcommand == "read" or subcommand == "ignore" or subcommand == "state" then
      local bufnr = vim.api.nvim_get_current_buf();
      if subcommand == "state" then
        config.notify("Buffer State: " .. context.get_state(bufnr), vim.log.levels.INFO);
      else
        context.set_state(bufnr, subcommand);
        config.notify("Buffer set to " .. subcommand, vim.log.levels.INFO);
      end
    else
      config.notify("Unknown internal command: " .. subcommand, vim.log.levels.WARN);
    end
  end
end

return M;
