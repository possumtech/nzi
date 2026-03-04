local M = {};

M.bufnr = nil;
M.winid = nil;
M.timer = nil;
M.current_open_tag = nil;
M.pending_cleanup = nil;
M.ns_id = vim.api.nvim_create_namespace("nzi_modal");

-- Precise background colors aligned 1:1 with OpenAI/Nzi Lexicon
local function setup_highlights()
  -- 1. INTERNAL / INFRASTRUCTURE (White on Black)
  vim.api.nvim_set_hl(0, "NziTelemetry", { bg = "#1d2021", fg = "#ebdbb2", ctermbg = 234, ctermfg = 15, bold = true });

  -- 2. EXTERNAL DATA (Distinct Opaque Backgrounds)
  vim.api.nvim_set_hl(0, "NziSystem", { bg = "#3c3836", fg = "#ebdbb2", ctermbg = 237, ctermfg = 15 });
  vim.api.nvim_set_hl(0, "NziContext", { bg = "#32302f", fg = "#a89984", ctermbg = 235, ctermfg = 246 }); 
  vim.api.nvim_set_hl(0, "NziHistory", { bg = "#32302f", fg = "#a89984", ctermbg = 235, ctermfg = 246 });
  vim.api.nvim_set_hl(0, "NziUser", { bg = "#427b58", fg = "#ffffff", ctermbg = 22, ctermfg = 15 });
  vim.api.nvim_set_hl(0, "NziAssistant", { bg = "#076678", fg = "#ebdbb2", ctermbg = 30, ctermfg = 15 });
  
  -- 3. STREAM COMPONENTS
  vim.api.nvim_set_hl(0, "NziReasoningContent", { bg = "#83a598", fg = "#282828", ctermbg = 12, ctermfg = 0 }); 
  vim.api.nvim_set_hl(0, "NziContent", { bg = "#458588", fg = "#ffffff", ctermbg = 18, ctermfg = 15 });
  
  vim.api.nvim_set_hl(0, "NziThinking", { fg = "#fe8019", ctermfg = 214, bold = true });
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

function M.open()
  local bufnr = get_or_create_buffer();
  if M.winid and vim.api.nvim_win_is_valid(M.winid) then return; end

  local config = require("nzi.config");
  local model_alias = config.options.active_model or "AI";
  local title = " " .. model_alias:upper() .. " " ;

  M.winid = vim.api.nvim_open_win(bufnr, false, {
    relative = "editor",
    width = math.floor(vim.o.columns * 0.8),
    height = math.floor(vim.o.lines * 0.8),
    col = math.floor(vim.o.columns * 0.1),
    row = math.floor(vim.o.lines * 0.1),
    style = "minimal", border = "rounded",
    title = title, title_pos = "center",
  });

  local opts = { buffer = bufnr, silent = true };
  vim.keymap.set("n", "q", M.close, opts);
  vim.keymap.set("n", "<Esc>", M.close, opts);
end

function M.set_thinking(active)
  local config = require("nzi.config");
  local model_alias = config.options.active_model or "AI";
  local default_title = " " .. model_alias:upper() .. " ";

  if active then
    if M.timer then return end
    local state = true
    M.timer = vim.loop.new_timer()
    M.timer:start(0, 500, vim.schedule_wrap(function()
      if M.winid and vim.api.nvim_win_is_valid(M.winid) then
        state = not state
        local title = state and " [ THINKING ] " or default_title
        vim.api.nvim_win_set_config(M.winid, { title = title })
      end
    end))
  else
    if M.timer then
      M.timer:stop(); M.timer:close(); M.timer = nil;
      if M.winid and vim.api.nvim_win_is_valid(M.winid) then
        vim.api.nvim_win_set_config(M.winid, { title = default_title })
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

function M.cancel_pending_prompt()
  if M.pending_cleanup then
    M.pending_cleanup();
    M.pending_cleanup = nil;
  end
end

local function get_tag_name(type)
  local map = {
    reasoning_content = "reasoning_content",
    content = "content",
    assistant = "assistant",
    system = "system",
    user = "user",
    context = "context",
    history = "history",
    shell = "shell_output",
    shell_output = "shell_output",
  };
  return map[type] or type;
end

local function get_hl_group(type)
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
  };
  return map[type] or "Normal";
end

local function _close_current_tag(bufnr)
  if not M.current_open_tag then return end
  local tag = get_tag_name(M.current_open_tag);
  local lc = vim.api.nvim_buf_line_count(bufnr);
  local tag_line = "</nzi:" .. tag .. ">";
  vim.api.nvim_buf_set_lines(bufnr, lc, lc, false, { tag_line });
  highlight_lines(bufnr, lc, lc, "NziTelemetry");
  M.current_open_tag = nil;
end

function M.close_tag()
  local bufnr = get_or_create_buffer();
  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr });
  _close_current_tag(bufnr);
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr });
end

local function get_telemetry_line(type)
  local config = require("nzi.config");
  local model_alias = config.options.active_model or "unknown";
  local opts = config.options.model_options or {};
  if type == "user" or type == "question" or type == "directive" then
    return string.format("[ USER | model: %s | temp: %.1f | top_p: %.1f ]", model_alias, opts.temperature or 0, opts.top_p or 0);
  elseif type == "reasoning_content" then
    return "[ ASSISTANT | reasoning_content | stream: active ]";
  elseif type == "content" then
    return "[ ASSISTANT | content | stream: active ]";
  elseif type == "shell" or type == "shell_output" then
    return "[ SYSTEM | shell_output | execution: complete ]";
  else
    return string.format("[ %s | context: %s ]", type:upper(), model_alias);
  end
end

function M.write(text, type, append)
  local bufnr = get_or_create_buffer();
  local tag = get_tag_name(type);
  if not append then M.cancel_pending_prompt(); end
  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr });

  -- 1. Structural Transitions
  if not append or (M.current_open_tag and M.current_open_tag ~= type) then
    _close_current_tag(bufnr);
    local lc = vim.api.nvim_buf_line_count(bufnr);
    local is_empty = (lc == 1 and vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] == "");
    
    local telemetry = get_telemetry_line(type);
    local open_tag = "<nzi:" .. tag .. ">";
    local lines_to_add = is_empty and { telemetry, open_tag } or { "", telemetry, open_tag };
    local start_idx = is_empty and 0 or lc;
    
    vim.api.nvim_buf_set_lines(bufnr, start_idx, -1, false, lines_to_add);
    
    -- Highlight Telemetry + Open Tag (White on Black)
    local h_start = start_idx + (is_empty and 0 or 1);
    highlight_lines(bufnr, h_start, h_start + 1, "NziTelemetry");
    
    M.current_open_tag = type;
    append = false; 
  elseif not M.current_open_tag then
    local telemetry = get_telemetry_line(type);
    local open_tag = "<nzi:" .. tag .. ">";
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { telemetry, open_tag });
    highlight_lines(bufnr, 0, 1, "NziTelemetry");
    M.current_open_tag = type;
    append = false;
  end

  -- 2. Content Injection
  local content_lines = vim.split(text, "\n");
  local hl_group = get_hl_group(type);
  local lc = vim.api.nvim_buf_line_count(bufnr);
  
  if append and lc > 0 then
    local last_idx = lc - 1;
    local last_line = vim.api.nvim_buf_get_lines(bufnr, last_idx, lc, false)[1] or "";
    vim.api.nvim_buf_set_lines(bufnr, last_idx, lc, false, { last_line .. content_lines[1] });
    highlight_lines(bufnr, last_idx, last_idx, hl_group);
    if #content_lines > 1 then
      local rem = {};
      for i = 2, #content_lines do table.insert(rem, content_lines[i]); end
      local current_lc = vim.api.nvim_buf_line_count(bufnr);
      vim.api.nvim_buf_set_lines(bufnr, current_lc, -1, false, rem);
      highlight_lines(bufnr, current_lc, current_lc + #rem - 1, hl_group);
    end
  else
    local current_lc = vim.api.nvim_buf_line_count(bufnr);
    vim.api.nvim_buf_set_lines(bufnr, current_lc, -1, false, content_lines);
    highlight_lines(bufnr, current_lc, current_lc + #content_lines - 1, hl_group);
  end

  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr });
  if M.winid and vim.api.nvim_win_is_valid(M.winid) then
    vim.api.nvim_win_set_cursor(M.winid, { vim.api.nvim_buf_line_count(bufnr), 0 });
  end
end

function M.clear()
  local bufnr = get_or_create_buffer();
  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr });
  _close_current_tag(bufnr);
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {});
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns_id, 0, -1);
  M.current_open_tag = nil;
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr });
end

function M.recolor_last_lines(count, type)
  local bufnr = get_or_create_buffer();
  local lc = vim.api.nvim_buf_line_count(bufnr);
  local hl_group = get_hl_group(type);
  highlight_lines(bufnr, math.max(0, lc - count), lc - 1, hl_group);
end

return M;
