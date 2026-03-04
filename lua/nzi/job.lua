local config = require("nzi.config");

local M = {};

--- Extract content or reasoning from a single line of bridge output
--- @param line string: A single line of JSON from the bridge
--- @return table: { content = string, reasoning_content = string, error = string | nil }
local function parse_bridge_line(line)
  local result = { content = "", reasoning_content = "", error = nil };
  
  if line == "" then return result end
  
  local ok, json = pcall(vim.json.decode, line);
  if not ok then return result end

  -- Handle Bridge Errors
  if json.error then
    result.error = json.error;
    return result;
  end

  if json.choices and json.choices[1] and json.choices[1].delta then
    local delta = json.choices[1].delta;
    
    -- Capture reasoning (OpenAI / LiteLLM style)
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
  
  return result;
end

--- Execute an AI job via the Python/LiteLLM bridge
--- @param messages table: Array of { role = string, content = string }
--- @param callback function: Called with (success, result_text)
--- @param on_stdout function | nil: Called with (chunk, type) for streaming
--- @return table | nil: The job handle
function M.run(messages, callback, on_stdout)
  local model_cfg = config.get_active_model();
  local opts = config.options;

  -- Ensure messages is an array of objects
  if type(messages) == "string" then
    messages = {{ role = "user", content = messages }};
  end

  -- 1. Prepare Request Payload for the Bridge
  local payload = {
    model = model_cfg.model,
    messages = messages,
    api_base = model_cfg.api_base,
    api_key = model_cfg.api_key,
    model_options = opts.model_options or {},
    extra_body = model_cfg.extra_body or {},
    extra_headers = model_cfg.extra_headers or {},
  };

  local request_json = vim.json.encode(payload);
  
  -- 2. Determine bridge path (absolute)
  local info = debug.getinfo(M.run);
  local script_dir = info.source:match("@?(.*/)")
  local script_path = vim.fn.fnamemodify(script_dir .. "bridge.py", ":p");

  -- 3. Execute via configured command
  local cmd = {}
  local python_parts = opts.python_cmd or { "python3" }
  for _, part in ipairs(python_parts) do
    table.insert(cmd, part)
  end
  table.insert(cmd, script_path)
  
  if os.getenv("NZI_DEBUG") then
    print("DEBUG CMD: " .. table.concat(cmd, " "));
  end

  local full_stdout = "";
  local partial_data = "";
  local job_error = nil;
  local job_ref = { handle = nil };

  local function process_output(data)
    if not data then return end
    partial_data = partial_data .. data;
    
    while true do
      local nl_pos = partial_data:find("\n");
      if not nl_pos then break end
      
      local line = partial_data:sub(1, nl_pos - 1);
      partial_data = partial_data:sub(nl_pos + 1);
      
      if line ~= "" then
        local parsed = parse_bridge_line(line);
        if parsed.error then
          job_error = parsed.error;
          if on_stdout then on_stdout(parsed.error, "error"); end
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
  end

  job_ref.handle = vim.system(cmd, {
    stdin = request_json,
    text = true,
    stdout = function(err, data)
      vim.schedule(function() process_output(data) end);
    end,
    stderr = function(err, data)
      if data then 
        -- Filter out common warnings, capture real errors
        if not data:match("Warning") then 
          job_error = (job_error or "") .. data 
        end
      end
    end
  }, function(obj)
    vim.schedule(function()
      if obj.code == 0 and not job_error then
        callback(true, full_stdout);
      else
        local msg = job_error or "Bridge failed"
        if msg:match("ModuleNotFoundError") and msg:match("litellm") then
          local plugin_root = vim.fn.fnamemodify(script_path, ":h:h:h")
          msg = "LiteLLM dependency missing. Please run the following to fix your environment:\n" ..
                "1. cd " .. plugin_root .. "\n" ..
                "2. python3 -m venv .venv\n" ..
                "3. .venv/bin/python -m pip install litellm\n" ..
                "4. Update your config: require('nzi').setup({ python_cmd = { '" .. plugin_root .. "/.venv/bin/python' } })"
        end
        callback(false, msg .. " (code " .. obj.code .. ")");
      end
    end);
  end);

  return job_ref.handle;
end

return M;
