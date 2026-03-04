local M = {};

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
  
  -- Focus the original buffer and start the diff
  vim.api.nvim_set_current_buf(bufnr);
  vim.cmd("diffthis");
  
  -- Open temp buffer in a vertical split and start diff
  vim.cmd("vsplit");
  vim.api.nvim_set_current_buf(temp_buf);
  vim.cmd("diffthis");
  
  -- Keybinding to close the diff view (just closes the temp window)
  vim.keymap.set("n", "q", ":q<CR>", { buffer = temp_buf, silent = true });
  
  vim.notify("AI: Diff opened. Use 'do' (diff obtain) or 'dp' (diff put) to merge changes.", vim.log.levels.INFO);
end

return M;
