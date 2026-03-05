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
            local accumulated_responses = {};
            
            local function run_next_action()
              if current_action_idx > #actions then
                -- All actions for this turn complete, start next model turn
                if #accumulated_responses > 0 then
                  local combined_resp = table.concat(accumulated_responses, "\n\n");
                  history.add(type, current_prompt, result);
                  
                  -- Faithfully record the response being sent back to the model
                  modal.write(combined_resp, "user", false);
                  
                  current_prompt = combined_resp;
                  start_turn();
                end
                return;
              end
              
              local action = actions[current_action_idx];
              current_action_idx = current_action_idx + 1;
              
              if action.name == "grep" then
                modal.write("Searching universe: " .. action.content, "system", false);
                local grep_res = tools.grep(action.content);
                table.insert(accumulated_responses, string.format("<agent:grep>\n%s\n</agent:grep>", grep_res));
                run_next_action();
              
              elseif action.name == "env" or action.name == "shell" then
                modal.write("Executing " .. action.name .. ": " .. action.content, "system", false);
                local output = tools.shell(action.content, config.options.yolo);
                local resp = "";
                if output then
                  resp = string.format("<agent:%s>\n%s\n</agent:%s>", action.name, output, action.name);
                else
                  resp = string.format("<agent:%s>Command executed. No output returned to context.</agent:%s>", action.name, action.name);
                end
                table.insert(accumulated_responses, resp);
                run_next_action();
              
              elseif action.name == "read" then
                local file = protocol.get_attr(action.attr, "file");
                if file then
                  modal.write("Reading file: " .. file, "system", false);
                  local ok = pcall(vim.cmd, "edit " .. file);
                  local status = ok and "File opened and added to context." or "Error: Could not open file."
                  table.insert(accumulated_responses, string.format("<agent:status>%s</agent:status>", status));
                end
                run_next_action();
              
              elseif action.name == "choice" then
                modal.write("User Choice Prompt: " .. action.content, "system", false);
                tools.choice(action.content, function(choice_res)
                  vim.schedule(function()
                    table.insert(accumulated_responses, string.format("<agent:choice>%s</agent:choice>", choice_res));
                    run_next_action();
                  end);
                end);
              else
                -- Unknown or reasoning-only action, skip
                run_next_action();
              end
            end
            
            run_next_action();
          else
            -- No actions, this is the final response
            -- Trigger auto-test if configured
            if config.options.auto_test then
              modal.write("Running auto-test: " .. config.options.auto_test, "system", false);
              local test_output = vim.fn.systemlist(config.options.auto_test);
              local exit_code = vim.v.shell_error;
              
              if exit_code ~= 0 then
                local failure_text = table.concat(test_output, "\n");
                modal.write("Test failure detected.", "error", false);
                
                local should_retry = config.options.ralph;
                if not should_retry then
                  local choice = vim.fn.confirm("Test failed. Send output back to AI?", "&Yes\n&No", 1);
                  should_retry = (choice == 1);
                end
                
                if should_retry then
                  -- Pair the current prompt with the buggy response
                  history.add(type, current_prompt, result);
                  -- The next prompt is the test failure
                  local resp = string.format("<agent:test>%s</agent:test>", failure_text);
                  
                  -- Faithfully record the response being sent back to the model
                  modal.write(resp, "user", false);
                  
                  current_prompt = resp;
                  start_turn();
                  return;
                end
              else
                modal.write("Tests passed.", "system", false);
              end
            end
            
            history.add(type, current_prompt, result);
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
