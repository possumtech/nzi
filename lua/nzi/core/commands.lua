local config = require("nzi.core.config");
local modal = require("nzi.ui.modal");
local dom_session = require("nzi.dom.session");
local bridge = require("nzi.service.llm.bridge");
local effector = require("nzi.service.vim.effector");
local diff = require("nzi.ui.diff");

local M = {};

-- ACTIONS: The core logic functions mapped by name
M.actions = {};

function M.actions.model(args)
  if not args or args == "" then
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
end

function M.actions.clear()
  dom_session.clear();
  config.notify("Session cleared.", vim.log.levels.INFO);
end

function M.actions.undo()
  local all = dom_session.get_all();
  if #all > 0 then
    dom_session.delete_after(all[#all].id);
    config.notify("Last turn removed.", vim.log.levels.INFO);
  else
    config.notify("History is empty.", vim.log.levels.WARN);
  end
end

function M.actions.toggle()
  modal.toggle();
end

function M.actions.stop()
  if bridge.current_job then
    bridge.current_job:kill(15);
    bridge.finish();
    modal.write("\n[STOPPED BY USER]\n", "error", true);
    config.notify("Generation stopped.", vim.log.levels.WARN);
  else
    bridge.finish();
    config.notify("Reset idle state.", vim.log.levels.INFO);
  end
end

function M.actions.save(name)
  local session_name = (name and name ~= "") and name or "default";
  local data_dir = vim.fn.stdpath("data") .. "/nzi/sessions";
  vim.fn.mkdir(data_dir, "p");
  local file_path = data_dir .. "/" .. session_name .. ".xml";
  local f = io.open(file_path, "w");
  if f then
    f:write(dom_session.format());
    f:close();
    config.notify("Session saved to '" .. session_name .. ".xml'", vim.log.levels.INFO);
  end
end

function M.actions.load(name)
  local session_name = (name and name ~= "") and name or "default";
  local data_dir = vim.fn.stdpath("data") .. "/nzi/sessions";
  local file_path = data_dir .. "/" .. session_name .. ".xml";
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

function M.actions.test(args)
  local test_cmd = config.options.test_command or "./test/test.sh";
  if args and args ~= "" then test_cmd = test_cmd .. " " .. args; end
  effector.run_shell(test_cmd, nil, nil, false, "test");
end

function M.actions.ralph(args)
  local ralph_cmd = config.options.ralph_command or "./test/ralph.sh";
  if args and args ~= "" then ralph_cmd = ralph_cmd .. " " .. args; end
  effector.run_shell(ralph_cmd, nil, nil, false, "ralph");
end

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

  if M.actions[subcommand] then
    M.actions[subcommand](args);
  else
    -- Fallback for context management and others
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
