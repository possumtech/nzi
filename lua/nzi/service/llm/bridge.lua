local dom_session = require("nzi.dom.session");
local watcher = require("nzi.service.vim.watcher");
local rpc = require("nzi.dom.rpc");
local config = require("nzi.core.config");
local modal = require("nzi.ui.modal");

local M = {};

M.is_busy = false;
M.queue = {};

--- The primary entry point for starting an interaction loop.
--- This now delegates entirely to the Python core.
function M.run_loop(content, mode, include_lsp, target_file, selection)
  if M.is_busy then
    table.insert(M.queue, {
      content = content,
      mode = mode,
      include_lsp = include_lsp,
      target_file = target_file,
      selection = selection
    });
    config.notify("AI is busy. Turn enqueued (Queue size: " .. #M.queue .. ")", "info");
    return;
  end

  M.is_busy = true;
  modal.set_thinking(true);
  
  -- 1. Gather Context & Prioritize current file
  local ctx_list = watcher.sync_list() or {};
  local cur_file = vim.api.nvim_buf_get_name(0);
  local relative_cur = (cur_file ~= "") and vim.fn.fnamemodify(cur_file, ":.") or nil;

  -- Move the current active file to the top of the context list for model attention
  if relative_cur then
    for i, item in ipairs(ctx_list) do
      if item.name == relative_cur then
        table.remove(ctx_list, i);
        table.insert(ctx_list, 1, item);
        break;
      end
    end
  end

  -- 2. Sync State to DOM
  dom_session.update_context(ctx_list, nil);

  -- 3. Hand off to Python
  local active_model = config.get_active_model();
  
  -- We wrap the RPC in a pcall to ensure M.finish() runs if Python is dead
  local ok, err = pcall(rpc.request_sync, "run_loop", {
    instruction = content,
    mode = mode or "act",
    user_data = {
      instruction = content,
      target_file = target_file or relative_cur,
      selection = selection
    },
    config = {
      model = active_model.model,
      api_key = active_model.api_key,
      api_base = active_model.api_base,
      model_options = config.options.model_options
    }
  });

  if not ok then
    config.notify("Bridge Error: " .. tostring(err), "error");
  end

  M.finish();
end

--- Signal turn completion and process queue
function M.finish()
  M.is_busy = false;
  modal.set_thinking(false);
  
  if #M.queue > 0 then
    local next_req = table.remove(M.queue, 1);
    -- Trigger next request in next tick to avoid deep recursion
    vim.schedule(function()
      M.run_loop(next_req.content, next_req.mode, next_req.include_lsp, next_req.target_file, next_req.selection);
    end);
  end
end

--- Execute a specific line as a 'Ghost Line' interpolation
function M.execute_interpolation(row)
  local bufnr = vim.api.nvim_get_current_buf();
  local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1];
  local parser = require("nzi.dom.parser");
  local type, content = parser.parse_line(line);

  if not type then return end

  -- 1. Immediate Cleanup: Delete the instruction line
  vim.api.nvim_buf_set_lines(bufnr, row - 1, row, false, {});

  -- 2. Target Selection: Line below the original instruction
  -- Note: After deletion, the "line below" is now at 'row'
  local total_lines = vim.api.nvim_buf_line_count(bufnr);
  local selection = nil;
  local cur_file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.");

  if row <= total_lines then
    local target_line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1];
    selection = {
      file = cur_file,
      start_line = row,
      start_col = 1,
      end_line = row,
      end_col = #target_line + 1,
      text = target_line,
      mode = "V" -- Treat as line selection
    }
  end

  -- 3. Start Mission
  if type == "run" then
    require("nzi.service.vim.effector").run(content);
  elseif type == "cmd" then
    require("nzi.core.commands").run(content);
  else
    M.run_loop(content, type, false, cur_file, selection);
  end
end

--- Helper to capture visual selection and start a loop
function M.start_loop(content, mode, include_lsp, target_file, selection)
  local current_selection = selection or watcher.get_selection();
  return M.run_loop(content, mode, include_lsp, target_file, current_selection);
end

--- Capture current selection and run 'Analyze'
function M.get_visual_selection()
  local selection = watcher.get_selection();
  if not selection or selection.text == "" then
    config.notify("No selection found", "warn");
    return;
  end
  M.run_loop("Analyze this", "ask", false, nil, selection);
end

--- Execute a specific range of lines
function M.execute_range(line1, line2)
  local bufnr = vim.api.nvim_get_current_buf();
  local lines = vim.api.nvim_buf_get_lines(bufnr, line1-1, line2, false);
  local parser = require("nzi.dom.parser");
  local row, type, content = parser.find_in_lines(lines);
  
  if type then
    local absolute_row = line1 + row - 1;
    vim.api.nvim_buf_set_lines(bufnr, absolute_row - 1, absolute_row, false, {});
    
    local cur_file = vim.api.nvim_buf_get_name(0);
    local relative_file = (cur_file ~= "") and vim.fn.fnamemodify(cur_file, ":.") or nil;
    
    if type == "run" then
      require("nzi.service.vim.effector").run(content);
    else
      local selection = watcher.get_selection();
      M.run_loop(content, type, false, relative_file, selection);
    end
  else
    local selection = watcher.get_selection();
    M.run_loop("Analyze this", "ask", false, nil, selection);
  end
end

--- Execute the current line if it contains an AI prefix
function M.execute_current_line()
  local line = vim.api.nvim_get_current_line();
  local parser = require("nzi.dom.parser");
  local parsed_type, content = parser.parse_line(line);

  if parsed_type then
    -- Delete the instruction line
    local row = vim.api.nvim_win_get_cursor(0)[1];
    vim.api.nvim_buf_set_lines(0, row-1, row, false, {});
    
    local cur_file = vim.api.nvim_buf_get_name(0);
    local relative_file = (cur_file ~= "") and vim.fn.fnamemodify(cur_file, ":.") or nil;
    
    if parsed_type == "run" then
      require("nzi.service.vim.effector").run(content);
    elseif parsed_type == "cmd" then
      require("nzi.core.commands").run(content);
    else
      M.run_loop(content, parsed_type, false, relative_file, nil);
    end
  else
    config.notify("No AI instruction found on current line.", "warn");
  end
end

return M;
