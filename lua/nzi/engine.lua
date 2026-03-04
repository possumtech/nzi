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
function M.handle_question(content)
  local ctx_list = context.gather();
  local prompt_parts = prompts.gather();
  
  local system_prompt = prompts.build_system_prompt(prompt_parts);
  local context_str = prompts.format_context(ctx_list);
  
  local full_prompt = system_prompt .. "\n\n" .. context_str .. "\n\n### QUESTION\n" .. content;
  
  modal.write("# nzi: Thinking...\n\nProcessing question: " .. content, false);
  modal.open();
  
  job.run(full_prompt, function(success, result)
    vim.schedule(function()
      if success then
        modal.write("# nzi: Response\n\n" .. result, false);
      else
        modal.write("# nzi: Error\n\n" .. result, false);
      end
    end);
  end);
end

--- Detect and execute the nzi directive at the current line
function M.execute_current_line()
  local bufnr = vim.api.nvim_get_current_buf();
  local cursor = vim.api.nvim_win_get_cursor(0);
  local line_idx = cursor[1];
  local line = vim.api.nvim_get_current_line();

  local type, content = parser.parse_line(line);
  if not type then
    vim.notify("No nzi directive found on current line.", vim.log.levels.WARN);
    return;
  end

  if type == "shell" then
    shell.run(content, bufnr, line_idx);
  elseif type == "question" then
    M.handle_question(content);
  elseif type == "directive" then
    directive.run(content, bufnr);
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
