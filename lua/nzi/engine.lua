local parser = require("nzi.parser");
local shell = require("nzi.shell");
local context = require("nzi.context");
local prompts = require("nzi.prompts");
local job = require("nzi.job");
local modal = require("nzi.modal");
local config = require("nzi.config");
local history = require("nzi.history");
local protocol = require("nzi.protocol");
local tools = require("nzi.tools");

local M = {};

M.current_job = nil;

--- Handle an ai? question or an AI: directive in a multi-turn loop
--- @param content string: The question or directive text
--- @param type string: 'question' or 'directive'
--- @param include_lsp boolean: Whether to include LSP symbol info
--- @param target_file string | nil: The target file for directives
function M.run_loop(content, type, include_lsp, target_file)
  -- Cancel existing job if running
  if M.current_job then
    M.current_job:kill(15);
    M.current_job = nil;
  end

  local turn_count = 0;
  local max_turns = config.options.max_turns or 5;
  local last_result = nil;
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
        
        if success then
          last_result = result;
          tag_parser:feed(""); -- Finalize parser
          local actions = tag_parser:get_actions();
          
          if #actions > 0 then
            -- Handle Tool Calls
            local current_action_idx = 1;
            
            local function run_next_action()
              if current_action_idx > #actions then
                -- All actions for this turn complete, start next model turn
                current_prompt = "Tool result(s) received. Continue.";
                start_turn();
                return;
              end
              
              local action = actions[current_action_idx];
              current_action_idx = current_action_idx + 1;
              
              local agent_response = nil;
              
              if action.name == "grep" then
                modal.write("Searching universe: " .. action.content, "system", false);
                local grep_res = tools.grep(action.content);
                agent_response = string.format("<agent:grep>\n%s\n</agent:grep>", grep_res);
              
              elseif action.name == "env" or action.name == "shell" then
                modal.write("Executing " .. action.name .. ": " .. action.content, "system", false);
                local output = tools.shell(action.content, config.options.yolo);
                if output then
                  agent_response = string.format("<agent:%s>\n%s\n</agent:grep>", action.name, output, action.name);
                else
                  agent_response = string.format("<agent:%s>Command executed. No output returned to context.</agent:%s>", action.name, action.name);
                end
              
              elseif action.name == "read" then
                local file = protocol.get_attr(action.attr, "file");
                if file then
                  modal.write("Reading file: " .. file, "system", false);
                  vim.cmd("edit " .. file);
                  agent_response = "<agent:status>File opened and added to context.</agent:status>";
                end
              
              elseif action.name == "choice" then
                modal.write("User Choice Prompt: " .. action.content, "system", false);
                tools.choice(action.content, function(choice_res)
                  vim.schedule(function()
                    history.add("assistant", result, nil);
                    history.add("user", string.format("<agent:choice>%s</agent:choice>", choice_res), nil);
                    current_prompt = "User selected: " .. choice_res;
                    start_turn();
                  end);
                end);
                return; -- Wait for callback
              end
              
              if agent_response then
                -- assistant role: the tag call itself
                history.add("assistant", result, nil);
                -- user role: the tool's result
                history.add("user", agent_response, nil);
                run_next_action();
              else
                run_next_action();
              end
            end
            
            run_next_action();
          else
            -- No actions, this is the final response
            history.add(type, content, result);
            modal.close_tag();
          end
        elseif not error_displayed then
          modal.write(result, "error", false);
          modal.close_tag();
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
