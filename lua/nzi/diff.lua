local M = {};

-- Map of original buffer IDs to their hidden "suggestion" buffer IDs
M.pending_reviews = {};

--- Propose an edit by creating a diff view
--- @param bufnr number: The original buffer
--- @param new_lines table: The lines after surgical application
function M.propose_edit(bufnr, new_lines)
  local name = vim.api.nvim_buf_get_name(bufnr);
  local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr });
  
  -- Create a scratch buffer for the suggestion
  local suggestion_buf = vim.api.nvim_create_buf(false, true);
  vim.api.nvim_buf_set_name(suggestion_buf, name .. " (AI Suggestion)");
  vim.api.nvim_set_option_value("filetype", ft, { buf = suggestion_buf });
  vim.api.nvim_buf_set_lines(suggestion_buf, 0, -1, false, new_lines);
  
  M.pending_reviews[bufnr] = suggestion_buf;
  
  -- Trigger the diff UI in the current tab
  vim.cmd("tab split");
  local win_orig = vim.api.nvim_get_current_win();
  vim.api.nvim_win_set_buf(win_orig, bufnr);
  vim.cmd("diffthis");
  
  vim.cmd("vsplit");
  local win_sugg = vim.api.nvim_get_current_win();
  vim.api.nvim_win_set_buf(win_sugg, suggestion_buf);
  vim.cmd("diffthis");
  
  -- Focus back on original
  vim.api.nvim_set_current_win(win_orig);
  
  vim.notify("AI: Surgical edit proposed. Use 'ga' to Accept or 'gr' to Reject.", vim.log.levels.INFO);
end

--- Accept the pending edit for a buffer
function M.accept(bufnr)
  local sugg_buf = M.pending_reviews[bufnr];
  if not sugg_buf or not vim.api.nvim_buf_is_valid(sugg_buf) then return end
  
  local new_lines = vim.api.nvim_buf_get_lines(sugg_buf, 0, -1, false);
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines);
  
  M.cleanup(bufnr);
  vim.notify("AI: Edit applied.", vim.log.levels.INFO);
end

--- Reject the pending edit
function M.reject(bufnr)
  M.cleanup(bufnr);
  vim.notify("AI: Edit discarded.", vim.log.levels.INFO);
end

--- Cleanup diff state and close suggest buffer
function M.cleanup(bufnr)
  local sugg_buf = M.pending_reviews[bufnr];
  if sugg_buf and vim.api.nvim_buf_is_valid(sugg_buf) then
    vim.api.nvim_buf_delete(sugg_buf, { force = true });
  end
  M.pending_reviews[bufnr] = nil;
  
  -- Turn off diff mode in all windows showing this buffer
  local wins = vim.fn.win_findbuf(bufnr);
  for _, win in ipairs(wins) do
    vim.api.nvim_win_call(win, function() vim.cmd("diffoff") end);
  end
end

function M.get_count()
  local count = 0;
  for _ in pairs(M.pending_reviews) do count = count + 1 end
  return count;
end

function M.has_pending_diff(bufnr)
  return M.pending_reviews[bufnr] ~= nil;
end

return M;
