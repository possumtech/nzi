local config = require("nzi.config");

local M = {};

--- Extract content or reasoning from a single line of OpenAI-compatible SSE data
--- @param line string: A single line from the stream (e.g., "data: {...}")
--- @return table: { content = string, reasoning_content = string, error = string | nil }
local function parse_sse_line(line)
  local result = { content = "", reasoning_content = "", error = nil };
  
  if line:match("^data: %[DONE%]$") then
    return result;
  end
  
  local data = line:match("^data: (.+)$");
  if data then
    local ok, json = pcall(vim.json.decode, data);
    if not ok then return result end

    -- Handle OpenAI / OpenRouter Errors
    if json.error then
      result.error = json.error.message or "Unknown API Error";
      return result;
    end

    if json.choices and json.choices[1] and json.choices[1].delta then
      local delta = json.choices[1].delta;
      
      -- Capture reasoning
      local reasoning = delta.reasoning_content or delta.thought or delta.reasoning;
      if reasoning then
        result.reasoning_content = reasoning;
      end
      
      -- Capture standard content
      local content = delta.content or "";
      if content then
        result.content = content;
      end
    end
  end
  
  return result;
end

--- Execute a model command asynchronously via Pure Lua + Curl (OpenAI Spec)
--- @param messages table: Array of { role = string, content = string }
--- @param callback function: Function to call with the result (success, result_or_error)
--- @param on_stdout function | nil: Optional function called with each chunk of stdout
function M.run(messages, callback, on_stdout)
  local model_cfg = config.get_active_model();
  local opts = config.options;
  
  -- 1. Prepare Request Body
  local body = {
    model = model_cfg.model,
    messages = messages,
    stream = true,
  };

  -- Merge model options (temperature, top_p, etc.)
  if opts.model_options then
    for k, v in pairs(opts.model_options) do
      body[k] = v;
    end
  end

  -- 2. Prepare Headers
  local headers = {
    ["Content-Type"] = "application/json",
  };
  if model_cfg.api_key then
    headers["Authorization"] = "Bearer " .. model_cfg.api_key;
  end

  -- 3. Execute via curl
  local request_body = vim.json.encode(body);
  local f = io.open("last_api_request.json", "w");
  if f then f:write(request_body); f:close(); end

  local cmd = { 
    "curl", "-s", "-N", "-X", "POST", 
    model_cfg.api_base .. "/chat/completions",
    "-d", request_body
  };

  for k, v in pairs(headers) do
    table.insert(cmd, "-H");
    table.insert(cmd, k .. ": " .. v);
  end

  local full_stdout = "";
  local partial_data = ""; -- Buffer for incomplete SSE lines
  local stream_error = nil;

  -- Helper to process whatever is currently in partial_data
  local function process_partial(is_final)
    while true do
      local nl_pos = partial_data:find("\n");
      if not nl_pos then break end
      
      local line = partial_data:sub(1, nl_pos - 1);
      partial_data = partial_data:sub(nl_pos + 1);
      
      if line ~= "" then
        local parsed = parse_sse_line(line);
        if parsed.error then
          stream_error = parsed.error;
          if on_stdout then on_stdout(parsed.error, "error"); end
        end
        if parsed.reasoning_content ~= "" then
          if on_stdout then on_stdout(parsed.reasoning_content, "reasoning_content"); end
        end
        if parsed.content ~= "" then
          full_stdout = full_stdout .. parsed.content;
          if on_stdout then on_stdout(parsed.content, "content"); end
        end
      end
    end

    if is_final and partial_data ~= "" then
      local parsed = parse_sse_line(partial_data);
      if parsed.error then 
        stream_error = parsed.error; 
        if on_stdout then on_stdout(parsed.error, "error"); end
      end
      if parsed.reasoning_content ~= "" then
        if on_stdout then on_stdout(parsed.reasoning_content, "reasoning_content"); end
      end
      if parsed.content ~= "" then
        full_stdout = full_stdout .. parsed.content;
        if on_stdout then on_stdout(parsed.content, "content"); end
      end
      partial_data = "";
    end
  end

  local job = vim.system(cmd, {
    text = true,
    stdout = function(err, data)
      if not data then return end
      partial_data = partial_data .. data;
      process_partial(false);
    end,
  }, function(obj)
    vim.schedule(function()
      process_partial(true);

      if obj.code == 0 and not stream_error then
        callback(true, full_stdout);
      else
        -- If curl failed or we got a mid-stream error, provide clear feedback
        local err_msg = stream_error or obj.stderr or string.format("API failed with code %d", obj.code);
        
        -- Special check for common OpenRouter/OpenAI parameter errors
        if err_msg:match("unsupported_parameter") or err_msg:match("invalid_request_error") then
          err_msg = "Model Compatibility Error: " .. err_msg;
        end
        
        callback(false, err_msg);
      end
    end);
  end);

  return job;
end

return M;
