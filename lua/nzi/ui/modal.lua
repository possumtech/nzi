local M = {};

M.bufnr = nil;
M.winid = nil;
M.timer = nil;
M.current_open_tag = nil; -- Tracks the turn level
M.current_open_turn_id = nil;
M.current_open_sub_tag = nil; -- Tracks blocks inside a turn

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
  
  return string.format("<session xmlns:nzi=\"nzi\" xmlns:agent=\"nzi\" xmlns:model=\"nzi\" model=\"%s\" yolo=\"%s\" roadmap=\"%s\">", 
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

function M.refresh_session_header()
  local bufnr = M.get_or_create_buffer();
  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr });
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false);
  if lines[1] and lines[1]:match("^<session") then
    vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { get_session_header() });
    highlight_lines(bufnr, 0, 0, "NziTelemetry");
  end
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr });
end

local function get_tag_name(msg_type)
  local map = {
    reasoning_content = "agent:reasoning",
    content = "agent:content",
    user = "agent:user",
    ask = "agent:user",
    instruct = "agent:user",
    system = "agent:status",
    error = "agent:status level='error'",
    shell = "agent:shell_output",
    shell_output = "agent:shell_output",
    response = "agent:content"
  };
  return map[msg_type] or "agent:status";
end

local function get_hl_group(msg_type)
  if msg_type == "reasoning_content" then return "Comment" end
  if msg_type == "user" or msg_type == "ask" or msg_type == "instruct" then return "NziStatusActive" end
  if msg_type == "error" then return "ErrorMsg" end
  return "Normal";
end

local function get_telemetry_line(msg_type, id, metadata)
  local config = require("nzi.core.config");
  local model_alias = config.options.active_model or "unknown";
  
  if msg_type == "turn" then
    local meta_str = "";
    if metadata and metadata.model then
      meta_str = string.format(" | %s | %.2fs | %d acts", metadata.model, metadata.duration or 0, metadata.changes or 0);
    else
      meta_str = string.format(" | %s", model_alias);
    end
    return string.format("[ TURN %d%s ]", id, meta_str);
  end

  if msg_type == "user" or msg_type == "ask" or msg_type == "instruct" then
    return ""; -- Let the XML tags speak for themselves
  elseif msg_type == "reasoning_content" then
    return "[ SYSTEM | reasoning ]";
  elseif msg_type == "content" then
    return ""; -- No header for primary content blocks
  elseif msg_type == "shell" or msg_type == "shell_output" then
    return "[ SYSTEM | shell_output ]";
  elseif msg_type == "error" then
    return "[ SYSTEM | error ]";
  else
    return string.format("[ %s ]", msg_type:upper());
  end
end

local function _close_sub_tag(bufnr)
  if not M.current_open_sub_tag then return end
  local tag = vim.split(get_tag_name(M.current_open_sub_tag), " ")[1];
  local lc = vim.api.nvim_buf_line_count(bufnr);
  vim.api.nvim_buf_set_lines(bufnr, lc - 1, lc - 1, false, { "</" .. tag .. ">" });
  highlight_lines(bufnr, lc - 1, lc - 1, "NziTelemetry");
  M.current_open_sub_tag = nil;
end

local function _close_current_tag(bufnr)
  if not M.current_open_tag then return end
  _close_sub_tag(bufnr);
  local lc = vim.api.nvim_buf_line_count(bufnr);
  vim.api.nvim_buf_set_lines(bufnr, lc - 1, lc - 1, false, { "</agent:turn>", "" });
  highlight_lines(bufnr, lc - 1, lc - 1, "NziTelemetry");
  M.current_open_tag = nil;
  M.current_open_turn_id = nil;
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
  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr });
  
  M.current_open_tag = nil;
  M.current_open_sub_tag = nil;
  M.current_open_turn_id = nil;
  
  local full_xml = history.format();
  local lines = vim.split(full_xml, "\n");
  
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines);
  
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns_id, 0, -1);
  vim.api.nvim_buf_clear_namespace(bufnr, M.turn_ns_id, 0, -1);
  M.mark_to_turn = {};
  
  for i, line in ipairs(lines) do
    local idx = i - 1;
    if line:match("^<session") or line:match("^</session") or line:match("^%[ TURN") or line:match("^<agent:turn") or line:match("^</agent:turn>") or line:match("^<agent:ack") or line:match("^<agent:status") then
      highlight_lines(bufnr, idx, idx, "NziTelemetry");
    end
    
    local tid = tonumber(line:match("id=\"(%d+)\""));
    if tid then
      local mid = vim.api.nvim_buf_set_extmark(bufnr, M.turn_ns_id, idx, 0, {});
      M.mark_to_turn[mid] = tid;
    end
  end
  
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr });
end

function M.write(text, msg_type, append, turn_id, metadata)
  if not text or text == "" then return end
  local bufnr = M.get_or_create_buffer();
  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr });

  local target_tid = turn_id or 0;

  if M.current_open_tag == "turn" and M.current_open_turn_id ~= target_tid then
    _close_current_tag(bufnr);
  end

  if not M.current_open_tag then
    local config = require("nzi.core.config");
    local active_model = config.options.active_model or "AI";
    local telemetry = get_telemetry_line("turn", target_tid, metadata);
    local model_name = metadata and metadata.model or (target_tid == 0 and "system" or active_model);
    local open_tag = string.format("<agent:turn id=\"%d\" model=\"%s\">", target_tid, model_name);
    
    local lc = vim.api.nvim_buf_line_count(bufnr);
    local insert_idx = lc - 1;
    local lines_to_add = { "", telemetry, open_tag };
    vim.api.nvim_buf_set_lines(bufnr, insert_idx, insert_idx, false, lines_to_add);
    highlight_lines(bufnr, insert_idx, insert_idx + 2, "NziTelemetry");
    
    local mid = vim.api.nvim_buf_set_extmark(bufnr, M.turn_ns_id, insert_idx + 1, 0, {});
    M.mark_to_turn[mid] = target_tid;
    M.current_open_tag = "turn";
    M.current_open_turn_id = target_tid;
  end

  if M.current_open_sub_tag ~= msg_type then
    _close_sub_tag(bufnr);
    local tag = get_tag_name(msg_type);
    local telemetry = get_telemetry_line(msg_type);
    local lc = vim.api.nvim_buf_line_count(bufnr);
    local insert_idx = lc - 1;
    local lines_to_add = (telemetry ~= "") and { telemetry, "<" .. tag .. ">" } or { "<" .. tag .. ">" };
    vim.api.nvim_buf_set_lines(bufnr, insert_idx, insert_idx, false, lines_to_add);
    highlight_lines(bufnr, insert_idx, insert_idx + #lines_to_add - 1, "NziTelemetry");
    M.current_open_sub_tag = msg_type;
    append = false;
  end

  local content_lines = vim.split(text, "\n");
  local hl_group = get_hl_group(msg_type);
  local lc = vim.api.nvim_buf_line_count(bufnr);
  local insert_idx = lc - 1;
  
  if append and lc > 2 then
    local last_line = vim.api.nvim_buf_get_lines(bufnr, lc - 2, lc - 1, false)[1] or "";
    vim.api.nvim_buf_set_lines(bufnr, lc - 2, lc - 1, false, { last_line .. content_lines[1] });
    if #content_lines > 1 then
      local rem = {}; for i=2,#content_lines do table.insert(rem, content_lines[i]) end
      vim.api.nvim_buf_set_lines(bufnr, lc - 1, lc - 1, false, rem);
      highlight_lines(bufnr, lc - 2, lc + #rem - 2, hl_group);
    else
      highlight_lines(bufnr, lc - 2, lc - 2, hl_group);
    end
  else
    vim.api.nvim_buf_set_lines(bufnr, insert_idx, insert_idx, false, content_lines);
    highlight_lines(bufnr, insert_idx, insert_idx + #content_lines - 1, hl_group);
  end

  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr });
  if M.winid and vim.api.nvim_win_is_valid(M.winid) then
    local nlc = vim.api.nvim_buf_line_count(bufnr);
    pcall(vim.api.nvim_win_set_cursor, M.winid, { nlc, 0 });
  end
end

function M.clear()
  local bufnr = M.get_or_create_buffer();
  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr });
  M.current_open_tag = nil;
  M.current_open_sub_tag = nil;
  M.current_open_turn_id = nil;
  
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { get_session_header(), "</session>" });
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns_id, 0, -1);
  vim.api.nvim_buf_clear_namespace(bufnr, M.turn_ns_id, 0, -1);
  highlight_lines(bufnr, 0, 0, "NziTelemetry");
  highlight_lines(bufnr, 1, 1, "NziTelemetry");
  
  M.mark_to_turn = {};
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr });
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
  local bufnr = M.get_or_create_buffer();
  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr });
  _close_current_tag(bufnr);
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr });
end

return M;
