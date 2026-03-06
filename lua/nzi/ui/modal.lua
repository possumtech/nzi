local M = {};

M.bufnr = nil;
M.winid = nil;
M.timer = nil;
M.current_open_tag = nil;
M.ns_id = vim.api.nvim_create_namespace("nzi_modal");

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
    -- Expand user and content tags
    if line:match("^<agent:user>") or line:match("^<agent:content>") then
      return "0"
    end
    -- Fold other tags
    return ">1"
  end

  if line:match("^</agent:[%w_]+>") then
    -- Closing tags match their opening level
    if line:match("^</agent:user>") or line:match("^</agent:content>") then
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
  local diff = require("nzi.ui.diff");
  local model_alias = (config.options.active_model or "AI"):upper();
  local branch = vim.fn.system("git branch --show-current 2>/dev/null"):gsub("\n", "");
  local diff_count = diff.get_count();
  local diff_str = diff_count > 0 and string.format(" [ DIFF: %d ] ", diff_count) or "";

  if branch ~= "" then
    return string.format(" %s :: %s%s", model_alias, branch, diff_str);
  end
  return string.format(" %s%s", model_alias, diff_str);
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
end

function M.set_thinking(active)
  local default_title = get_title();

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

--- Lexicon Mapping
local function get_tag_name(type)
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
    error = "NziError",
  };
  return map[type] or "Normal";
end

local function get_telemetry_line(type)
  local config = require("nzi.core.config");
  local model_alias = config.options.active_model or "unknown";
  local opts = config.options.model_options or {};
  if type == "user" or type == "ask" or type == "instruct" then
    return string.format("[ USER | model: %s | temp: %.1f | top_p: %.1f ]", model_alias, opts.temperature or 0, opts.top_p or 0);
  elseif type == "reasoning_content" then
    return "[ ASSISTANT | reasoning | stream: active ]";
  elseif type == "content" then
    return "[ ASSISTANT | content | stream: active ]";
  elseif type == "shell" or type == "shell_output" then
    return "[ SYSTEM | shell_output | execution: complete ]";
  elseif type == "error" then
    return "[ SYSTEM | error | state: failure ]";
  else
    return string.format("[ %s | context: %s ]", type:upper(), model_alias);
  end
end

--- Internal helper to close the currently open section
local function _close_current_tag(bufnr)
  if not M.current_open_tag then return end
  local type = M.current_open_tag;
  local tag = get_tag_name(type);
  local lc = vim.api.nvim_buf_line_count(bufnr);
  local tag_line = "</" .. tag .. ">";
  vim.api.nvim_buf_set_lines(bufnr, lc, lc, false, { tag_line });
  highlight_lines(bufnr, lc, lc, "NziTelemetry");
  
  -- AUTO-FOLD Reasoning when finished
  if type == "reasoning_content" then
    if M.winid and vim.api.nvim_win_is_valid(M.winid) then
      -- Find the opening tag for this reasoning block
      local start_line = -1;
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
      for i = #lines, 1, -1 do
        if lines[i]:match("^<agent:reasoning>") then
          start_line = i;
          break;
        end
      end
      
      if start_line ~= -1 then
        -- Neovim folds are slightly tricky; we set the fold level in the foldexpr
        -- But for reasoning specifically, we can force a fold here.
        vim.api.nvim_win_call(M.winid, function()
          vim.cmd(tostring(start_line) .. "foldclose");
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

function M.write(text, type, append)
  if not text or text == "" then return end
  local bufnr = get_or_create_buffer();
  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr });

  -- 1. Structural Transitions
  if (M.current_open_tag and M.current_open_tag ~= type) or (not append and M.current_open_tag) then
    _close_current_tag(bufnr);
  end

  if not M.current_open_tag then
    local lc = vim.api.nvim_buf_line_count(bufnr);
    local is_empty = (lc == 1 and vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] == "");
    
    local telemetry = get_telemetry_line(type);
    local open_tag = "<" .. get_tag_name(type) .. ">";
    local header = is_empty and { telemetry, open_tag } or { "", telemetry, open_tag };
    local start_idx = is_empty and 0 or lc;
    
    vim.api.nvim_buf_set_lines(bufnr, start_idx, -1, false, header);
    highlight_lines(bufnr, start_idx, start_idx + #header - 1, "NziTelemetry");
    M.current_open_tag = type;
    append = false; -- First write in a section is never an "append" to existing text

    -- Ensure reasoning is EXPANDED when starting
    if type == "reasoning_content" and M.winid and vim.api.nvim_win_is_valid(M.winid) then
      vim.api.nvim_win_call(M.winid, function()
        pcall(vim.cmd, "normal! zR"); -- Expand all just in case
      end);
    end
  end

  -- 2. Content Injection
  local content_lines = vim.split(text, "\n");
  local hl_group = get_hl_group(type);
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
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr });
end

return M;
