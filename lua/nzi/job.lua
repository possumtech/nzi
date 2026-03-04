local config = require("nzi.config");

local M = {};

--- Execute a model command asynchronously
--- @param prompt string: The full prompt (including system prompt and context)
--- @param callback function: Function to call with the result (success, result_or_error)
function M.run(prompt, callback)
  local opts = config.options;
  
  -- Build the command (e.g., litellm --model gpt-4 --prompt "...")
  -- This structure expects the CLI to accept the prompt via stdin or a flag.
  -- We default to stdin for maximum compatibility.
  local cmd = {
    opts.litellm_cmd,
    "--model",
    opts.default_model,
  };

  -- Use vim.system for modern, clean async job management
  local job = vim.system(cmd, {
    stdin = prompt,
    text = true, -- Handle as text, not bytes
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
