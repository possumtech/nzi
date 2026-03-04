local parser = require("nzi.parser");
local shell = require("nzi.shell");
local context = require("nzi.context");
local prompts = require("nzi.prompts");
local job = require("nzi.job");
local modal = require("nzi.modal");
local commands = require("nzi.commands");

local M = {};

--- Handle an ai? question (or ai: directive for now)
--- @param content string
--- @param include_lsp boolean | nil
function M.handle_question(content, include_lsp)
  local config = require("nzi.config");
  local model_alias = config.options.active_model or "AI";
  local ctx_list = context.gather();
  local prompt_parts = prompts.gather();
  
  local system_prompt = prompts.build_system_prompt(prompt_parts, model_alias);
  local context_str = prompts.format_context(ctx_list, include_lsp, prompt_parts.tasks);
  local hist_str = require("nzi.history").format();
  
  local full_prompt = system_prompt .. "\n\n" .. hist_str .. "\n\n" .. context_str .. "\n\n### QUESTION\n" .. content;
  
  modal.open();
  
  if config.options.modal.show_context then
    modal.write(system_prompt, "system", false);
    if hist_str ~= "" then
      modal.write(hist_str, "history", false);
    end
    modal.write(context_str, "context", false);
  end

  modal.write(content, "user", config.options.modal.show_context);
  
  modal.set_thinking(true);
  local start_line_count = vim.api.nvim_buf_line_count(modal.bufnr or 0);
  
  job.run(full_prompt, function(success, result)
    vim.schedule(function()
      modal.set_thinking(false);
      if success then
        -- Add to structured history for the next turn
        require("nzi.history").add("question", content, result);
      else
        modal.write("\nERROR: " .. result .. "\n", "system", false);
      end
      -- Finalize the XML structure
      modal.close_tag();
    end);
  end, function(chunk, type)
    -- On stdout chunk, stream to modal with correct color (reasoning_content or content)
    vim.schedule(function()
      modal.write(chunk, type, true);
    end);
  end);
end

--- Detect and execute the AI directive at the current line
function M.execute_current_line()
  local bufnr = vim.api.nvim_get_current_buf();
  local cursor = vim.api.nvim_win_get_cursor(0);
  local line_idx = cursor[1]; -- 1-based index
  local line = vim.api.nvim_buf_get_lines(bufnr, line_idx - 1, line_idx, false)[1];

  local type, content = parser.parse_line(line);
  if not type then
    vim.notify("No AI directive found on current line.", vim.log.levels.WARN);
    return;
  end

  if type == "shell" then
    shell.run(content, bufnr, line_idx);
  elseif type == "question" or type == "directive" then
    -- Directives are currently treated as questions
    M.handle_question(content, true);
  elseif type == "command" then
    commands.run(content);
  end
end

--- Execute AI logic on a range of lines (Visual Mode)
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
    elseif type == "question" or type == "directive" then
      M.handle_question(content .. "\n\n### FOCUS SELECTION\n" .. table.concat(lines, "\n"));
    elseif type == "command" then
      commands.run(content);
    end
    return;
  end

  -- 2. If no interpolated directive, prompt the user for a task
  vim.ui.input({ prompt = "AI (prompt): " }, function(input)
    if not input or input == "" then return; end
    
    local selection_text = table.concat(lines, "\n");
    -- Treat everything as a question/prompt about the selection
    M.handle_question(input .. "\n\n### FOCUS SELECTION\n" .. selection_text);
  end);
end

return M;
