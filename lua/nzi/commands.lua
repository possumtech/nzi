local config = require("nzi.config");
local modal = require("nzi.modal");
local history = require("nzi.history");
local buffers = require("nzi.buffers");

local M = {};

--- Execute an internal AI/ command
--- @param command_str string: The command and its arguments (e.g., "model local_llm")
function M.run(command_str)
  local parts = vim.split(command_str, " ");
  local cmd = parts[1];

  if cmd == "model" then
    local alias = parts[2];
    if not alias then
      local active = config.options.active_model;
      print("Current model: " .. active);
      return;
    end

    if config.options.models[alias] then
      config.options.active_model = alias;
      vim.notify("AI: Switched to model '" .. alias .. "'", vim.log.levels.INFO);
    else
      vim.notify("AI: Unknown model alias: " .. alias, vim.log.levels.ERROR);
    end

  elseif cmd == "clear" then
    history.clear();
    modal.clear();
    vim.notify("AI: History and modal cleared", vim.log.levels.INFO);

  elseif cmd == "status" then
    local active = config.options.active_model;
    local model_cfg = config.get_active_model();
    print("AI Status:");
    print("  Active Model: " .. active);
    print("  API Base:     " .. model_cfg.api_base);
    print("  Model Name:   " .. model_cfg.model);
    print("  Turns:        " .. #history.get_all());

  elseif cmd == "toggle" then
    modal.toggle();

  elseif cmd == "buffers" then
    buffers.open_ui();

  elseif cmd == "config" then
    print(vim.inspect(config.options));
    
  else
    vim.notify("AI: Unknown internal command: " .. cmd, vim.log.levels.WARN);
  end
end

return M;
