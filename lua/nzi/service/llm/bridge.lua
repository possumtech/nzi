local dom_session = require("nzi.dom.session");
local watcher = require("nzi.service.vim.watcher");
local rpc = require("nzi.dom.rpc");
local config = require("nzi.core.config");
local modal = require("nzi.ui.modal");

local M = {};

M.is_busy = false;

--- The primary entry point for starting an interaction loop.
--- This now delegates entirely to the Python core.
function M.run_loop(content, mode, include_lsp, target_file, selection)
  if M.is_busy then
    config.notify("AI is already processing a request.", "warn");
    return;
  end

  M.is_busy = true;
  modal.set_thinking(true);
  
  -- Gather current context state to sync once before the loop starts
  local ctx_list = watcher.sync_list() or {};
  local roadmap_content = nil;
  
  -- We still use prompt.lua just to gather the roadmap file content for sync
  local prompt_service = require("nzi.service.llm.prompt");
  local parts = prompt_service.gather();
  roadmap_content = parts.roadmap_content;

  -- 1. Sync State to DOM
  dom_session.update_context(ctx_list, roadmap_content);

  -- 2. Hand off to Python
  -- We pass the instruction and the current configuration
  rpc.request_sync("run_loop", {
    instruction = content,
    mode = mode or "ask",
    user_data = {
      instruction = content,
      target_file = target_file,
      selection = selection
    },
    config = {
      model = config.options.active_model,
      api_key = config.options.api_key,
      api_base = config.options.api_base,
      model_options = config.options.model_options
    }
  });

  M.is_busy = false;
  modal.set_thinking(false);
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
      require("nzi.service.vim.effector").run_shell(content);
    else
      M.run_loop(content, type, false, relative_file, nil);
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
      require("nzi.service.vim.effector").run_shell(content);
    elseif parsed_type == "internal" then
      require("nzi.core.commands").run(content);
    else
      M.run_loop(content, parsed_type, false, relative_file, nil);
    end
  else
    config.notify("No AI instruction found on current line.", "warn");
  end
end

return M;
