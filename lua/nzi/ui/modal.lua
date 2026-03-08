local M = {};

M.bufnr = nil;
M.winid = nil;
M.timer = nil;

M.ns_id = vim.api.nvim_create_namespace("nzi_modal");
M.turn_ns_id = vim.api.nvim_create_namespace("nzi_turns");
M.mark_to_turn = {};

local function highlight_lines(bufnr, start_line, end_line, hl_group)
  for i = start_line, end_line do
    vim.api.nvim_buf_set_extmark(bufnr, M.ns_id, i, 0, {
      end_line = i + 1,
      hl_group = hl_group,
      hl_eol = true,
      priority = 1000,
    })
  end
end

local function get_session_header()
  local config = require("nzi.core.config");
  local model = config.options.active_model or "unknown";
  local yolo = config.options.yolo and "true" or "false";
  local roadmap = config.options.roadmap_file or "AGENTS.md";
  
  return string.format("<session model=\"%s\" yolo=\"%s\" roadmap=\"%s\">", 
    model, yolo, roadmap);
end

function M.get_or_create_buffer()
  if not M.bufnr or not vim.api.nvim_buf_is_valid(M.bufnr) then
    M.bufnr = vim.api.nvim_create_buf(false, true);
    vim.api.nvim_set_option_value("filetype", "aiLog", { buf = M.bufnr });
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = M.bufnr });
    vim.api.nvim_set_option_value("bufhidden", "hide", { buf = M.bufnr });
    vim.api.nvim_set_option_value("modifiable", true, { buf = M.bufnr });
    
    -- Initialize with valid XML structure
    vim.api.nvim_buf_set_lines(M.bufnr, 0, -1, false, { get_session_header(), "</session>" });
    highlight_lines(M.bufnr, 0, 0, "NziTelemetry");
    highlight_lines(M.bufnr, 1, 1, "NziTelemetry");
    
    vim.api.nvim_set_option_value("modifiable", false, { buf = M.bufnr });
  end
  return M.bufnr;
end

local function get_title()
  local config = require("nzi.core.config");
  local model_alias = config.options.active_model or "unknown";
  local status_str = "";
  if M.timer then
    local frames = { "   ", ".  ", ".. ", "...", " ..", "  ." };
    local frame = frames[(math.floor(vim.loop.hrtime() / 1e8) % #frames) + 1];
    status_str = " (Thinking" .. frame .. ")";
  end
  return string.format(" %s%s ", model_alias, status_str);
end

function M.open()
  local bufnr = M.get_or_create_buffer();
  if M.winid and vim.api.nvim_win_is_valid(M.winid) then return; end

  local width = math.floor(vim.o.columns * 0.8);
  local height = math.floor(vim.o.lines * 0.8);
  local row = math.floor((vim.o.lines - height) / 2);
  local col = math.floor((vim.o.columns - width) / 2);

  M.winid = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    border = "rounded",
    title = get_title(),
    title_pos = "center",
  });

  vim.api.nvim_set_option_value("wrap", true, { win = M.winid });
  vim.api.nvim_set_option_value("cursorline", true, { win = M.winid });
end

function M.close()
  if M.winid and vim.api.nvim_win_is_valid(M.winid) then
    vim.api.nvim_win_close(M.winid, true);
  end
  M.winid = nil;
end

function M.toggle()
  if M.winid and vim.api.nvim_win_is_valid(M.winid) then
    M.close();
  else
    M.open();
  end
end

function M.render_history()
  local history = require("nzi.dom.session");
  local bufnr = M.get_or_create_buffer();
  if not vim.api.nvim_buf_is_valid(bufnr) then return end

  -- Use a scheduled block to avoid race conditions with modifiable state
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then return end
    
    local ok, full_xml = pcall(history.format);
    if not ok or not full_xml then return end

    vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr });
    
    local lines = vim.split(full_xml, "\n");
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines);
    
    vim.api.nvim_buf_clear_namespace(bufnr, M.ns_id, 0, -1);
    vim.api.nvim_buf_clear_namespace(bufnr, M.turn_ns_id, 0, -1);
    M.mark_to_turn = {};
    
    for i, line in ipairs(lines) do
      local idx = i - 1;
      if line:match("^%s*<[/?]?[%a:]+") then
        highlight_lines(bufnr, idx, idx, "NziTelemetry");
      end
      
      local tid = tonumber(line:match("id=\"(%d+)\""));
      if tid and line:match("<turn") then
        local mid = vim.api.nvim_buf_set_extmark(bufnr, M.turn_ns_id, idx, 0, {});
        M.mark_to_turn[mid] = tid;
      end
    end
    
    vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr });
    
    -- Scroll to bottom if we are active
    if M.winid and vim.api.nvim_win_is_valid(M.winid) then
      local lc = vim.api.nvim_buf_line_count(bufnr);
      if lc > 0 then
        pcall(vim.api.nvim_win_set_cursor, M.winid, { lc, 0 });
      end
    end
  end);
end

function M.write(text, msg_type, append, turn_id, metadata)
  -- Pure projection: Just refresh
  M.render_history();
end

function M.clear()
  M.render_history();
end

function M.set_thinking(active)
  if active then
    if M.timer then return end
    M.timer = vim.loop.new_timer();
    M.timer:start(0, 100, vim.schedule_wrap(function()
      if M.winid and vim.api.nvim_win_is_valid(M.winid) then
        vim.api.nvim_win_set_config(M.winid, { title = get_title(), title_pos = "center" });
      end
    end));
    require("nzi.ui.visuals").start_thinking();
  else
    if M.timer then
      M.timer:stop();
      M.timer:close();
      M.timer = nil;
    end
    if M.winid and vim.api.nvim_win_is_valid(M.winid) then
      vim.api.nvim_win_set_config(M.winid, { title = get_title(), title_pos = "center" });
    end
    require("nzi.ui.visuals").stop_thinking();
  end
end

function M.close_tag()
  M.render_history();
end

--- Delete the turn under the cursor and all subsequent turns
function M.rewind()
  if not M.bufnr or not vim.api.nvim_buf_is_valid(M.bufnr) then return end
  
  local cursor_row = vim.api.nvim_win_get_cursor(0)[1] - 1;
  -- Search forward from start to find all preceding turn marks
  local marks = vim.api.nvim_buf_get_extmarks(M.bufnr, M.turn_ns_id, {0, 0}, {cursor_row, -1}, {});
  
  if #marks > 0 then
    -- The LAST mark before or at the cursor is our target turn
    local mid = marks[#marks][1];
    local turn_id = M.mark_to_turn[mid];
    if turn_id then
      local config = require("nzi.core.config");
      local session = require("nzi.dom.session");
      config.notify("Rewinding history from turn " .. turn_id, vim.log.levels.WARN);
      session.delete_after(turn_id);
    end
  end
end

return M;
