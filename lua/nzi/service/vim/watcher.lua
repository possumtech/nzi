local config = require("nzi.core.config");
local M = {};

--- Set the AI context state for a buffer
--- @param bufnr number
--- @param state string: "active", "read", "map", "ignore"
function M.set_state(bufnr, state)
  vim.api.nvim_buf_set_var(bufnr, "nzi_state", state);
  -- Trigger visual update
  require("nzi.ui.visuals").update_buffer(bufnr);
end

--- Get the current AI context state for a buffer
--- @param bufnr number
--- @return string
function M.get_state(bufnr)
  local ok, val = pcall(vim.api.nvim_buf_get_var, bufnr, "nzi_state");
  if ok then return val end
  
  -- Default heuristics if no explicit state set
  local current_buf = vim.api.nvim_get_current_buf();
  if bufnr == current_buf then return "active" end
  return "map"
end

--- Check if a buffer is a real file (not a plugin UI, etc.)
function M.is_real_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then return false end
  local buftype = vim.api.nvim_get_option_value("buftype", { buf = bufnr });
  if buftype ~= "" then return false end
  
  local full_path = vim.api.nvim_buf_get_name(bufnr);
  if full_path == "" then return false end
  
  -- Check against ignored filetypes from config
  local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr });
  for _, ignore in ipairs(config.options.context.ignore_filetypes) do
    if ft == ignore then return false end
  end
  
  return true
end

--- Gather the raw state of all relevant buffers.
function M.sync_list()
  local items = {};
  local bufs = vim.api.nvim_list_bufs();
  
  for _, bufnr in ipairs(bufs) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local full_path = vim.api.nvim_buf_get_name(bufnr);
      if full_path ~= "" then
        local relative_name = vim.fn.fnamemodify(full_path, ":.");
        local state = M.get_state(bufnr);

        if state ~= "ignore" then
          local item = {
            name = relative_name,
            state = state
          };

          -- Include content only for Active or Read context
          if state == "active" or state == "read" or vim.api.nvim_get_option_value("modified", { buf = bufnr }) then
            item.content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n");
          end

          table.insert(items, item);
        end
      end
    end
  end
  return items;
end

--- Capture current visual selection metadata with mode-aware text extraction
function M.get_selection()
  local mode = vim.fn.mode();
  if mode ~= 'v' and mode ~= 'V' and mode ~= '\22' then return nil end

  local start_pos = vim.fn.getpos("v");
  local end_pos = vim.fn.getpos(".");
  
  -- 1. Normalize range coordinates
  local s_row, s_col = start_pos[2], start_pos[3];
  local e_row, e_col = end_pos[2], end_pos[3];
  if s_row > e_row or (s_row == e_row and s_col > e_col) then
    s_row, e_row = e_row, s_row;
    s_col, e_col = e_col, s_col;
  end

  local lines = vim.api.nvim_buf_get_lines(0, s_row - 1, e_row, false);
  if #lines == 0 then return nil end

  -- 2. Mode-specific text extraction
  local extracted_text = ""
  if mode == "V" then
    -- Line mode: full lines are already in the 'lines' table
    extracted_text = table.concat(lines, "\n")
  elseif mode == "v" then
    -- Character mode: slice the start and end lines
    if #lines == 1 then
      lines[1] = lines[1]:sub(s_col, e_col)
    else
      lines[1] = lines[1]:sub(s_col)
      lines[#lines] = lines[#lines]:sub(1, e_col)
    end
    extracted_text = table.concat(lines, "\n")
  elseif mode == "\22" then
    -- Block mode: slice every line between s_col and e_col
    local block_lines = {}
    for _, line in ipairs(lines) do
      table.insert(block_lines, line:sub(s_col, e_col))
    end
    extracted_text = table.concat(block_lines, "\n")
  end

  local cur_file = vim.api.nvim_buf_get_name(0);
  
  return {
    file = (cur_file ~= "") and vim.fn.fnamemodify(cur_file, ":.") or "unknown",
    start_line = s_row,
    start_col = s_col,
    end_line = e_row,
    end_col = e_col,
    text = extracted_text,
    mode = mode
  };
end

return M;
