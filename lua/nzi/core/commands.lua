local config = require("nzi.core.config");
local modal = require("nzi.ui.modal");
local dom_session = require("nzi.dom.session");
local dom_query = require("nzi.dom.query");
local bridge = require("nzi.service.llm.bridge");
local effector = require("nzi.service.vim.effector");
local diff = require("nzi.ui.diff");

local M = {};

--- Execute an internal AI/ command
--- @param cmd string: The subcommand (e.g. "model", "clear")
function M.run(cmd)
  config.log(cmd, "CMD");
  if not cmd or cmd == "" then
    require("nzi.ui.buffers").open_ui();
    return;
  end

  local parts = vim.split(cmd, " ");
  local subcommand = parts[1];
  local args = table.concat(parts, " ", 2);

  if subcommand == "model" then
    if args == "" then
      local model_aliases = {};
      for alias, _ in pairs(config.options.models) do table.insert(model_aliases, alias) end
      table.sort(model_aliases);
      vim.ui.select(model_aliases, { prompt = "Select Active AI Model:" }, function(choice)
        if choice then
          config.options.active_model = choice;
          modal.refresh_session_header();
          config.notify("Active model set to " .. choice, vim.log.levels.INFO);
        end
      end);
    else
      if config.options.models[args] then
        config.options.active_model = args;
        modal.refresh_session_header();
        config.notify("Active model set to " .. args, vim.log.levels.INFO);
      else
        config.notify("Unknown model alias: " .. args, vim.log.levels.ERROR);
      end
    end

  elseif subcommand == "clear" then
    dom_session.clear();
    config.notify("Session cleared.", vim.log.levels.INFO);

  elseif subcommand == "undo" then
    local all = dom_session.get_all();
    if #all > 0 then
      dom_session.delete_after(all[#all].id);
      config.notify("Last turn removed.", vim.log.levels.INFO);
    else
      config.notify("History is empty.", vim.log.levels.WARN);
    end

  elseif subcommand == "status" then
    local model = config.options.active_model;
    local turns = #dom_session.get_all();
    local diffs = diff.get_count();
    config.notify(string.format("Model: %s | Turns: %d | Pending Diffs: %d", model, turns, diffs), vim.log.levels.INFO);

  elseif subcommand == "toggle" then
    modal.toggle();

  elseif subcommand == "stop" then
    if bridge.current_job then
      bridge.current_job:kill(15);
      bridge.finish();
      modal.write("\n[STOPPED BY USER]\n", "error", true);
      config.notify("Generation stopped.", vim.log.levels.WARN);
    else
      bridge.finish();
      config.notify("Reset idle state.", vim.log.levels.INFO);
    end

  elseif subcommand == "yank" then
    local all = dom_session.get_all();
    if #all > 0 then
      local last = all[#all];
      local text = dom_session.strip_line_numbers(last.assistant or "");
      vim.fn.setreg('+', text);
      vim.fn.setreg('"', text);
      config.notify("Last response yanked.", vim.log.levels.INFO);
    end

  elseif subcommand == "next" or subcommand == "prev" then
    local bufs = vim.api.nvim_list_bufs();
    local current = vim.api.nvim_get_current_buf();
    local found = false;
    for i, b in ipairs(bufs) do
      if b == current then
        for j = 1, #bufs do
          local step = (subcommand == "next") and j or -j;
          local next_b = bufs[(i + step - 1) % #bufs + 1];
          if diff.has_pending_diff(next_b) then
            vim.api.nvim_set_current_buf(next_b);
            found = true;
            break;
          end
        end
        break;
      end
    end
    if not found then config.notify("No pending diffs.", vim.log.levels.WARN) end

  elseif subcommand == "accept" then
    diff.accept(vim.api.nvim_get_current_buf());

  elseif subcommand == "reject" then
    diff.reject(vim.api.nvim_get_current_buf());

  elseif subcommand == "yolo" then
    config.options.yolo = not config.options.yolo;
    modal.refresh_session_header();
    local mode = config.options.yolo and "ON (Autopilot)" or "OFF (Safe Mode)";
    config.notify("YOLO Mode is " .. mode, vim.log.levels.INFO);

  elseif subcommand == "reset" then
    dom_session.clear();
    require("nzi.core.queue").clear_instructions();
    config.notify("Full system reset.", vim.log.levels.INFO);

  elseif subcommand == "test" then
    local test_cmd = config.options.test_command or "./test/test.sh";
    if args ~= "" then test_cmd = test_cmd .. " " .. args; end
    effector.run_shell(test_cmd);

  elseif subcommand == "save" or subcommand == "load" then
    local session_name = args ~= "" and args or "default";
    local data_dir = vim.fn.stdpath("data") .. "/nzi/sessions";
    vim.fn.mkdir(data_dir, "p");
    local file_path = data_dir .. "/" .. session_name .. ".xml";

    if subcommand == "save" then
      local f = io.open(file_path, "w");
      if f then
        f:write(dom_session.format());
        f:close();
        config.notify("Session saved to '" .. session_name .. ".xml'", vim.log.levels.INFO);
      end
    else
      local f = io.open(file_path, "r");
      if f then
        local content = f:read("*a");
        f:close();
        if dom_session.hydrate(content) then
          config.notify("Session '" .. session_name .. ".xml' loaded.", vim.log.levels.INFO);
        else
          config.notify("Failed to hydrate session.", vim.log.levels.ERROR);
        end
      else
        config.notify("Session file not found.", vim.log.levels.WARN);
      end
    end

  else
    local context = require("nzi.service.vim.watcher");
    if subcommand == "active" or subcommand == "read" or subcommand == "ignore" or subcommand == "state" then
      local bufnr = vim.api.nvim_get_current_buf();
      if subcommand == "state" then
        config.notify("Buffer State: " .. context.get_state(bufnr), vim.log.levels.INFO);
      else
        context.set_state(bufnr, subcommand);
        config.notify("Buffer set to " .. subcommand, vim.log.levels.INFO);
      end
    else
      config.notify("Unknown command: " .. subcommand, vim.log.levels.WARN);
    end
  end
end

return M;
