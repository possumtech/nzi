local parser = require("nzi.parser");
local shell = require("nzi.shell");
local context = require("nzi.context");
local prompts = require("nzi.prompts");
local job = require("nzi.job");
local modal = require("nzi.modal");
local directive = require("nzi.directive");
local commands = require("nzi.commands");

local M = {};

--- Handle an nzi? question
--- @param content string
--- @param include_lsp boolean | nil
function M.handle_question(content, include_lsp)
  local config = require("nzi.config");
  local model_name = config.options.default_model;
  local ctx_list = context.gather();
  local prompt_parts = prompts.gather();
  
  local system_prompt = prompts.build_system_prompt(prompt_parts, model_name);
  local context_str = prompts.format_context(ctx_list, include_lsp);
  
  local full_prompt = system_prompt .. "\n\n" .. context_str .. "\n\n### QUESTION\n" .. content;
  
  modal.open();
  modal.write(system_prompt .. "\n", "system", false);
  modal.write(context_str .. "\n", "context", false);
  modal.write(content .. "\n", "question", false);
  
  modal.set_thinking(true);
  local start_line_count = vim.api.nvim_buf_line_count(modal.bufnr or 0);
  
  job.run(full_prompt, function(success, result)
    vim.schedule(function()
      modal.set_thinking(false);
      if success then
        -- Transition the streamed lines to the final response color
        local end_line_count = vim.api.nvim_buf_line_count(modal.bufnr);
        modal.recolor_last_lines(end_line_count - start_line_count, "response");
      else
        modal.write("\nERROR: " .. result .. "\n", "system", false);
      end
    end);
  end, function(chunk, type)
    -- On stdout chunk, stream to modal with correct color (thought or stream)
    vim.schedule(function()
      modal.write(chunk, type, true);
    end);
  end);
end

--- Detect and execute the nzi directive at the current line
function M.execute_current_line()
  local bufnr = vim.api.nvim_get_current_buf();
  local cursor = vim.api.nvim_win_get_cursor(0);
  local line_idx = cursor[1]; -- 1-based index
  local line = vim.api.nvim_buf_get_lines(bufnr, line_idx - 1, line_idx, false)[1];

  local type, content = parser.parse_line(line);
  if not type then
    vim.notify("No nzi directive found on current line.", vim.log.levels.WARN);
    return;
  end

  if type == "shell" then
    shell.run(content, bufnr, line_idx);
  elseif type == "question" then
    M.handle_question(content, true); -- Localized: include LSP
  elseif type == "directive" then
    require("nzi.directive").run(content, bufnr, true); -- Localized: include LSP
  elseif type == "command" then
    commands.run(content);
  end
end

--- Execute nzi logic on a range of lines (Visual Mode)
--- @param line1 number: Start line
--- @param line2 number: End line
function M.execute_range(line1, line2)
  local bufnr = vim.api.nvim_get_current_buf();
  local lines = vim.api.nvim_buf_get_lines(bufnr, line1 - 1, line2, false);
  
  -- 1. Try to find an interpolated directive within the selection
  local idx, type, content = parser.find_in_lines(lines);
  
  if type then
    if type == "shell" then
      shell.run(content, bufnr, line1 + idx - 1);
    elseif type == "question" then
      M.handle_question(content .. "\n\n### FOCUS SELECTION\n" .. table.concat(lines, "\n"));
    elseif type == "directive" then
      directive.run(content, bufnr);
    elseif type == "command" then
      commands.run(content);
    end
    return;
  end

  -- 2. If no interpolated directive, prompt the user for a task
  vim.ui.input({ prompt = "nzi (?:question, else:directive): " }, function(input)
    if not input or input == "" then return; end
    
    local first_char = input:sub(1,1);
    local selection_text = table.concat(lines, "\n");
    
    if first_char == "?" then
      -- It's a question about the selection
      M.handle_question(input:sub(2) .. "\n\n### FOCUS SELECTION\n" .. selection_text);
    else
      -- It's a directive to modify the selection (or project)
      -- We still run the directive handler, which will have the selection in context
      directive.run(input, bufnr);
    end
  end);
end

return M;
