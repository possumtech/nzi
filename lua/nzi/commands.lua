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

  elseif cmd == "stop" then
    local engine = require("nzi.engine");
    if engine.current_job then
      engine.current_job:kill(15);
      engine.current_job = nil;
      modal.set_thinking(false);
      vim.notify("AI: Generation aborted", vim.log.levels.WARN);
    else
      vim.notify("AI: No active job to stop", vim.log.levels.INFO);
    end

  elseif cmd == "yank" then
    local turns = history.get_all();
    if #turns > 0 then
      local last_turn = turns[#turns];
      local assistant_raw = history.strip_line_numbers(last_turn.assistant);
      vim.fn.setreg("+", assistant_raw);
      vim.notify("AI: Last response yanked to + register", vim.log.levels.INFO);
    else
      vim.notify("AI: No history to yank", vim.log.levels.WARN);
    end

  elseif cmd == "active" or cmd == "read" or cmd == "ignore" then
    local bufnr = vim.api.nvim_get_current_buf();
    local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.");
    require("nzi.context").set_state(bufnr, cmd);
    require("nzi.visuals").refresh();
    vim.notify(string.format("AI: Buffer '%s' set to %s", name, cmd), vim.log.levels.INFO);

  elseif cmd == "next" then
    require("nzi.diff").next();

  elseif cmd == "prev" then
    require("nzi.diff").prev();

  elseif cmd == "state" then
    local bufnr = vim.api.nvim_get_current_buf();
    local state = require("nzi.context").get_state(bufnr);
    local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.");
    print(string.format("AI: Buffer '%s' state is '%s'", name, state));

  elseif cmd == "buffers" then
    buffers.open_ui();

  elseif cmd == "tree" or cmd == "Tree" then
    local ctx = require("nzi.context").gather();
    local items = {};
    local show_all = (cmd == "Tree");

    for _, item in ipairs(ctx) do
      if show_all or item.state == "active" or item.state == "read" then
        local state_icon = (item.state == "active" and "(A)" or (item.state == "read" and "(R)" or "(M)"));
        table.insert(items, string.format("%s %s", state_icon, item.name));
      end
    end

    if #items == 0 then
      vim.notify("AI: No files in " .. (show_all and "project" or "active context"), vim.log.levels.WARN);
      return;
    end

    vim.ui.select(items, {
      prompt = "AI Project Universe (" .. (show_all and "All" or "Active/Read") .. "):",
    }, function(choice)
      if choice then
        local path = choice:sub(5);
        vim.cmd("edit " .. path);
      end
    end);

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
