local config = require("nzi.core.config");
local M = {};

--- Gather the raw state of all relevant buffers.
--- This is sent to Python, which decides what to do with it.
function M.sync_list()
  local items = {};
  local bufs = vim.api.nvim_list_bufs();
  
  for _, bufnr in ipairs(bufs) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr);
      if name ~= "" then
        local relative_name = vim.fn.fnamemodify(name, ":.");
        
        -- Basic metadata
        table.insert(items, {
          name = relative_name,
          bufnr = bufnr,
          changedtick = vim.api.nvim_buf_get_var(bufnr, "changedtick"),
          is_modified = vim.api.nvim_get_option_value("modified", { buf = bufnr }),
          -- Only send content for small/active buffers to keep RPC light
          content = vim.api.nvim_get_option_value("modified", { buf = bufnr }) and 
                    table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n") or nil
        });
      end
    end
  end
  return items;
end

--- Capture current visual selection metadata
function M.get_selection()
  local mode = vim.fn.mode();
  if mode ~= 'v' and mode ~= 'V' and mode ~= '\22' then return nil end

  local start_pos = vim.fn.getpos("v");
  local end_pos = vim.fn.getpos(".");
  
  -- Normalize range
  local s_row, s_col = start_pos[2], start_pos[3];
  local e_row, e_col = end_pos[2], end_pos[3];
  if s_row > e_row or (s_row == e_row and s_col > e_col) then
    s_row, e_row = e_row, s_row;
    s_col, e_col = e_col, s_col;
  end

  local lines = vim.api.nvim_buf_get_lines(0, s_row - 1, e_row, false);
  if #lines == 0 then return nil end

  -- Handle character-wise selection (v)
  if mode == "v" then
    if #lines == 1 then
      lines[1] = lines[1]:sub(s_col, e_col);
    else
      lines[1] = lines[1]:sub(s_col);
      lines[#lines] = lines[#lines]:sub(1, e_col);
    end
  end

  local text = table.concat(lines, "\n");
  
  local cur_file = vim.api.nvim_buf_get_name(0);
  
  return {
    file = (cur_file ~= "") and vim.fn.fnamemodify(cur_file, ":.") or "unknown",
    start_line = s_row,
    start_col = s_col,
    end_line = e_row,
    end_col = e_col,
    text = text,
    mode = mode
  };
end

return M;
