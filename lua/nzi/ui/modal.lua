local M = {};

M.bufnr = nil;
M.winid = nil;
M.timer = nil;
M.current_open_tag = nil;
M.ns_id = vim.api.nvim_create_namespace("nzi_modal");
M.turn_ns_id = vim.api.nvim_create_namespace("nzi_turn_ids");
M.mark_to_turn = {}; -- Mapping of extmark IDs to turn IDs

-- Categorized Opaque Highlights
local function setup_highlights()
  vim.api.nvim_set_hl(0, "NziTelemetry", { bg = "#1d2021", fg = "#ebdbb2", ctermbg = 234, ctermfg = 15, bold = true });
  vim.api.nvim_set_hl(0, "NziSystem", { bg = "#3c3836", fg = "#ebdbb2", ctermbg = 237, ctermfg = 15 });
  vim.api.nvim_set_hl(0, "NziContext", { bg = "#32302f", fg = "#a89984", ctermbg = 235, ctermfg = 246 }); 
  vim.api.nvim_set_hl(0, "NziHistory", { bg = "#32302f", fg = "#a89984", ctermbg = 235, ctermfg = 246 });
  vim.api.nvim_set_hl(0, "NziUser", { bg = "#427b58", fg = "#ffffff", ctermbg = 22, ctermfg = 15 });
  vim.api.nvim_set_hl(0, "NziAssistant", { bg = "#076678", fg = "#ebdbb2", ctermbg = 30, ctermfg = 15 });
  vim.api.nvim_set_hl(0, "NziError", { bg = "#fb4934", fg = "#ffffff", ctermbg = 1, ctermfg = 15, bold = true });
  vim.api.nvim_set_hl(0, "NziReasoningContent", { bg = "#83a598", fg = "#282828", ctermbg = 12, ctermfg = 0 }); 
  vim.api.nvim_set_hl(0, "NziContent", { bg = "#458588", fg = "#ffffff", ctermbg = 18, ctermfg = 15 });
  vim.api.nvim_set_hl(0, "NziThinking", { fg = "#fe8019", ctermfg = 214, bold = true });
end

--- Folding expression for nzi modal
--- Folds everything except user and content tags
_G.nzi_modal_foldexpr = function(lnum)
  local line = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1] or ""
  
  if line:match("^<agent:[%w_]+>") then
    -- Fold all tags that represent a completed turn (have an ID)
    -- or tags that are not the primary interactive ones
    if line:match(" id=\"%d+\"") then
      return ">1"
    end
    
    -- Expand current user and content tags
    if line:match("^<agent:user>") or line:match("^<agent:content>") then
      return "0"
    end
    -- Fold other tags (reasoning, summary, context, etc.)
    return ">1"
  end

  if line:match("^</agent:[%w_]+>") then
    -- Match closing logic
    local tag = line:match("^</agent:([%w_]+)>")
    if tag == "user" or tag == "content" then
      -- Search up for opening tag to see if it had an ID
      local search_line = lnum - 1
      while search_line > 0 do
        local prev_line = vim.api.nvim_buf_get_lines(0, search_line - 1, search_line, false)[1] or ""
        if prev_line:match("^<agent:" .. tag .. ">") then return "0" end
        if prev_line:match("^<agent:" .. tag .. " id=\"%d+\"") then return "<1" end
        if prev_line:match("^<agent:") then break end
        search_line = search_line - 1
      end
      return "0"
    end
    return "<1"
  end

  -- Keep current level
  return "="
end

local function get_or_create_buffer()
  if not M.bufnr or not vim.api.nvim_buf_is_valid(M.bufnr) then
    M.bufnr = vim.api.nvim_create_buf(false, true);
    vim.api.nvim_set_option_value("filetype", "aiLog", { buf = M.bufnr });
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = M.bufnr });
    vim.api.nvim_set_option_value("bufhidden", "hide", { buf = M.bufnr });
    vim.api.nvim_set_option_value("modifiable", false, { buf = M.bufnr });
    
    setup_highlights();
  end
  return M.bufnr;
end

local function get_title()
  local config = require("nzi.core.config");
  local visuals = require("nzi.ui.visuals");
  
  local model_alias = config.options.active_model or "AI";
  local branch = vim.fn.system("git branch --show-current 2>/dev/null"):gsub("\n", "");
  
  -- Get the same status info used in the global statusline
  local status_data = visuals.get_status_data();
  local status_str = status_data.text ~= "" and string.format(" %s ", status_data.text) or "";

  if branch ~= "" then
    return string.format(" %s :: %s%s", model_alias, branch, status_str);
  end
  return string.format(" %s%s", model_alias, status_str);
end

function M.open()
  local bufnr = get_or_create_buffer();
  if M.winid and vim.api.nvim_win_is_valid(M.winid) then return; end

  local title = get_title();

  M.winid = vim.api.nvim_open_win(bufnr, true, { -- ENTER = true for cursor focus
    relative = "editor",
    width = math.floor(vim.o.columns * 0.8),
    height = math.floor(vim.o.lines * 0.8),
    col = math.floor(vim.o.columns * 0.1),
    row = math.floor(vim.o.lines * 0.1),
    style = "minimal", border = "rounded",
    title = title, title_pos = "center",
  });

  -- Folding setup (Window-local)
  vim.wo[M.winid].foldmethod = "expr";
  vim.wo[M.winid].foldexpr = "v:lua.nzi_modal_foldexpr(v:lnum)";
  vim.wo[M.winid].foldlevel = 0;

  local opts = { buffer = bufnr, silent = true };
  vim.keymap.set("n", "q", M.close, opts);
  vim.keymap.set("n", "<Esc>", M.close, opts);
  vim.keymap.set("n", "X", function() M.handle_delete(true) end, opts);

  -- Prevent window hijacking: If they try to move away, close it
  vim.api.nvim_create_autocmd({ "WinLeave" }, {
    buffer = bufnr,
    once = true,
    callback = function() M.close() end,
  });
end

--- Find the turn ID at the current cursor position
local function get_turn_id_at_cursor()
  if not M.winid or not vim.api.nvim_win_is_valid(M.winid) then return nil end
  local cursor = vim.api.nvim_win_get_cursor(M.winid);
  local line = cursor[1] - 1; -- 0-indexed for extmarks

  -- Search for the closest extmark with a turn_id at or before current line
  local marks = vim.api.nvim_buf_get_extmarks(M.bufnr, M.turn_ns_id, { 0, 0 }, { line, -1 }, {});
  if #marks > 0 then
    local mark_id = marks[#marks][1];
    return M.mark_to_turn[mark_id];
  end
  return nil;
end


--- Handle turn deletion or rewind
--- @param is_rewind boolean: If true, delete everything after the turn as well
function M.handle_delete(is_rewind)
  local turn_id = get_turn_id_at_cursor();
  if not turn_id or type(turn_id) ~= "number" or turn_id == 0 then
    vim.notify("No turn selected for rewind.", vim.log.levels.WARN);
    return;
  end

  local history = require("nzi.context.history");
  local msg = "Rewind history to this turn?"
  if vim.fn.confirm(msg, "&Yes\n&No", 2) ~= 1 then return end

  history.delete_after(turn_id);
  M.render_history();
  vim.notify("History rewound.", vim.log.levels.INFO);
end

--- Clear modal and re-render everything from history
function M.render_history()
  local history = require("nzi.context.history");
  M.clear();
  
  local turns = history.get_all();
  for _, turn in ipairs(turns) do
    local user_clean = history.strip_line_numbers(turn.user);
    local assistant_clean = history.strip_line_numbers(turn.assistant);
    
    if user_clean ~= "" then
      M.write(user_clean, "user", false, turn.id, turn.metadata);
    end
    if assistant_clean ~= "" then
      M.write(assistant_clean, "assistant", false, turn.id, turn.metadata);
    end
  end
end

function M.set_thinking(active)
  if active then
    if M.timer then return end
    local state = true
    M.timer = vim.loop.new_timer()
    M.timer:start(0, 500, vim.schedule_wrap(function()
      if M.winid and vim.api.nvim_win_is_valid(M.winid) then
        state = not state
        local base_title = get_title();
        local title = state and " [ THINKING ] " or base_title
        vim.api.nvim_win_set_config(M.winid, { title = title })
      end
    end))
  else
    if M.timer then
      M.timer:stop(); M.timer:close(); M.timer = nil;
      if M.winid and vim.api.nvim_win_is_valid(M.winid) then
        vim.api.nvim_win_set_config(M.winid, { title = get_title() })
      end
    end
  end
end

function M.close()
  M.set_thinking(false)
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
    if M.winid then vim.api.nvim_set_current_win(M.winid); end
  end
end

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

--- Lexicon Mapping
local function get_tag_name(msg_type)
  local map = {
    reasoning_content = "agent:reasoning",
    content = "agent:content",
    assistant = "agent:summary", -- Maps 'assistant' (from agent.lua) to 'agent:summary'
    system = "agent:system",
    user = "agent:user",
    context = "agent:context",
    history = "agent:history",
    shell = "agent:shell_output",
    shell_output = "agent:shell_output",
    error = "agent:error",
  };
  return map[msg_type] or msg_type;
end

local function get_hl_group(msg_type)
  local map = {
    system = "NziSystem",
    user = "NziUser",
    assistant = "NziAssistant",
    reasoning_content = "NziReasoningContent",
    content = "NziContent",
    context = "NziContext",
    history = "NziHistory",
    shell_output = "NziAssistant",
    shell = "NziAssistant",
    error = "NziError",
  };
  return map[msg_type] or "Normal";
end

local function get_telemetry_line(msg_type, id, metadata)
  local config = require("nzi.core.config");
  local model_alias = config.options.active_model or "unknown";
  local opts = config.options.model_options or {};
  
  if id and type(id) == "number" and id > 0 then
    local meta_str = "";
    if metadata and metadata.model then
      meta_str = string.format(" | %s | %.2fs | %d acts", metadata.model, metadata.duration or 0, metadata.changes or 0);
    else
      meta_str = string.format(" | %s", model_alias);
    end
    return string.format("[ TURN %d%s ]", id, meta_str);
  end

  if msg_type == "user" or msg_type == "ask" or msg_type == "instruct" then
    return string.format("[ USER | model: %s | temp: %.1f | top_p: %.1f ]", model_alias, opts.temperature or 0, opts.top_p or 0);
  elseif msg_type == "reasoning_content" then
    return "[ ASSISTANT | reasoning | stream: active ]";
  elseif msg_type == "content" then
    return "[ ASSISTANT | content | stream: active ]";
  elseif msg_type == "shell" or msg_type == "shell_output" then
    return "[ SYSTEM | shell_output | execution: complete ]";
  elseif msg_type == "error" then
    return "[ SYSTEM | error | state: failure ]";
  else
    return string.format("[ %s | context: %s ]", msg_type:upper(), model_alias);
  end
end

--- Internal helper to close the currently open section
local function _close_current_tag(bufnr)
  if not M.current_open_tag then return end
  local msg_type = M.current_open_tag;
  local tag = get_tag_name(msg_type);
  local lc = vim.api.nvim_buf_line_count(bufnr);
  local tag_line = "</" .. tag .. ">";
  vim.api.nvim_buf_set_lines(bufnr, lc, lc, false, { tag_line });
  highlight_lines(bufnr, lc, lc, "NziTelemetry");
  
  -- AUTO-FOLD Reasoning or completed history turns
  if M.winid and vim.api.nvim_win_is_valid(M.winid) then
    local cursor = vim.api.nvim_win_get_cursor(M.winid);
    local line = cursor[1] - 1;
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, M.turn_ns_id, { 0, 0 }, { line, -1 }, {});
    
    local turn_id = nil;
    if #marks > 0 then
      local mark_id = marks[#marks][1];
      turn_id = M.mark_to_turn[mark_id];
    end

    if msg_type == "reasoning_content" or (turn_id and turn_id > 0) then
      -- Find the opening tag for this block
      local start_line = -1;
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
      local pattern = "^<" .. tag .. ".*>";
      for i = #lines, 1, -1 do
        if lines[i]:match(pattern) then
          start_line = i;
          break;
        end
      end
      
      if start_line ~= -1 then
        vim.api.nvim_win_call(M.winid, function()
          pcall(vim.cmd, tostring(start_line) .. "foldclose");
        end);
      end
    end
  end

  M.current_open_tag = nil;
end

function M.close_tag()
  local bufnr = get_or_create_buffer();
  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr });
  _close_current_tag(bufnr);
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr });
end

function M.write(text, msg_type, append, turn_id, metadata)
  if not text or text == "" then return end
  local bufnr = get_or_create_buffer();
  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr });

  -- 1. Structural Transitions
  if (M.current_open_tag and M.current_open_tag ~= msg_type) or (not append and M.current_open_tag) then
    _close_current_tag(bufnr);
  end

  if not M.current_open_tag then
    local lc = vim.api.nvim_buf_line_count(bufnr);
    local is_empty = (lc == 1 and vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] == "");
    
    local telemetry = get_telemetry_line(msg_type, turn_id, metadata);
    local tag = get_tag_name(msg_type);
    local meta_attrs = "";
    if turn_id and type(turn_id) == "number" and turn_id > 0 and metadata and metadata.model then
      meta_attrs = string.format(" id=\"%d\" model=\"%s\" duration=\"%.2f\" acts=\"%d\"", 
        turn_id, metadata.model, metadata.duration or 0, metadata.changes or 0);
    elseif turn_id and type(turn_id) == "number" and turn_id > 0 then
      meta_attrs = string.format(" id=\"%d\"", turn_id);
    end
    
    local open_tag = "<" .. tag .. meta_attrs .. ">";
    local header = is_empty and { telemetry, open_tag } or { "", telemetry, open_tag };
    local start_idx = is_empty and 0 or lc;
    
    vim.api.nvim_buf_set_lines(bufnr, start_idx, -1, false, header);
    highlight_lines(bufnr, start_idx, start_idx + #header - 1, "NziTelemetry");

    -- MARK THE TURN ID with an extmark in turn_ns_id
    if turn_id and type(turn_id) == "number" then
      local mid = vim.api.nvim_buf_set_extmark(bufnr, M.turn_ns_id, start_idx, 0, {});
      M.mark_to_turn[mid] = turn_id;
    end

    M.current_open_tag = msg_type;
    append = false; -- First write in a section is never an "append" to existing text

    -- Ensure reasoning is EXPANDED when starting
    if msg_type == "reasoning_content" and M.winid and vim.api.nvim_win_is_valid(M.winid) then
      vim.api.nvim_win_call(M.winid, function()
        pcall(vim.cmd, "normal! zR"); -- Expand all just in case
      end);
    end
  end

  -- 2. Content Injection
  local content_lines = vim.split(text, "\n");
  local hl_group = get_hl_group(msg_type);
  local lc = vim.api.nvim_buf_line_count(bufnr);
  
  if append and lc > 0 then
    -- Merge with last line
    local last_idx = lc - 1;
    local last_line = vim.api.nvim_buf_get_lines(bufnr, last_idx, lc, false)[1] or "";
    vim.api.nvim_buf_set_lines(bufnr, last_idx, lc, false, { last_line .. content_lines[1] });
    highlight_lines(bufnr, last_idx, last_idx, hl_group);
    
    if #content_lines > 1 then
      local remaining = {};
      for i = 2, #content_lines do table.insert(remaining, content_lines[i]); end
      local new_lc = vim.api.nvim_buf_line_count(bufnr);
      vim.api.nvim_buf_set_lines(bufnr, new_lc, new_lc, false, remaining);
      highlight_lines(bufnr, new_lc, new_lc + #remaining - 1, hl_group);
    end
  else
    -- Append as new lines
    local start_lc = vim.api.nvim_buf_line_count(bufnr);
    vim.api.nvim_buf_set_lines(bufnr, start_lc, start_lc, false, content_lines);
    highlight_lines(bufnr, start_lc, start_lc + #content_lines - 1, hl_group);
  end

  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr });
  
  if M.winid and vim.api.nvim_win_is_valid(M.winid) then
    local lc = vim.api.nvim_buf_line_count(bufnr);
    if lc > 0 then
      -- Ensure the window is still showing our buffer before moving cursor
      local win_buf = vim.api.nvim_win_get_buf(M.winid);
      if win_buf == bufnr then
        pcall(vim.api.nvim_win_set_cursor, M.winid, { lc, 0 });
      end
    end
  end
end

function M.clear()
  local bufnr = get_or_create_buffer();
  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr });
  M.current_open_tag = nil;
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {});
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns_id, 0, -1);
  vim.api.nvim_buf_clear_namespace(bufnr, M.turn_ns_id, 0, -1);
  M.mark_to_turn = {};
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr });
end

return M;
