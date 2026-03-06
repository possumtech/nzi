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
--- @param selection table | nil: Visual selection metadata
function M.run_loop(content, type, include_lsp, target_file, selection)
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

    local messages, system_prompt, context_str, ctx_list = prompts.build_messages(current_prompt, type, target_file, include_lsp, selection);
    
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
          agent.dispatch_actions(actions, function(combined_agent_response, signal)
            vim.schedule(function()
              if signal == "ABORTED" then
                modal.write("User aborted turn. Agent momentum halted.", "system", false);
                modal.set_thinking(false);
                modal.close_tag();
                vim.schedule(function() M.is_busy = false; end);
                return;
              end

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
  local formatted = content;

  if type == "question" then
    M.handle_question(formatted, false);
  elseif type == "shell" then
    shell.run(content);
  elseif type == "directive" then
    M.run_loop(formatted, "directive", false, file_name);
  elseif type == "command" then
    require("nzi.commands").run(content);
  end
end

--- Execute directives in a specified line range
function M.execute_range(start_line, end_line)
  local bufnr = vim.api.nvim_get_current_buf();
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false);
  local file_name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.");
  local ft = vim.bo[bufnr].filetype;
  local found_directive = false;
  
  -- Scan for the FIRST directive in the range (visual mode idiomatic)
  for i, line in ipairs(lines) do
    local type, content = parser.parse_line(line);
    if type then
      -- Remove only the directive line itself
      local actual_row = start_line + i - 1;
      vim.api.nvim_buf_set_lines(bufnr, actual_row - 1, actual_row, false, {});
      
      -- Capture the remaining text in the selection as character-perfect metadata
      -- Since this is line-based, we'll treat it as a 'V' mode selection minus the directive line
      local selection_text = table.concat(vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line - 1, false), "\n");
      local instruction = (content == "" and "Analyze this" or content);
      
      local selection = {
        text = selection_text,
        file = file_name,
        start_line = start_line,
        start_col = 1,
        end_line = end_line - 1,
        end_col = #lines[#lines],
        mode = "V"
      };

      if type == "question" then
        M.run_loop(instruction, "question", false, nil, selection);
      elseif type == "shell" then
        shell.run(content);
      elseif type == "directive" then
        M.run_loop(instruction, "directive", false, file_name, selection);
      elseif type == "command" then
        require("nzi.commands").run(content);
      end
      
      found_directive = true;
      break; 
    end
  end

  if not found_directive then
    -- Handle raw visual selection with no AI: prefix
    local selection = M.get_visual_selection();
    vim.ui.input({ prompt = "AI Question on selection: " }, function(input)
      if input and input ~= "" then
        M.run_loop(input, "question", false, nil, selection);
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

--- Capture character-perfect visual selection
--- @return table: { text = string, file = string, s_line = number, s_col = number, e_line = number, e_col = number }
function M.get_visual_selection()
  local bufnr = vim.api.nvim_get_current_buf();
  local s_start = vim.fn.getpos("'<");
  local s_end = vim.fn.getpos("'>");
  
  -- getpos is 1-indexed, but nvim_buf_get_text is 0-indexed and end-exclusive
  local start_line = s_start[2] - 1;
  local start_col = s_start[3] - 1;
  local end_line = s_end[2] - 1;
  local end_col = s_end[3]; -- No -1 here because it's exclusive

  -- Handle visual line mode ('V') where col is effectively infinite
  local mode = vim.fn.visualmode();
  if mode == "V" then
    start_col = 0;
    local last_line = vim.api.nvim_buf_get_lines(bufnr, end_line, end_line + 1, false)[1] or "";
    end_col = #last_line;
  end

  local text = table.concat(vim.api.nvim_buf_get_text(bufnr, start_line, start_col, end_line, end_col, {}), "\n");
  local file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.");

  return {
    text = text,
    file = file,
    start_line = s_start[2],
    start_col = s_start[3],
    end_line = s_end[2],
    end_col = s_end[3],
    mode = mode
  };
end

--- Handle visual selection
function M.handle_visual()
  local selection = M.get_visual_selection();
  local ft = vim.bo.filetype;

  vim.ui.input({ prompt = "AI Question on selection: " }, function(input)
    if input and input ~= "" then
      -- Pass the selection metadata to run_loop or a new handler
      -- We'll modify engine.run_loop to accept selection metadata
      M.run_loop(input, "question", false, nil, selection);
    end
  end);
end

return M;
