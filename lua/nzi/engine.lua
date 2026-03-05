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
M.is_busy = false; -- Reliable state for testing and UI

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

  M.is_busy = true;
  local turn_count = 0;
  local max_turns = config.options.max_turns or 5;
  local current_prompt = content;

  local function start_turn()
    turn_count = turn_count + 1;
    if turn_count > max_turns then
      modal.write("Max turns reached. Loop halted for safety.", "error", false);
      modal.set_thinking(false);
      modal.close_tag();
      vim.schedule(function() M.is_busy = false; end);
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
        
        if not success then
          modal.set_thinking(false);
          if not error_displayed then
            modal.write(result, "error", false);
            modal.close_tag();
          end
          vim.schedule(function() M.is_busy = false; end);
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
                -- Tools ran but no response for model (finalize)
                history.add(type, current_prompt, result);
                modal.set_thinking(false);
                modal.close_tag();
                vim.schedule(function() M.is_busy = false; end);
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
                -- Final response, all good
                history.add(type, current_prompt, result);
                modal.set_thinking(false);
                modal.close_tag();
                vim.schedule(function() M.is_busy = false; end);
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
  local bufnr = vim.api.nvim_get_current_buf();
  local type, content = parser.parse_line(line);
  
  if not type then
    print("No AI directive found on current line.");
    return;
  end
  
  -- Remove the directive line from buffer before execution
  local row = vim.api.nvim_win_get_cursor(0)[1];
  vim.api.nvim_buf_set_lines(0, row - 1, row, false, {});

  local file_name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.");
  local selection_tag = string.format("<agent:selection file=\"%s\" line=\"%d\" end_line=\"%d\" instruction=\"%s\">\n</agent:selection>",
    file_name, row, row, content);

  if type == "question" then
    M.handle_question(selection_tag, false);
  elseif type == "shell" then
    shell.run(content);
  elseif type == "directive" then
    M.run_loop(selection_tag, "directive", false, file_name);
  elseif type == "command" then
    require("nzi.commands").run(content);
  end
end

--- Execute directives in a specified line range
function M.execute_range(start_line, end_line)
  local bufnr = vim.api.nvim_get_current_buf();
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false);
  local file_name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.");
  local found_directive = false;
  
  -- Scan for the FIRST directive in the range (visual mode idiomatic)
  for i, line in ipairs(lines) do
    local type, content = parser.parse_line(line);
    if type then
      -- Remove only the directive line itself
      local actual_row = start_line + i - 1;
      vim.api.nvim_buf_set_lines(bufnr, actual_row - 1, actual_row, false, {});
      
      -- Content remaining in selection (minus the directive)
      local context_lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line - 1, false);
      local selection_text = table.concat(context_lines, "\n");
      local instruction = (content == "" and "Analyze this" or content);
      
      local selection_tag = string.format("<agent:selection file=\"%s\" line=\"%d\" end_line=\"%d\" instruction=\"%s\">\n%s\n</agent:selection>",
        file_name, start_line, end_line, instruction, selection_text);

      if type == "question" then
        M.handle_question(selection_tag, false);
      elseif type == "shell" then
        shell.run(content);
      elseif type == "directive" then
        M.run_loop(selection_tag, "directive", false, file_name);
      elseif type == "command" then
        require("nzi.commands").run(content);
      end
      
      found_directive = true;
      break; 
    end
  end

  if not found_directive then
    -- Handle raw visual selection with no AI: prefix
    local selection_text = table.concat(lines, "\n");
    vim.ui.input({ prompt = "AI Question on selection: " }, function(input)
      if input and input ~= "" then
        local selection_tag = string.format("<agent:selection file=\"%s\" line=\"%d\" end_line=\"%d\" instruction=\"%s\">\n%s\n</agent:selection>",
          file_name, start_line, end_line, input, selection_text);
        M.handle_question(selection_tag, false);
      end
    end);
  end
end

--- Main entry point for the :AI command
function M.dispatch(args)
  local input = args.args;
  local line1 = args.line1;
  local line2 = args.line2;
  local range = args.range;
  
  if input == "" then
    if range > 0 then
      M.execute_range(line1, line2);
    else
      M.execute_current_line();
    end
  elseif input:match("^!") then
    shell.run(input:sub(2):gsub("^%s*", ""));
  elseif input:match("^:") or input:match("^%?") then
    local type, content = parser.parse_line("AI" .. input);
    if type == "question" then
      M.handle_question(content, true);
    elseif type == "directive" then
      M.run_loop(content, "directive", true, vim.fn.fnamemodify(0, ":."));
    end
  else
    M.handle_question(input, false);
  end
end

--- Handle visual selection
function M.handle_visual()
  local s_start = vim.fn.getpos("'<");
  local s_end = vim.fn.getpos("'>");
  M.execute_range(s_start[2], s_end[2]);
end

return M;
