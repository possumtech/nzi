local config = require("nzi.core.config");
local M = {};

M.job_id = nil;
M.callbacks = {};
M.next_id = 1;

--- Start the Python DOM Engine
function M.ensure_engine()
  if M.job_id and M.job_id > 0 then return M.job_id end

  local script_path = config.get_plugin_path() .. "/python/nzi/service/vim/bridge.py";
  local cmd = vim.list_extend({}, config.options.python_cmd);
  table.insert(cmd, "-u");
  table.insert(cmd, script_path);

  M.job_id = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then
          local ok, res = pcall(vim.fn.json_decode, line);
          if ok and res then
            -- Proactive Cache Sync
            if res.xml then
              require("nzi.dom.session").cache_xml = res.xml;
            end

            if res.method == "refresh_ui" then
              -- Pure projection: Just re-render what Python says is true
              vim.schedule(function()
                require("nzi.ui.modal").render_history();
              end);
            elseif res.id and M.callbacks[res.id] then
              local cb = M.callbacks[res.id];
              M.callbacks[res.id] = nil;
              cb(res);
            end
          else
            -- NOT JSON: Log to file, NOT the command window
            config.log("PYTHON RAW: " .. line, "BRIDGE");
          end
        end
      end
    end,
    on_stderr = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then
          config.log("PYTHON ERROR: " .. line, "BRIDGE");
        end
      end
    end,
  });

  return M.job_id;
end

--- Send a synchronous request to the Python bridge
function M.request_sync(method, params)
  M.ensure_engine();
  local id = M.next_id;
  M.next_id = M.next_id + 1;

  local payload = vim.fn.json_encode({
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params or {}
  });

  local result = nil;
  M.callbacks[id] = function(res)
    result = res;
  end

  vim.fn.chansend(M.job_id, payload .. "\n");

  -- Wait for result (Block Lua)
  vim.wait(10000, function() return result ~= nil end, 10);

  if not result then
    error("RPC Timeout: " .. method);
  end

  if not result.success then
    local err_msg = "Bridge Error (" .. method .. "): " .. (result.error or "Unknown");
    if result.xml_dump then
      local dump_path = "/tmp/nzi_error_dump.xml";
      local f = io.open(dump_path, "w");
      if f then f:write(result.xml_dump); f:close(); end
      err_msg = err_msg .. "\nXML Dumped to: " .. dump_path;
    end
    error(err_msg);
  end

  return result;
end

return M;
