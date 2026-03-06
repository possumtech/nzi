local config = require("nzi.core.config");

local M = {};

--- Extract content or reasoning from a single line of bridge output
local function parse_bridge_line(line)
  local result = { content = "", reasoning_content = "", error = nil };
  if line == "" then return result end
  
  local ok, json = pcall(vim.json.decode, line);
  if not ok then return result end

  if json.error then
    result.error = json.error;
    return result;
  end

  if json.choices and json.choices[1] and json.choices[1].delta then
    local delta = json.choices[1].delta;
    local reasoning = delta.reasoning_content or delta.thought or delta.reasoning;
    if reasoning then result.reasoning_content = reasoning; end
    local content = delta.content;
    if content and content ~= vim.NIL then result.content = content; end
  end
  
  return result;
end

--- Execute an AI job via the Python/LiteLLM bridge
function M.run(messages, callback, on_stdout)
  local model_alias = config.options.active_model or "deepseek";
  local model_cfg = config.get_active_model();
  local opts = config.options;

  local model_name = model_cfg.model;
  if model_cfg.provider then
    model_name = model_cfg.provider .. "/" .. model_name;
  end

  if type(messages) == "string" then
    messages = {{ role = "user", content = messages }};
  end

  local payload = {
    model = model_name,
    alias = model_alias,
    messages = messages,
    api_base = model_cfg.api_base,
    api_key = model_cfg.api_key,
    model_options = opts.model_options or {},
    extra_body = model_cfg.extra_body or {},
    extra_headers = vim.tbl_deep_extend("force", {
      ["HTTP-Referer"] = opts.referer,
      ["X-Title"] = opts.title,
    }, model_cfg.extra_headers or {}),
  };

  local request_id = math.random(1000, 9999);
  local request_json = vim.json.encode(payload);
  
  -- Tracing: Log request if debug is enabled
  if os.getenv("NZI_DEBUG") == "1" then
    local log_path = vim.fn.getcwd() .. "/nzi_debug.log";
    local f = io.open(log_path, "a");
    if f then
      f:write(string.format("\n[%s] [JOB %d] --- [LLM REQUEST START] ---\nModel: %s\nPayload:\n%s\n", 
        os.date("%H:%M:%S"), request_id, model_name, request_json));
      f:close();
    end
  end

  local info = debug.getinfo(M.run);
  local script_dir = info.source:match("@?(.*/)")
  -- bridge.py moved from engine/ to protocol/
  local script_path = vim.fn.fnamemodify(script_dir .. "../protocol/bridge.py", ":p");

  local cmd = {}
  local python_parts = opts.python_cmd or { "python3" }
  for _, part in ipairs(python_parts) do table.insert(cmd, part) end
  table.insert(cmd, "-W")
  table.insert(cmd, "ignore")
  table.insert(cmd, script_path)

  local state = {
    full_stdout = "",
    partial_data = "",
    job_error = nil,
    handle = nil,
  };

  local function process_data(data)
    if not data then return end
    state.partial_data = state.partial_data .. data;
    
    -- Tracing: Log raw chunk if debug is enabled
    if os.getenv("NZI_DEBUG") == "1" then
      local log_path = vim.fn.getcwd() .. "/nzi_debug.log";
      local f = io.open(log_path, "a");
      if f then
        f:write(string.format("[%s] [JOB %d] [CHUNK] %s\n", os.date("%H:%M:%S"), request_id, data));
        f:close();
      end
    end
    
    while true do
      local nl_pos = state.partial_data:find("\n");
      if not nl_pos then break end
      
      local line = state.partial_data:sub(1, nl_pos - 1);
      state.partial_data = state.partial_data:sub(nl_pos + 1);
      
      if line ~= "" then
        local parsed = parse_bridge_line(line);
        if parsed.error then
          state.job_error = parsed.error;
          if on_stdout then on_stdout(parsed.error, "error"); end
          if state.handle then state.handle:kill(15) end
        end
        if parsed.reasoning_content ~= "" then
          if on_stdout then on_stdout(parsed.reasoning_content, "reasoning_content"); end
        end
        if parsed.content ~= "" then
          state.full_stdout = state.full_stdout .. parsed.content;
          if on_stdout then on_stdout(parsed.content, "content"); end
        end
      end
    end
  end

  state.handle = vim.system(cmd, {
    stdin = request_json,
    text = true,
    stdout = function(err, data)
      if data then
        -- Process line fragments immediately to avoid accumulation in vim.schedule queue
        vim.schedule(function() process_data(data) end);
      end
    end,
    stderr = function(err, data)
      if data then 
        -- Accumulate all stderr (it often contains valuable traceback or LiteLLM detail)
        state.job_error = (state.job_error or "") .. data 
      end
    end
  }, function(obj)
    vim.schedule(function()
      local has_error = (obj.code ~= 0) or (state.job_error and state.job_error:match("Error"))
      
      if obj.code == 0 and not has_error then
        callback(true, state.full_stdout);
      else
        local msg = state.job_error or "Bridge failed with no error output."
        
        -- Special case for dependency issues (common)
        if msg:match("ModuleNotFoundError") and msg:match("litellm") then
          msg = "LiteLLM dependency missing. Run :AI/install to fix your environment.\n\nRaw Error:\n" .. msg
        end
        
        callback(false, msg .. " (code " .. obj.code .. ")");
      end
    end);
  end);

  return state.handle;
end

return M;
