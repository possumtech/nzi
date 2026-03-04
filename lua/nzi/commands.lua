local config = require("nzi.config");
local modal = require("nzi.modal");
local history = require("nzi.history");
local buffers = require("nzi.buffers");

local M = {};

--- Execute an internal AI/ command
--- @param command_str string: The command and its arguments
function M.run(command_str)
  local parts = vim.split(command_str, " ");
  local cmd = parts[1];

  if cmd == "model" then
    local alias = parts[2];
    if not alias then
      -- List all aliases in a clean way
      local model_list = {};
      for name, _ in pairs(config.options.models) do
        table.insert(model_list, name);
      end
      table.sort(model_list);
      
      print("Available AI Models:");
      for _, name in ipairs(model_list) do
        local active = (name == config.options.active_model) and "*" or " ";
        print(string.format(" %s %s", active, name));
      end
      return;
    end

    if config.options.models[alias] then
      config.options.active_model = alias;
      vim.notify("AI: Switched to model '" .. alias .. "'", vim.log.levels.INFO);
    else
      vim.notify("AI: Unknown model alias: " .. alias, vim.log.levels.ERROR);
    end

  elseif cmd == "set" then
    local key = parts[2];
    local val = parts[3];
    if not key or not val then
      print("Current Options: " .. vim.inspect(config.options.model_options));
      return;
    end
    
    local num_val = tonumber(val);
    config.options.model_options[key] = num_val or val;
    vim.notify(string.format("AI: %s set to %s", key, val), vim.log.levels.INFO);

  elseif cmd == "add" then
    local alias, model, url, key = parts[2], parts[3], parts[4], parts[5];
    if not alias or not model or not url then
      print("Usage: AI/add <alias> <model_name> <api_base_url> [api_key]");
      return;
    end
    config.options.models[alias] = {
      model = model,
      api_base = url,
      api_key = key
    };
    vim.notify("AI: Added model alias '" .. alias .. "'", vim.log.levels.INFO);

  elseif cmd == "undo" then
    if history.pop() then
      vim.notify("AI: Removed last interaction from history", vim.log.levels.INFO);
    else
      vim.notify("AI: History is already empty", vim.log.levels.WARN);
    end

  elseif cmd == "clear" then
    history.clear();
    modal.clear();
    vim.notify("AI: History and modal cleared", vim.log.levels.INFO);

  elseif cmd == "status" then
    local active = config.options.active_model;
    local model_cfg = config.get_active_model();
    local opts = config.options.model_options;
    print("AI Status:");
    print("  Active Model: " .. active);
    print("  Model Name:   " .. model_cfg.model);
    print("  Temperature:  " .. (opts.temperature or "default"));
    print("  Turns:        " .. #history.get_all());

  elseif cmd == "toggle" then
    modal.toggle();

  elseif cmd == "buffers" then
    buffers.open_ui();

  elseif cmd == "install" then
    local info = debug.getinfo(M.run);
    local script_dir = info.source:match("@?(.*/)")
    local plugin_root = vim.fn.fnamemodify(script_dir .. "../../", ":p");
    local venv_path = plugin_root .. ".venv";
    local python_bin = venv_path .. "/bin/python";

    vim.notify("AI: Installing LiteLLM environment in " .. venv_path .. "...", vim.log.levels.INFO);
    
    local cmd_str = string.format("cd %s && python3 -m venv .venv && .venv/bin/python -m pip install litellm", plugin_root);
    
    vim.fn.jobstart(cmd_str, {
      on_exit = function(_, code)
        if code == 0 then
          vim.notify("AI: LiteLLM installation successful! Update your config to use: " .. python_bin, vim.log.levels.INFO);
          config.options.python_cmd = { python_bin };
        else
          vim.notify("AI: Installation failed (code " .. code .. "). Check your python3 and pip installation.", vim.log.levels.ERROR);
        end
      end,
      stdout_buffered = true,
      stderr_buffered = true,
    });

  elseif cmd == "config" then
    print(vim.inspect(config.options));
    
  else
    vim.notify("AI: Unknown internal command: " .. cmd, vim.log.levels.WARN);
  end
end

return M;
