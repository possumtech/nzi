local M = {};

-- Set of buffer IDs that have pending AI suggestions
M.pending_diffs = {};

--- Check if a buffer has a pending AI diff
--- @param bufnr number
--- @return boolean
function M.has_pending_diff(bufnr)
  return M.pending_diffs[bufnr] == true;
end

--- Open a vertical diff split between the current buffer and new content
--- @param bufnr number: The original buffer to be modified
--- @param new_content string: The complete new content for the buffer
function M.open_diff(bufnr, new_content)
  local original_name = vim.api.nvim_buf_get_name(bufnr);
  local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr });
  
  -- Create a temporary, unlisted scratch buffer
  local temp_buf = vim.api.nvim_create_buf(false, true);
  local lines = vim.split(new_content, "\n");
  
  -- Remove trailing empty line if present
  if #lines > 0 and lines[#lines] == "" then
    table.remove(lines);
  end
  
  vim.api.nvim_buf_set_lines(temp_buf, 0, -1, false, lines);
  vim.api.nvim_set_option_value("filetype", ft, { buf = temp_buf });
  vim.api.nvim_buf_set_name(temp_buf, original_name .. " (AI-suggestion)");
  
  -- Mark as pending
  M.pending_diffs[bufnr] = true;
  require("nzi.visuals").refresh();

  -- Focus the original buffer and start the diff
  vim.api.nvim_set_current_buf(bufnr);
  vim.cmd("diffthis");
  
  -- Open temp buffer in a vertical split and start diff
  vim.cmd("vsplit");
  vim.api.nvim_set_current_buf(temp_buf);
  vim.cmd("diffthis");
  
  -- Keybinding to close the diff view
  -- When the diff is closed, we assume the user has finished reviewing.
  vim.keymap.set("n", "q", function()
    vim.cmd("q");
    M.pending_diffs[bufnr] = nil;
    require("nzi.visuals").refresh();
  end, { buffer = temp_buf, silent = true });
  
  vim.notify("AI: Diff opened. Use 'do' (diff obtain) or 'dp' (diff put) to merge changes. 'q' to finish.", vim.log.levels.INFO);
end

--- Navigate to the next buffer with a pending diff
function M.next()
  local bufs = vim.api.nvim_list_bufs();
  local current = vim.api.nvim_get_current_buf();
  local start_index = 1;
  
  for i, b in ipairs(bufs) do
    if b == current then start_index = i; break; end
  end

  for i = 1, #bufs do
    local idx = (start_index + i - 1) % #bufs + 1;
    local b = bufs[idx];
    if M.pending_diffs[b] then
      vim.api.nvim_set_current_buf(b);
      return;
    end
  end
  vim.notify("AI: No more pending diffs", vim.log.levels.INFO);
end

--- Navigate to the previous buffer with a pending diff
function M.prev()
  local bufs = vim.api.nvim_list_bufs();
  local current = vim.api.nvim_get_current_buf();
  local start_index = 1;
  
  for i, b in ipairs(bufs) do
    if b == current then start_index = i; break; end
  end

  for i = 1, #bufs do
    local idx = (start_index - i - 1) % #bufs + 1;
    local b = bufs[idx];
    if M.pending_diffs[b] then
      vim.api.nvim_set_current_buf(b);
      return;
    end
  end
  vim.notify("AI: No more pending diffs", vim.log.levels.INFO);
end

return M;
