local client = require("nzi.service.llm.client");
local dom_session = require("nzi.dom.session");
local dom_query = require("nzi.dom.query");
local protocol = require("nzi.dom.parser");
local agent_actions = require("nzi.service.llm.actions");
local modal = require("nzi.ui.modal");
local config = require("nzi.core.config");
local visuals = require("nzi.ui.visuals");
local watcher = require("nzi.service.vim.watcher");
local effector = require("nzi.service.vim.effector");

local M = {};

M._is_bridge = true; -- Debug flag
M.current_job = nil;
M.is_busy = false;

--- Start a cognitive loop (Multi-turn LLM interaction)
function M.start_loop(content, mode, include_lsp, target_file, selection)
  M.is_busy = true;
  visuals.set_busy(true);
  
  local turn_count = 0;
  local max_turns = config.options.max_turns or 5;
  local current_input = content;

  local function execute_turn()
    turn_count = turn_count + 1;
    local current_turn_id = dom_session.get_next_id();
    local start_time = vim.loop.hrtime();

    if turn_count > max_turns then
      modal.write("Max turns reached. Loop halted for safety.", "error", false, current_turn_id);
      M.finish();
      return;
    end

    -- 1. SYNC: Hardware -> DOM
    local current_selection = selection or watcher.get_selection();
    local prompt_service = require("nzi.service.llm.prompt");
    local user_block = prompt_service.build_user_block(current_input, target_file, current_selection);

    modal.write(user_block, "user", false, current_turn_id);
    modal.set_thinking(true);

    local tag_parser = protocol.create_parser();
    local error_displayed = false;

    M.current_job = client.complete(function(success, result)
      vim.schedule(function()
        M.current_job = nil;
        modal.set_thinking(false);
        local duration = (vim.loop.hrtime() - start_time) / 1e9;

        if not success then
          if not error_displayed then modal.write(result, "error", false, current_turn_id); end
          M.finish();
          return;
        end

        tag_parser:feed("");
        local actions = tag_parser:get_actions();
        local remaining = tag_parser:get_remaining();

        if #actions == 0 and remaining:match("%S") then
          table.insert(actions, { name = "summary", content = remaining:gsub("^%s*", ""):gsub("%s*$", "") });
        end

        local metadata = {
          model = config.options.active_model or "unknown",
          duration = duration,
          changes = #actions
        };

        if #actions > 0 then
          -- EFFECT: DOM -> Hardware
          for _, action in ipairs(actions) do
            effector.dispatch(action, current_turn_id);
          end

          agent_actions.dispatch_actions(actions, mode, current_turn_id, function(combined_agent_response, signal, was_blocked)
            vim.schedule(function()
              if signal == "ABORTED" then
                modal.write("User aborted turn.", "system", false, current_turn_id);
                M.finish();
                return;
              end

              dom_session.add_turn(mode, user_block, result, metadata);

              if combined_agent_response and combined_agent_response ~= "" then
                current_input = combined_agent_response;
                if not was_blocked then
                  execute_turn();
                else
                  M.finish();
                end
              else
                M.finish();
              end
            end);
          end);
        else
          agent_actions.verify_state(current_turn_id, function(failure_response)
            vim.schedule(function()
              dom_session.add_turn(mode, user_block, result, metadata);
              if failure_response then
                current_input = failure_response;
                execute_turn();
              else
                M.finish();
              end
            end);
          end);
        end
      end);
    end, function(chunk, msg_type)
      vim.schedule(function()
        if msg_type == "error" then error_displayed = true end
        if msg_type == "content" then tag_parser:feed(chunk) end
        modal.write(chunk, msg_type, true, current_turn_id);
      end);
    end);
  end

  execute_turn();
end

function M.finish()
  M.is_busy = false;
  visuals.set_busy(false);
  modal.set_thinking(false);
  
  local queue = require("nzi.core.queue");
  local next_work = queue.pop_instruction();
  if next_work and not dom_query.is_blocked() then
    M.run_loop(next_work.instruction, next_work.mode, false, next_work.target_file, next_work.selection);
  end
end

function M.run_loop(content, mode, include_lsp, target_file, selection)
  return M.start_loop(content, mode, include_lsp, target_file, selection);
end

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
  if start_line == end_line and start_col > end_col then start_col, end_col = end_col, start_col; end
  local visual_mode = vim.fn.visualmode();
  if visual_mode == "V" then
    start_col = 0;
    end_col = #last_line_content;
  end
  local ok, lines = pcall(vim.api.nvim_buf_get_text, bufnr, start_line, start_col, end_line, end_col, {});
  local text = ok and table.concat(lines, "\n") or "";
  local file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.");
  return {
    text = text, file = file, start_line = start_line + 1, start_col = start_col + 1,
    end_line = end_line + 1, end_col = end_col, mode = visual_mode
  };
end

function M.execute_range(line1, line2)
  local bufnr = vim.api.nvim_get_current_buf();
  local lines = vim.api.nvim_buf_get_lines(bufnr, line1-1, line2, false);
  local parser = require("nzi.dom.parser");
  local row, type, content = parser.find_in_lines(lines);
  
  if type then
    local absolute_row = line1 + row - 1;
    vim.api.nvim_buf_set_lines(bufnr, absolute_row - 1, absolute_row, false, {});
    
    if type == "run" then
      require("nzi.service.vim.effector").run_shell(content);
    elseif type == "ask" then
      M.run_loop(content, "ask", false, nil, nil);
    elseif type == "instruct" then
      local cur_file = vim.api.nvim_buf_get_name(0);
      local relative_file = (cur_file ~= "") and vim.fn.fnamemodify(cur_file, ":.") or nil;
      M.run_loop(content, "instruct", false, relative_file, nil);
    elseif type == "internal" then
      require("nzi.core.commands").run(content);
    end
  else
    local selection = M.get_visual_selection();
    return M.run_loop("Analyze this", "ask", false, nil, selection);
  end
end

function M.execute_current_line()
  local line = vim.api.nvim_get_current_line();
  local parser = require("nzi.dom.parser");
  local parsed_type, content = parser.parse_line(line);
  
  if not parsed_type then
    print("No AI instruct found on current line.");
    return;
  end
  
  local row = vim.api.nvim_win_get_cursor(0)[1];
  vim.api.nvim_buf_set_lines(0, row - 1, row, false, {});
  
  if parsed_type == "run" then
    require("nzi.service.vim.effector").run_shell(content);
  elseif parsed_type == "ask" then
    M.run_loop(content, "ask", false, nil, nil);
  elseif parsed_type == "instruct" then
    local cur_file = vim.api.nvim_buf_get_name(0);
    local relative_file = (cur_file ~= "") and vim.fn.fnamemodify(cur_file, ":.") or nil;
    M.run_loop(content, "instruct", false, relative_file, nil);
  elseif parsed_type == "internal" then
    require("nzi.core.commands").run(content);
  end
end

return M;
