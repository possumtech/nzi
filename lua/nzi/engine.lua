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

  local messages, system_prompt, context_str, ctx_list = prompts.build_messages(content, "question", nil, include_lsp);
  
  modal.open();
  
  if config.options.modal.show_context then
    modal.write(system_prompt, "system", false);
    
    local history_msgs = history.get_as_messages();
    if #history_msgs > 0 then
      for _, msg in ipairs(history_msgs) do
        modal.write(msg.content, msg.role, false);
      end
    end
    
    modal.write(context_str, "context", false);
  end

  -- Summary for user feedback
  local counts = { active = 0, read = 0, map = 0 };
  local warnings = {};
  for _, item in ipairs(ctx_list) do
    counts[item.state] = (counts[item.state] or 0) + 1;
    if item.err then table.insert(warnings, string.format("Warning (%s): %s", item.name, item.err)) end
  end
  local summary = string.format("Context: %d active, %d read, %d mapped.", counts.active, counts.read, counts.map);
  modal.write(summary, "system", false);
  for _, w in ipairs(warnings) do modal.write(w, "error", false) end
  
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
