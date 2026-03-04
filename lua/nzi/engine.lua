local parser = require("nzi.parser");
local shell = require("nzi.shell");
local context = require("nzi.context");
local prompts = require("nzi.prompts");
local job = require("nzi.job");
local modal = require("nzi.modal");
local config = require("nzi.config");
local history = require("nzi.history");

local M = {};

M.current_job = nil;

--- Handle an ai? question
--- @param content string: The question text
--- @param include_lsp boolean: Whether to include LSP symbol info
function M.handle_question(content, include_lsp)
  -- Cancel existing job if running
  if M.current_job then
    M.current_job:kill(15);
    M.current_job = nil;
  end

  local model_cfg = config.get_active_model();
  local model_alias = config.options.active_model or "AI";
  
  local ctx_list = context.gather();
  local prompt_parts = prompts.gather();
  
  -- 1. Rules of Behavior (System Role)
  local system_prompt_str = prompts.build_system_prompt(prompt_parts, model_alias);
  
  -- 2. Facts of the Project (User Role)
  local context_str = prompts.format_context(ctx_list, include_lsp);
  
  -- Build the Message Array for the API
  local messages = {};
  local role = model_cfg.role_preference or "system";
  table.insert(messages, { role = role, content = system_prompt_str });
  
  local history_msgs = history.get_as_messages();
  for _, msg in ipairs(history_msgs) do
    table.insert(messages, msg);
  end
  
  -- The final user message contains context and the question
  local user_prompt = string.format("<agent:context>\n%s\n</agent:context>\n\n<agent:user>\n%s\n</agent:user>", 
    context_str, history.xml_escape(content));
  table.insert(messages, { role = "user", content = user_prompt });
  
  modal.open();
  
  if config.options.modal.show_context then
    modal.write(system_prompt_str, "system", false);
    
    if #history_msgs > 0 then
      for _, msg in ipairs(history_msgs) do
        modal.write(msg.content, msg.role, false);
      end
    end
    
    modal.write(context_str, "context", false);
  end
  
  -- Display the final user question
  modal.write(content, "user", false);
  modal.set_thinking(true);

  local error_displayed = false;

  M.current_job = job.run(messages, function(success, result)
    vim.schedule(function()
      M.current_job = nil;
      modal.set_thinking(false);
      if success then
        -- Add to structured history for the next turn
        history.add("question", content, result);
      elseif not error_displayed then
        -- Only write the final error if the stream hasn't already reported one
        modal.write(result, "error", false);
        error_displayed = true;
      end
      -- ALWAYS finalize the XML structure
      modal.close_tag();
    end);
  end, function(chunk, type)
    -- On stdout chunk, stream to modal with correct color (reasoning_content, content, or error)
    vim.schedule(function()
      if type == "error" then
        error_displayed = true;
      end
      modal.write(chunk, type, true);
    end);
  end);
end

--- Parse and execute the current line as a directive
function M.execute_current_line()
  local line = vim.api.nvim_get_current_line();
  local type, content = parser.parse_line(line);
  
  if not type then
    print("No AI directive found on current line.");
    return;
  end
  
  if type == "question" then
    M.handle_question(content, false);
  elseif type == "shell" then
    shell.run(content);
  elseif type == "directive" then
    require("nzi.directive").run(content, vim.api.nvim_get_current_buf(), false);
  end
end

--- Execute directives in a specified line range
--- @param start_line number
--- @param end_line number
function M.execute_range(start_line, end_line)
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false);
  for _, line in ipairs(lines) do
    local type, content = parser.parse_line(line);
    if type then
      if type == "question" then
        M.handle_question(content, false);
      elseif type == "shell" then
        shell.run(content);
      elseif type == "directive" then
        require("nzi.directive").run(content, vim.api.nvim_get_current_buf(), false);
      end
    end
  end
end

--- Main entry point for the :AI command
--- @param args table: Table containing args string from nvim command
function M.dispatch(args)
  local input = args.args;
  
  if input == "" then
    M.execute_current_line();
  elseif input:match("^!") then
    -- Shortcut for :AI ! echo hello
    shell.run(input:sub(2):gsub("^%s*", ""));
  elseif input:match("^:") then
    -- Handle :AI :question or :AI :directive
    local type, content = parser.parse_line("AI" .. input);
    if type == "question" then
      M.handle_question(content, true);
    elseif type == "directive" then
      require("nzi.directive").run(content, vim.api.nvim_get_current_buf(), true);
    end
  else
    -- Treat everything else as a question
    M.handle_question(input, false);
  end
end

--- Handle visual selection
function M.handle_visual()
  local input = vim.fn.input("AI Context Question: ");
  if input == "" then return end
  
  vim.schedule(function()
    local s_start = vim.fn.getpos("'<");
    local s_end = vim.fn.getpos("'>");
    local lines = vim.api.nvim_buf_get_lines(0, s_start[2]-1, s_end[2], false);
    if #lines == 0 then return end
    
    local selection_text = table.concat(lines, "\n");
    -- Treat everything as a question/prompt about the selection
    M.handle_question(input .. "\n\n### FOCUS SELECTION\n" .. selection_text);
  end);
end

return M;
