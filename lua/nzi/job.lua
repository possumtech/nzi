local config = require("nzi.config");

local M = {};

--- Extract content or reasoning from a single line of OpenAI-compatible SSE data
--- @param line string: A single line from the stream (e.g., "data: {...}")
--- @return table: { content = string, reasoning_content = string, error = string | nil }
local function parse_sse_line(line)
  local result = { content = "", reasoning_content = "", error = nil };
  
  -- Skip HTTP status line and other non-data lines
  if line:match("^HTTP_STATUS:") or line:match("^%d%d%d$") or line:match("^data: %[DONE%]$") then
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
      
      -- Capture reasoning (OpenAI O1/O3 style or OpenRouter thought)
      local reasoning = delta.reasoning_content or delta.thought or delta.reasoning;
      if reasoning then
        result.reasoning_content = reasoning;
      end
      
      -- Capture standard content
      local content = delta.content;
      if content and content ~= vim.NIL then
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

  -- Merge model options (temperature, top_p, etc.) and filter out nils
  if config.options.model_options then
    for k, v in pairs(config.options.model_options) do
      if v ~= nil then body[k] = v; end
    end
  end

  -- 2. Prepare Headers
  local headers = {
    ["Content-Type"] = "application/json",
    ["HTTP-Referer"] = opts.referer, 
    ["X-Title"] = opts.title,        
  };
  if model_cfg.api_key then
    headers["Authorization"] = "Bearer " .. model_cfg.api_key;
  end

  -- 3. Execute via curl
  local request_body = vim.json.encode(body);
  local f = io.open("last_api_request.json", "w");
  if f then f:write(request_body); f:close(); end

  local cmd = { 
    "curl", "-s", "-N", "--no-buffer", "-X", "POST", 
    "-w", "\\nHTTP_STATUS:%{http_code}", -- Write status code with prefix
    model_cfg.api_base .. "/chat/completions",
    "-d", "@-" -- Read from stdin
  };

  for k, v in pairs(headers) do
    table.insert(cmd, "-H");
    table.insert(cmd, k .. ": " .. v);
  end

  local full_stdout = "";
  local partial_data = ""; -- Buffer for incomplete SSE lines
  local stream_error = nil;
  local http_status = nil;
  local job_ref = { handle = nil };

  -- Helper to process whatever is currently in partial_data
  local function process_partial(is_final)
    while true do
      local nl_pos = partial_data:find("\n");
      if not nl_pos then break end
      
      local line = partial_data:sub(1, nl_pos - 1);
      partial_data = partial_data:sub(nl_pos + 1);
      
      -- Catch the HTTP status code added by -w
      local status_code = line:match("^HTTP_STATUS:(%d%d%d)$") or line:match("^(%d%d%d)$");
      if status_code then
        http_status = tonumber(status_code);
      elseif line ~= "" then
        local parsed = parse_sse_line(line);
        if parsed.error then
          stream_error = parsed.error;
          if on_stdout then on_stdout(parsed.error, "error"); end
          -- If we get a stream error, we should probably stop and report
          if job_ref.handle then job_ref.handle:kill(15) end
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

  job_ref.handle = vim.system(cmd, {
    text = false, -- Use raw bytes to avoid \r\n vs \n issues in SSE
    stdin = request_body,
    stdout = function(err, data)
      if not data then return end
      partial_data = partial_data .. data;
      process_partial(false);
    end,
  }, function(obj)
    vim.schedule(function()
      process_partial(true);

      local success = (obj.code == 0) and (not stream_error) and (not http_status or (http_status >= 200 and http_status < 300));

      if success then
        callback(true, full_stdout);
      else
        -- If curl failed or we got a mid-stream error, provide clear feedback
        local err_msg = stream_error or obj.stderr;
        
        if http_status and (http_status < 200 or http_status >= 300) then
          err_msg = string.format("HTTP %d: %s", http_status, err_msg or "Unknown Error");
        elseif obj.code ~= 0 then
          err_msg = err_msg or string.format("API failed with code %d", obj.code);
        end
        
        -- Special check for common OpenRouter/OpenAI parameter errors
        if err_msg and (err_msg:match("unsupported_parameter") or err_msg:match("invalid_request_error")) then
          err_msg = "Model Compatibility Error: " .. err_msg;
        end
        
        callback(false, err_msg);
      end
    end);
  end);

  return job_ref.handle;
end

return M;
