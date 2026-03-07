local parser = require("nzi.engine.parser");
local shell = require("nzi.tools.shell");
local context = require("nzi.context.context");
local prompts = require("nzi.engine.prompts");
local job = require("nzi.engine.job");
local modal = require("nzi.ui.modal");
local config = require("nzi.core.config");
local history = require("nzi.context.history");
local protocol = require("nzi.protocol.protocol");
local agent = require("nzi.protocol.agent");
local visuals = require("nzi.ui.visuals");

local M = {};

M.current_job = nil;
M.is_busy = false; 

--- Handle an ai? ask or an AI: instruct in a multi-turn loop
--- @param content string: The initial ask or instruct text
--- @param mode string: 'ask' or 'instruct'
--- @param include_lsp boolean: Whether to include LSP symbol info
--- @param target_file string | nil: The target file for instruct
--- @param selection table | nil: Visual selection metadata
function M.run_loop(content, mode, include_lsp, target_file, selection)
  local queue = require("nzi.core.queue");

  -- If we are busy or blocked by actions, enqueue this as a pending instruction
  if M.is_busy or queue.is_blocked() then
    queue.enqueue_instruction(content, mode, target_file, selection);
    local reason = M.is_busy and "Model is busy" or "Pending diffs require resolution"
    config.notify("Instruction enqueued (" .. reason .. ")", vim.log.levels.INFO);
    return;
  end

  if M.current_job then
    M.current_job:kill(15);
    M.current_job = nil;
  end

  M.is_busy = true;
  visuals.set_busy(true);
  
  local turn_count = 0;
  local max_turns = config.options.max_turns or 5;
  local current_prompt = content;

  local function start_turn()
    local current_turn_id = history.get_next_id();
    local start_time = vim.loop.hrtime();
    turn_count = turn_count + 1;
    if turn_count > max_turns then
      modal.write("Max turns reached. Loop halted for safety.", "error", false, current_turn_id);
      modal.close_tag();
      vim.schedule(function() 
        M.is_busy = false; 
        visuals.set_busy(false);
      end);
      return;
    end

    local messages, system_prompt, context_str, ctx_list, turn_block = prompts.build_messages(current_prompt, mode, target_file, include_lsp, selection);
    local user_message_content = messages[#messages].content;

    if turn_count == 1 then
      -- Always write preamble to the buffer so it's there if modal opens later
      if config.options.modal.show_context then
        modal.write(system_prompt, "system", false, 0); -- 0 for non-history preamble
        local history_msgs = history.get_as_messages();
        for _, msg in ipairs(history_msgs) do 
          -- Extract turn ID from attributes if possible, or use 0
          local tid = tonumber(msg.content:match("id=\"(%d+)\"")) or 0
          modal.write(msg.content, msg.role, false, tid); 
        end
        modal.write(context_str, "context", false, 0);
        modal.close_tag(); -- Close Turn 0 (Preamble)
      end
      modal.write(user_message_content, "user", false, current_turn_id);
    end

    modal.set_thinking(true);
    local tag_parser = protocol.create_parser();
    local error_displayed = false;

    M.current_job = job.run(messages, function(success, result)
      vim.schedule(function()
        M.current_job = nil;
        local duration = (vim.loop.hrtime() - start_time) / 1e9; -- seconds
        local active_model = config.options.active_model or "unknown";

        if not success then
          if not error_displayed then
            modal.write(result, "error", false, current_turn_id);
            modal.close_tag();
          end
          vim.schedule(function() 
            M.is_busy = false; 
            visuals.set_busy(false);
          end);
          return;
        end

        tag_parser:feed(""); -- Finalize parser
        local actions = tag_parser:get_actions();
        local remaining = tag_parser:get_remaining();

        -- Fallback: If model sent naked text with no tags, treat it as a summary/ask
        if #actions == 0 and remaining:match("%S") then
          table.insert(actions, { name = "summary", content = remaining:gsub("^%s*", ""):gsub("%s*$", "") });
        end

        local metadata = {
          model = active_model,
          duration = duration,
          changes = #actions
        };

        if #actions > 0 then
          -- 1. Discovery/Action Phase
          agent.dispatch_actions(actions, mode, current_turn_id, function(combined_agent_response, signal, was_blocked)
            vim.schedule(function()
              if signal == "ABORTED" then
                modal.write("User aborted turn. Agent momentum halted.", "system", false, current_turn_id);
                modal.close_tag();
                vim.schedule(function() 
                  M.is_busy = false; 
                  visuals.set_busy(false);
                end);
                return;
              end

              if combined_agent_response and combined_agent_response ~= "" then
                -- At least one tool produced an ACTIVE response (grep, read, etc.)
                -- We must force a new turn to deliver this data.
                history.add(mode, turn_block, result, metadata);
                modal.write(combined_agent_response, "user", false, history.get_next_id());
                modal.close_tag(); -- Close the turn block immediately for sequential clarity
                current_prompt = combined_agent_response;

                -- Resumption logic:
                -- 1. Not blocked (grep, read, etc.) -> Auto-resume
                -- 2. Headless (tests) -> Auto-resume
                -- 3. Choice Resolution -> We just got user input, MUST resume
                local has_ui = (#vim.api.nvim_list_uis() > 0);
                local is_choice_res = combined_agent_response:match("<agent:choice>");

                if not was_blocked or not has_ui or is_choice_res then
                  -- RECURSIVE TURN: We stay BUSY
                  vim.schedule(function() start_turn(); end);
                else
                  M.is_busy = false;
                  visuals.set_busy(false);
                  config.log("Turn sequence suspended for user review/choice.", "ENGINE");
                end

              else
                -- Tools ran but were all PASSIVE (acks) or produced no context.
                -- We terminate the turn here and return control to the user.
                -- The passive buffer will be flushed and piggybacked on the NEXT turn.
                history.add(mode, turn_block, result, metadata);
                modal.close_tag(); -- Final closure

                -- COMPLETELY FINISHED
                vim.schedule(function() 
                  M.is_busy = false; 
                  visuals.set_busy(false);
                  -- AUTO-DRAIN: Check if there's more work in the queue
                  local next_work = queue.pop_instruction();
                  if next_work and not queue.is_blocked() then
                    M.run_loop(next_work.instruction, next_work.mode, false, next_work.target_file, next_work.selection);
                  end
                end);
              end
            end);
          end);
        else
          -- 2. Final Response & Verification Phase
          agent.verify_state(current_turn_id, function(failure_response)
            vim.schedule(function()
              if failure_response then
                history.add(mode, turn_block, result, metadata);
                modal.write(failure_response, "user", false, history.get_next_id());
                modal.close_tag();
                current_prompt = failure_response;
                vim.schedule(function() start_turn(); end);
              else
                -- Final response, all good
                -- CRITICAL: Ensure history is updated so tests/UI see the completion
                history.add(mode, turn_block, result, metadata);
                modal.close_tag();

                vim.schedule(function() 
                  M.is_busy = false; 
                  visuals.set_busy(false);
                  -- AUTO-DRAIN: Check if there's more work in the queue
                  local next_work = queue.pop_instruction();
                  if next_work and not queue.is_blocked() then
                    M.run_loop(next_work.instruction, next_work.mode, false, next_work.target_file, next_work.selection);
                  end
                end);
              end
            end);
          end);
        end

      end);
    end, function(chunk, msg_type)
      vim.schedule(function()
        if msg_type == "error" then error_displayed = true; end
        -- ONLY feed "content" to the action parser. 
        -- Reasoning (thought tokens) must not be parsed as model actions.
        if msg_type == "content" then
          tag_parser:feed(chunk);
        end
        modal.write(chunk, msg_type, true, current_turn_id);
      end);
    end);
  end

  start_turn();
end

--- Handle an ai? ask
function M.handle_ask(content, include_lsp)
  M.run_loop(content, "ask", include_lsp, nil);
end

--- Parse and execute the current line as a instruct
function M.execute_current_line()
  local line = vim.api.nvim_get_current_line();
  local bufnr = vim.api.nvim_get_current_buf();
  local parsed_type, content = parser.parse_line(line);
  
  if not parsed_type then
    print("No AI instruct found on current line.");
    return;
  end
  
  -- Remove the instruct line from buffer before execution
  local row = vim.api.nvim_win_get_cursor(0)[1];
  vim.api.nvim_buf_set_lines(0, row - 1, row, false, {});

  local file_name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.");
  local formatted = content;

  -- For a instruct on a single line, we pass the buffer context as a selection
  -- so the model knows where it is, but without the instruct line itself.
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
  local selection = {
    text = table.concat(lines, "\n"),
    file = file_name,
    start_line = 1,
    start_col = 1,
    end_line = #lines,
    end_col = #(lines[#lines] or ""),
    mode = "V"
  };

  if parsed_type == "ask" then
    M.run_loop(formatted, "ask", false, nil, selection);
  elseif parsed_type == "run" then
    shell.run(content);
  elseif parsed_type == "instruct" then
    M.run_loop(formatted, "instruct", false, file_name, selection);
  elseif parsed_type == "internal" then
    require("nzi.core.commands").run(content);
  end
end

--- Execute instruct in a specified line range
function M.execute_range(start_line, end_line)
  local bufnr = vim.api.nvim_get_current_buf();
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false);
  local file_name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.");
  local found_instruct = false;
  
  -- Scan for the FIRST instruct in the range (visual mode idiomatic)
  for i, line in ipairs(lines) do
    local parsed_type, content = parser.parse_line(line);
    if parsed_type then
      -- Remove only the instruct line itself
      local actual_row = start_line + i - 1;
      vim.api.nvim_buf_set_lines(bufnr, actual_row - 1, actual_row, false, {});
      
      -- Capture the remaining text in the selection as character-perfect metadata
      -- Since this is line-based, we'll treat it as a 'V' mode selection minus the instruct line
      local selection_text = table.concat(vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line - 1, false), "\n");
      local instruction = (content == "" and "Analyze this" or content);
      
      local selection = {
        text = selection_text,
        file = file_name,
        start_line = start_line,
        start_col = 1,
        end_line = end_line,
        end_col = #lines[#lines],
        mode = "V"
      };

      if parsed_type == "ask" then
        M.run_loop(instruction, "ask", false, nil, selection);
      elseif parsed_type == "run" then
        shell.run(content);
      elseif parsed_type == "instruct" then
        M.run_loop(instruction, "instruct", false, file_name, selection);
      elseif parsed_type == "internal" then
        require("nzi.core.commands").run(content);
      end
      
      found_instruct = true;
      break; 
    end
  end

  if not found_instruct then
    -- Handle active selection with no AI: prefix
    local selection = M.get_visual_selection();
    vim.ui.input({ prompt = "AI Ask on selection: " }, function(input)
      if input and input ~= "" then
        M.run_loop(input, "ask", false, nil, selection);
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
    local first_char = input:sub(1,1);
    local instruction = input:sub(2):gsub("^%s*", "");
    
    -- If they typed :AI :AI: something, instruction is AI: something
    -- We want to strip the extra AI prefix if present
    if instruction:match("^[Aa][Ii][:%?]") then
      instruction = instruction:sub(4):gsub("^%s*", "");
    end

    if first_char == "?" then
      M.handle_ask(instruction, true);
    else
      M.run_loop(instruction, "instruct", true, vim.fn.fnamemodify(0, ":."));
    end
  else
    M.handle_ask(input, false);
  end
end

--- Capture character-perfect visual selection
--- @return table: { text = string, file = string, s_line = number, s_col = number, e_line = number, e_col = number }
function M.get_visual_selection()
  local bufnr = vim.api.nvim_get_current_buf();
  local s_start = vim.fn.getpos("'<");
  local s_end = vim.fn.getpos("'>");
  
  local start_line = s_start[2] - 1;
  local start_col = s_start[3] - 1;
  local end_line = s_end[2] - 1;
  local end_col = s_end[3];

  local line_count = vim.api.nvim_buf_line_count(bufnr);
  if end_line >= line_count then end_line = line_count - 1 end
  local last_line_content = vim.api.nvim_buf_get_lines(bufnr, end_line, end_line + 1, false)[1] or "";
  if end_col > #last_line_content then end_col = #last_line_content end

  if start_line == end_line and start_col > end_col then
    start_col, end_col = end_col, start_col;
  end

  local visual_mode = vim.fn.visualmode();
  if visual_mode == "V" then
    start_col = 0;
    end_col = #last_line_content;
  end

  local ok, lines = pcall(vim.api.nvim_buf_get_text, bufnr, start_line, start_col, end_line, end_col, {});
  local text = ok and table.concat(lines, "\n") or "";
  local file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.");

  return {
    text = text,
    file = file,
    start_line = start_line + 1,
    start_col = start_col + 1,
    end_line = end_line + 1,
    end_col = end_col,
    mode = visual_mode
  };
end

--- Handle Execute selection (Visual mode shortcut)
function M.handle_visual()
  local selection = M.get_visual_selection();

  vim.ui.input({ prompt = "AI Ask on selection: " }, function(input)
    if input and input ~= "" then
      M.run_loop(input, "ask", false, nil, selection);
    end
  end);
end

return M;
