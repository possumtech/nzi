local M = {};

M.bufnr = nil;
M.winid = nil;
M.timer = nil;
M.last_type = nil;
M.ns_id = vim.api.nvim_create_namespace("nzi_modal");

-- Precise background colors for categorization
local function setup_highlights()
  -- User Handshake
  vim.api.nvim_set_hl(0, "NziQuestion", { bg = "#b8bb26", fg = "#282828", ctermbg = 10, ctermfg = 0 }); -- Light Green
  vim.api.nvim_set_hl(0, "NziDirective", { bg = "#427b58", fg = "#ffffff", ctermbg = 22, ctermfg = 15 }); -- Dark Green
  
  -- Model Communication
  vim.api.nvim_set_hl(0, "NziThought", { bg = "#83a598", fg = "#282828", ctermbg = 12, ctermfg = 0 }); -- Light Blue (Reasoning)
  vim.api.nvim_set_hl(0, "NziResponse", { bg = "#458588", fg = "#ffffff", ctermbg = 18, ctermfg = 15 }); -- Dark Blue (Actual Answer)
  
  -- Specialized
  vim.api.nvim_set_hl(0, "NziEdit", { bg = "#fb4934", fg = "#ffffff", ctermbg = 1, ctermfg = 15 }); -- Red (Reserved)
  vim.api.nvim_set_hl(0, "NziSystem", { bg = "#3c3836", fg = "#ebdbb2", ctermbg = 237, ctermfg = 15 }); -- Gray (The Law)
  vim.api.nvim_set_hl(0, "NziContext", { bg = "#32302f", fg = "#a89984", ctermbg = 235, ctermfg = 246 }); -- Deeper Gray (The Facts)
  vim.api.nvim_set_hl(0, "NziHistory", { bg = "#32302f", fg = "#a89984", ctermbg = 235, ctermfg = 246 }); -- Same as context
  vim.api.nvim_set_hl(0, "NziShell", { bg = "#076678", fg = "#ebdbb2", ctermbg = 30, ctermfg = 15 });
  
  -- Thinking state border
  vim.api.nvim_set_hl(0, "NziThinking", { fg = "#fe8019", ctermfg = 214, bold = true });
end

--- Create or retrieve the modal buffer
local function get_or_create_buffer()
  if not M.bufnr or not vim.api.nvim_buf_is_valid(M.bufnr) then
    M.bufnr = vim.api.nvim_create_buf(false, true);
    vim.api.nvim_set_option_value("filetype", "nziLog", { buf = M.bufnr });
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = M.bufnr });
    vim.api.nvim_set_option_value("bufhidden", "hide", { buf = M.bufnr });
    vim.api.nvim_set_option_value("modifiable", false, { buf = M.bufnr });
    setup_highlights();
  end
  return M.bufnr;
end

--- Open the modal window
function M.open()
  local bufnr = get_or_create_buffer();
  if M.winid and vim.api.nvim_win_is_valid(M.winid) then return; end

  local config = require("nzi.config");
  local model_alias = config.options.active_model or "AI";
  local title = " " .. model_alias:upper() .. " " ;

  local width = math.floor(vim.o.columns * 0.8);
  local height = math.floor(vim.o.lines * 0.8);
  
  M.winid = vim.api.nvim_open_win(bufnr, false, {
    relative = "editor",
    width = width, height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2,
    style = "minimal", border = "rounded",
    title = title, title_pos = "center",
  });

  local opts = { buffer = bufnr, silent = true };
  vim.keymap.set("n", "q", M.close, opts);
  vim.keymap.set("n", "<Esc>", M.close, opts);
  
  -- Disable insert mode keys to prevent accidental edits
  vim.keymap.set("n", "i", "<nop>", opts);
  vim.keymap.set("n", "a", "<nop>", opts);
  vim.keymap.set("n", "o", "<nop>", opts);
  vim.keymap.set("n", "I", "<nop>", opts);
  vim.keymap.set("n", "A", "<nop>", opts);
  vim.keymap.set("n", "O", "<nop>", opts);
end

--- Set the "Thinking" state
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
      M.timer:stop()
      M.timer:close()
      M.timer = nil
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

--- Apply background color to a range of lines
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

--- Write text to the modal buffer
function M.write(text, type, append)
  local bufnr = get_or_create_buffer();

  -- Headers for different sections
  local emoji_map = {
    thought = "💭 REASONING:\n",
    model = "✨ ANSWER:\n",
    response = "✨ ANSWER:\n",
    shell = "🐚 SHELL OUTPUT:\n",
    system = "⚖️ SYSTEM PROMPT:\n",
    context = "📂 CONTEXT (BUFFERS):\n",
    history = "⏳ HISTORY:\n",
    question = "❓ QUESTION:\n",
    directive = "🛠️ DIRECTIVE:\n",
  };

  -- Handle Transitions and Initial Header
  if append and M.last_type and M.last_type ~= type then
    local transition_prefix = "\n\n" .. (emoji_map[type] or "");
    M.last_type = type; -- Set before recursion to prevent stack overflow
    M.write(transition_prefix, type, false);
    append = false;
  elseif not append and not M.last_type then
    -- First write of a session
    if emoji_map[type] then
      M.last_type = type; -- Set before recursion to prevent stack overflow
      M.write(emoji_map[type], type, false);
    end
  end
  M.last_type = type;

  local lines = vim.split(text, "\n");
  
  local hl_map = {
    system = "NziSystem",
    context = "NziContext",
    history = "NziHistory",
    question = "NziQuestion",
    directive = "NziDirective",
    thought = "NziThought",
    model = "NziResponse",
    response = "NziResponse",
    edit = "NziEdit",
    shell = "NziShell",
  };
  local hl_group = hl_map[type] or "Normal";

  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr });
  local line_count = vim.api.nvim_buf_line_count(bufnr);
  
  if append and line_count > 0 then
    local last_line_idx = line_count - 1;
    local last_line = vim.api.nvim_buf_get_lines(bufnr, last_line_idx, line_count, false)[1] or "";
    local updated_line = last_line .. lines[1];
    vim.api.nvim_buf_set_lines(bufnr, last_line_idx, line_count, false, { updated_line });
    highlight_lines(bufnr, last_line_idx, last_line_idx, hl_group);

    if #lines > 1 then
      local remaining = {};
      for i = 2, #lines do table.insert(remaining, lines[i]); end
      vim.api.nvim_buf_set_lines(bufnr, line_count, -1, false, remaining);
      highlight_lines(bufnr, line_count, line_count + #remaining - 1, hl_group);
    end
  else
    local insert_pos = (line_count == 1 and vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] == "") and 0 or line_count;
    vim.api.nvim_buf_set_lines(bufnr, insert_pos, -1, false, lines);
    highlight_lines(bufnr, insert_pos, insert_pos + #lines - 1, hl_group);
  end

  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr });
  
  local mode = vim.api.nvim_get_mode().mode;
  if M.winid and vim.api.nvim_win_is_valid(M.winid) then
    local cur_win = vim.api.nvim_get_current_win();
    if not (cur_win == M.winid and mode:match("[vV\22]")) then
      local last_line_count = vim.api.nvim_buf_line_count(bufnr);
      vim.api.nvim_win_set_cursor(M.winid, { last_line_count, 0 });
    end
  end
end

function M.clear()
  M.last_type = nil;
  local bufnr = get_or_create_buffer();
  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr });
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {});
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns_id, 0, -1);
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr });
end

--- Replace the highlight of a range of lines
function M.recolor_last_lines(count, type)
  local bufnr = get_or_create_buffer();
  local line_count = vim.api.nvim_buf_line_count(bufnr);
  local start_line = math.max(0, line_count - count);
  local hl_group = "Nzi" .. type:sub(1,1):upper() .. type:sub(2);
  
  highlight_lines(bufnr, start_line, line_count - 1, hl_group);
end

return M;
