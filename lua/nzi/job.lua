local config = require("nzi.config");

local M = {};

--- Execute a model command asynchronously
--- @param prompt string: The full prompt (including system prompt and context)
--- @param callback function: Function to call with the result (success, result_or_error)
--- @param on_stdout function | nil: Optional function called with each chunk of stdout
function M.run(prompt, callback, on_stdout)
  local opts = config.options;
  
  -- Clone the base command table
  local cmd = {};
  for _, part in ipairs(opts.model_cmd) do
    table.insert(cmd, part);
  end

  -- Append arguments
  table.insert(cmd, "--model");
  table.insert(cmd, opts.default_model);

  if opts.api_base then
    table.insert(cmd, "--api_base");
    table.insert(cmd, opts.api_base);
  end

  if opts.api_key then
    table.insert(cmd, "--api_key");
    table.insert(cmd, opts.api_key);
  end

  -- Use vim.system for modern, clean async job management
  local job = vim.system(cmd, {
    stdin = prompt,
    text = true, -- Handle as text, not bytes
    stdout = function(err, data)
      if data and on_stdout then
        -- Handle tagged streaming data
        -- Note: Chunks might be partial, but for these specific markers
        -- we check each chunk for the presence of the tag.
        local type = "model";
        local clean_data = data;
        
        if data:match("<NZ_THOUGHT>") then
          type = "thought";
          clean_data = data:gsub("<NZ_THOUGHT>", "");
        elseif data:match("<NZ_CONTENT>") then
          type = "model";
          clean_data = data:gsub("<NZ_CONTENT>", "");
        end
        
        if clean_data ~= "" then
          on_stdout(clean_data, type);
        end
      end
    end,
  }, function(obj)
    -- Callback is called when the process exits
    if obj.code == 0 then
      callback(true, obj.stdout);
    else
      -- Provide useful error feedback including stderr
      local err_msg = string.format("Job failed with code %d: %s", obj.code, obj.stderr or "unknown error");
      callback(false, err_msg);
    end
  end);

  return job;
end

return M;
