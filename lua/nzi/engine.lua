local parser = require("nzi.parser");
local shell = require("nzi.shell");
local context = require("nzi.context");
local prompts = require("nzi.prompts");
local job = require("nzi.job");
local modal = require("nzi.modal");
local config = require("nzi.config");
local history = require("nzi.history");
local protocol = require("nzi.protocol");
local agent = require("nzi.agent");

local M = {};

M.current_job = nil;

--- Handle an ai? question or an AI: directive in a multi-turn loop
--- @param content string: The initial question or directive text
--- @param type string: 'question' or 'directive'
--- @param include_lsp boolean: Whether to include LSP symbol info
--- @param target_file string | nil: The target file for directives
function M.run_loop(content, type, include_lsp, target_file)
  if M.current_job then
    M.current_job:kill(15);
    M.current_job = nil;
  end

  local turn_count = 0;
  local max_turns = config.options.max_turns or 5;
  local current_prompt = content;

  local function start_turn()
    turn_count = turn_count + 1;
    if turn_count > max_turns then
      modal.write("Max turns reached. Loop halted for safety.", "error", false);
      modal.set_thinking(false);
      modal.close_tag();
      return;
    end

    local messages, system_prompt, context_str, ctx_list = prompts.build_messages(current_prompt, type, target_file, include_lsp);
    
    if turn_count == 1 then
      modal.open();
      if config.options.modal.show_context then
        modal.write(system_prompt, "system", false);
        local history_msgs = history.get_as_messages();
        for _, msg in ipairs(history_msgs) do modal.write(msg.content, msg.role, false); end
        modal.write(context_str, "context", false);
      end
      modal.write(content, "user", false);
    end

    modal.set_thinking(true);
    local tag_parser = protocol.create_parser();
    local error_displayed = false;

    M.current_job = job.run(messages, function(success, result)
      vim.schedule(function()
        M.current_job = nil;
        modal.set_thinking(false);
        
        if not success then
          if not error_displayed then
            modal.write(result, "error", false);
            modal.close_tag();
          end
          return;
        end

        tag_parser:feed(""); -- Finalize parser
        local actions = tag_parser:get_actions();
        
        if #actions > 0 then
          -- 1. Discovery/Action Phase
          agent.dispatch_actions(actions, function(combined_agent_response)
            vim.schedule(function()
              if combined_agent_response then
                history.add(type, current_prompt, result);
                modal.write(combined_agent_response, "user", false);
                current_prompt = combined_agent_response;
                start_turn();
              else
                -- Tools ran but no response for model (e.g. env command with no returned context)
                history.add(type, current_prompt, result);
                modal.close_tag();
              end
            end);
          end);
        else
          -- 2. Final Response & Verification Phase
          agent.verify_state(function(failure_response)
            vim.schedule(function()
              if failure_response then
                history.add(type, current_prompt, result);
                modal.write(failure_response, "user", false);
                current_prompt = failure_response;
                start_turn();
              else
                -- All good, wrap up
                history.add(type, current_prompt, result);
                modal.close_tag();
              end
            end);
          end);
        end
      end);
    end, function(chunk, chunk_type)
      vim.schedule(function()
        if chunk_type == "error" then error_displayed = true; end
        tag_parser:feed(chunk);
        modal.write(chunk, chunk_type, true);
      end);
    end);
  end

  start_turn();
end

--- Handle an ai? question
function M.handle_question(content, include_lsp)
  M.run_loop(content, "question", include_lsp, nil);
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
    M.run_loop(content, "directive", false, vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":."));
  end
end

--- Execute directives in a specified line range
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
        M.run_loop(content, "directive", false, vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":."));
      end
    end
  end
end

--- Main entry point for the :AI command
function M.dispatch(args)
  local input = args.args;
  
  if input == "" then
    M.execute_current_line();
  elseif input:match("^!") then
    shell.run(input:sub(2):gsub("^%s*", ""));
  elseif input:match("^:") then
    local type, content = parser.parse_line("AI" .. input);
    if type == "question" then
      M.handle_question(content, true);
    elseif type == "directive" then
      M.run_loop(content, "directive", true, vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":."));
    end
  else
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
    M.handle_question(input .. "\n\n### FOCUS SELECTION\n" .. selection_text);
  end);
end

return M;
