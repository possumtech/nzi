local config = require("nzi.core.config");
local M = {};

M.job_id = nil;
M.callbacks = {};
M.next_id = 1;

--- Start the Python DOM Engine (New Modular Bridge)
function M.ensure_engine()
  if M.job_id and M.job_id > 0 then return true; end

  local python_cmd = config.options.python_cmd and config.options.python_cmd[1] or "python3";
  -- Locate the new modular bridge
  local info = debug.getinfo(1).source;
  if info:sub(1,1) == "@" then info = info:sub(2) end
  local base_dir = vim.fn.fnamemodify(info, ":h:h:h:h"); -- Back out to root from lua/nzi/dom/
  local engine_script = base_dir .. "/python/nzi/service/vim/bridge.py";
  
  config.log("Starting Python Core: " .. engine_script, "DOM");

  M.job_id = vim.fn.jobstart({ python_cmd, engine_script }, {
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then
          config.log("RPC RES: " .. line, "DOM");
          local ok, res = pcall(vim.fn.json_decode, line);
          if ok then
            if res.id and M.callbacks[res.id] then
              M.callbacks[res.id](res);
              M.callbacks[res.id] = nil;
            elseif res.method then
              -- Request FROM Python to Vim
              M.handle_incoming_request(res);
            end
          end
        end
      end
    end,
    on_stderr = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then
          config.log("Engine Stderr: " .. line, "ERROR");
          -- Also print to stdout for test harness visibility
          print("ENGINE STDERR: " .. line);
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

--- Handle requests coming FROM Python TO Vim
function M.handle_incoming_request(req)
  local method = req.method;
  local params = req.params or {};
  
  vim.schedule(function()
    if method == "stream_chunk" then
      require("nzi.ui.modal").write(params.text, params.type or "content", true);
    elseif method == "notify" then
      config.notify(params.msg, params.level or "info");
    elseif method == "execute_command" then
      vim.cmd(params.command);
    elseif method == "propose_edit" then
      require("nzi.ui.diff").propose_edit(params.file, params.content);
    elseif method == "execute_shell" then
      require("nzi.service.vim.effector").run_shell(params.command);
    end
  end);
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
  config.log("RPC REQ: " .. req, "DOM");
  vim.fn.jobsend(M.job_id, req .. "\n");

  -- Wait for response
  -- In headless mode, we must manually allow the event loop to process stdout
  local timeout = 5000;
  local step = 20;
  local elapsed = 0;
  while response == nil and elapsed < timeout do
    -- This helps spin the loop and process callbacks
    vim.wait(step, function() return response ~= nil end);
    elapsed = elapsed + step;
  end
  
  if response == nil then
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
