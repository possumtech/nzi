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

  local stdout_buf = "";
  M.job_id = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data)
      if not data then return end
      
      -- data is a list of strings where data[1] continues the previous chunk
      -- and data[#data] is the start of the next chunk.
      stdout_buf = stdout_buf .. table.concat(data, "\n");
      
      -- Process all complete lines
      local lines = vim.split(stdout_buf, "\n", { plain = true });
      
      -- The last element is always the partial line (even if empty)
      stdout_buf = table.remove(lines);
      
      for _, line in ipairs(lines) do
        if line ~= "" then
          config.log("Decoding line, length: " .. #line, "BRIDGE");
          local ok, res = pcall(vim.fn.json_decode, line);
          if ok and res then
            -- Proactive Cache Sync
            if res.xml then
              require("nzi.dom.session").cache_xml = res.xml;
            end

            if res.method == "refresh_ui" then
              vim.schedule(function()
                require("nzi.ui.modal").render_history();
              end);
            elseif res.method == "propose_edit" then
              vim.schedule(function()
                require("nzi.service.vim.effector").propose_edit(res.params);
              end);
            elseif res.method == "propose_create" then
              vim.schedule(function()
                require("nzi.service.vim.effector").propose_create(res.params);
              end);
            elseif res.method == "propose_delete" then
              vim.schedule(function()
                require("nzi.service.vim.effector").propose_delete(res.params);
              end);
            elseif res.method == "propose_choice" then
              vim.schedule(function()
                require("nzi.service.vim.effector").propose_choice(res.params);
              end);
            elseif res.method == "execute_shell" then
              vim.schedule(function()
                require("nzi.service.vim.effector").run(res.params.command, nil, nil, false, res.params.signal_type);
              end);
            elseif res.id then
              config.log("Received result for id: " .. res.id, "BRIDGE");
              if M.callbacks[res.id] then
                local cb = M.callbacks[res.id];
                M.callbacks[res.id] = nil;
                cb(res);
              else
                config.log("No callback found for id: " .. res.id, "BRIDGE");
              end
            end

          else
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
    on_exit = function(_, code)
      config.log("PYTHON PROCESS EXITED with code " .. code, "BRIDGE");
      M.job_id = nil;
    end
  });

  if M.job_id <= 0 then
    local err = "Failed to start Python bridge (code " .. M.job_id .. ")";
    M.job_id = nil;
    error(err);
  end

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

  local ok_send, err_send = pcall(vim.fn.chansend, M.job_id, payload .. "\n");
  if not ok_send then
    M.job_id = nil; -- Force restart on next call
    error("Failed to send to Python bridge: " .. tostring(err_send));
  end

  -- Wait for result (Block Lua)
  vim.wait(30000, function() return result ~= nil end, 10);

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
