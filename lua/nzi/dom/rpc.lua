local config = require("nzi.core.config");
local M = {};

M.job_id = nil;
M.callbacks = {};
M.next_id = 1;

--- Start the Python DOM Engine
function M.ensure_engine()
  if M.job_id then return true; end

  local python_cmd = config.options.python_cmd[1] or "python3";
  local engine_script = vim.fn.getcwd() .. "/lua/nzi/dom/engine.py";

  M.job_id = vim.fn.jobstart({ python_cmd, engine_script }, {
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then
          local ok, res = pcall(vim.fn.json_decode, line);
          if ok and res.id and M.callbacks[res.id] then
            M.callbacks[res.id](res);
            M.callbacks[res.id] = nil;
          end
        end
      end
    end,
    on_stderr = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then
          config.log("Engine Stderr: " .. line, "ERROR");
        end
      end
    end,
    on_exit = function(_, code)
      config.log("Engine Exited with code: " .. code, "ERROR");
      M.job_id = nil;
    end
  });

  return M.job_id > 0;
end

--- Send a synchronous request to the engine (using wait)
function M.request_sync(method, params)
  M.ensure_engine();
  local id = M.next_id;
  M.next_id = M.next_id + 1;

  local response = nil;
  M.callbacks[id] = function(res)
    response = res;
  end

  local req = vim.fn.json_encode({ id = id, method = method, params = params });
  vim.fn.jobsend(M.job_id, req .. "\n");

  -- Wait for response (fail-hard if it takes too long)
  local ok = vim.wait(5000, function() return response ~= nil end, 10);
  
  if not ok then
    error("DOM Engine Timeout on method: " .. method);
  end

  if not response.success then
    local err_msg = "Contract Violation: " .. (response.error or "Unknown Error");
    if response.xml_dump then
      -- Write violation to a temp file for inspection
      local dump_path = "/tmp/nzi_violation.xml";
      local f = io.open(dump_path, "w");
      if f then f:write(response.xml_dump); f:close(); end
      err_msg = err_msg .. "\nXML Dumped to: " .. dump_path;
    end
    error(err_msg);
  end

  return response;
end

return M;
