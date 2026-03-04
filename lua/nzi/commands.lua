local config = require("nzi.config");

local M = {};

--- Execute an internal nzi/ command
--- @param command_str string: The command and its arguments (e.g., "model gpt-4")
function M.run(command_str)
  local parts = vim.split(command_str, "%s+");
  local cmd = parts[1];
  
  if cmd == "undo" then
    vim.cmd("undo");
  elseif cmd == "model" then
    local new_model = parts[2];
    if new_model then
      config.options.default_model = new_model;
      vim.notify("nzi: Switched to model " .. new_model, vim.log.levels.INFO);
    else
      vim.notify("nzi: Current model is " .. config.options.default_model, vim.log.levels.INFO);
    end
  elseif cmd == "config" then
    -- Open the config module in a new buffer or modal?
    -- For now, just print the current config
    print(vim.inspect(config.options));
  else
    vim.notify("nzi: Unknown internal command: " .. cmd, vim.log.levels.WARN);
  end
end

return M;
