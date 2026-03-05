local context = require("nzi.context");
local config = require("nzi.config");

local M = {};

--- Execute a grep search across the project universe (Active + Read files)
--- @param pattern string: The search pattern
--- @return string: The formatted <agent:grep> output
function M.grep(pattern)
  local ctx_list = context.gather();
  local results = {};
  
  for _, item in ipairs(ctx_list) do
    -- Only grep files the model is allowed to "see" (Active or Read)
    -- We skip 'map' (skeletons) as the model needs to 'read' those first to grep them,
    -- OR we can allow grepping skeletons if we want it to be more powerful?
    -- Decision: Let's allow grepping everything in the universe (Active/Read/Map) 
    -- but NOT Ignore. This makes discovery much faster.
    if item.state ~= "ignore" then
      local path = item.name;
      local full_path = vim.fn.getcwd() .. "/" .. path;
      
      -- If it's a buffer, use buffer lines for accuracy (unsaved changes)
      local lines = {};
      if item.bufnr and vim.api.nvim_buf_is_loaded(item.bufnr) then
        lines = vim.api.nvim_buf_get_lines(item.bufnr, 0, -1, false);
      elseif vim.fn.filereadable(full_path) == 1 then
        lines = vim.fn.readfile(full_path);
      end
      
      for i, line in ipairs(lines) do
        if line:find(pattern, 1, true) then
          table.insert(results, string.format("%s:%d:%s", path, i, line));
        end
      end
    end
  end
  
  if #results == 0 then
    return "No matches found in project universe.";
  end
  
  return table.concat(results, "\n");
end

--- Execute a shell/env command with user permission
--- @param command string: The shell command
--- @param is_yolo boolean: Whether to skip permission prompts
--- @return string | nil: The output if the user wants to return it to context, else nil
function M.shell(command, is_yolo)
  local confirmed = is_yolo;
  
  if not confirmed then
    local choice = vim.fn.confirm("AI requests shell command: " .. command, "&Yes\n&No", 2);
    confirmed = (choice == 1);
  end
  
  if not confirmed then
    return "User denied shell command execution.";
  end
  
  local output = vim.fn.systemlist(command);
  local result_text = table.concat(output, "\n");
  
  local send_to_context = is_yolo;
  if not send_to_context then
    local choice = vim.fn.confirm("Send command output back to AI context?", "&Yes\n&No", 1);
    send_to_context = (choice == 1);
  end
  
  if send_to_context then
    return result_text;
  end
  
  return nil; -- Command ran, but result stays local
end

--- Present a multiple-choice question to the user using vim.ui.select
--- @param content string: The question and checkbox list from the model
--- @param callback function: Called with the final user answer string
function M.choice(content, callback)
  -- 1. Extract the question and the options from the markdown checkboxes
  local question = content:match("^(.-)%- %[ %]") or "Please choose an option:";
  local options = {};
  for option in content:gmatch("%- %[ %]%s*(.-)\r?\n") do
    table.insert(options, option);
  end
  -- Handle final option without newline
  if #options == 0 then
    for option in content:gmatch("%- %[ %]%s*(.-)$") do
      table.insert(options, option);
    end
  end
  
  -- 2. Append the mandatory "Open response" option
  table.insert(options, "None of the above (Respond with text)");
  
  -- 3. Show the UI
  vim.ui.select(options, {
    prompt = question:gsub("^%s*", ""),
  }, function(choice, index)
    if not choice then
      callback("User cancelled selection.");
      return;
    end
    
    if index == #options then
      -- User chose "Open response"
      vim.ui.input({ prompt = "Your response: " }, function(input)
        callback(input or "User provided no text response.");
      end);
    else
      callback(choice);
    end
  end);
end

return M;
