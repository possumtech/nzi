local M = {};

-- Map of original buffer IDs to their hidden "suggestion" buffer IDs
M.pending_reviews = {};
-- Map of file paths to be deleted
M.pending_deletions = {};

--- Apply a change immediately (for YOLO mode)
--- @param bufnr number
--- @param new_lines table
function M.apply_immediately(bufnr, new_lines)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines);
  -- If it's a real file, save it
  local name = vim.api.nvim_buf_get_name(bufnr);
  if name ~= "" and vim.fn.filereadable(name) == 1 then
    vim.api.nvim_buf_call(bufnr, function() vim.cmd("silent! write") end);
  end
end

--- Open a diff view from a raw string result
--- @param bufnr number
--- @param result string
function M.open_diff(bufnr, result)
  local config = require("nzi.config");
  local lines = vim.split(result, "\n");
  if config.options.yolo then
    M.apply_immediately(bufnr, lines);
  else
    M.propose_edit(bufnr, lines);
  end
end

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
  
  -- Use native Neovim tabs/windows for the diff
  vim.cmd("tab split");
  local win_orig = vim.api.nvim_get_current_win();
  vim.api.nvim_win_set_buf(win_orig, bufnr);
  
  vim.cmd("vsplit");
  local win_sugg = vim.api.nvim_get_current_win();
  vim.api.nvim_win_set_buf(win_sugg, suggestion_buf);
  
  -- MUST set diff mode in BOTH windows
  vim.api.nvim_win_call(win_orig, function() vim.cmd("diffthis") end);
  vim.api.nvim_win_call(win_sugg, function() vim.cmd("diffthis") end);
  
  -- Focus the original buffer so user can use 'do' (diff obtain) to pull from suggestion
  vim.api.nvim_set_current_win(win_orig);
  
  vim.notify("AI: Diff mode active. Use 'do'/'dp' to merge. Close tab when finished.", vim.log.levels.INFO);
end

--- Propose a file deletion for review
--- @param file_path string: The file to delete
function M.propose_deletion(file_path)
  M.pending_deletions[file_path] = true;
  vim.notify("AI: Marked for deletion: " .. file_path .. ". Use AI/accept to confirm.", vim.log.levels.WARN);
end

--- Finalize the review (Accept the current state of original buffer)
function M.accept(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr);
  local relative_name = vim.fn.fnamemodify(name, ":.");
  
  if M.pending_deletions[relative_name] then
    os.remove(vim.fn.getcwd() .. "/" .. relative_name);
    M.pending_deletions[relative_name] = nil;
    vim.api.nvim_buf_delete(bufnr, { force = true });
    vim.notify("AI: File deleted: " .. relative_name, vim.log.levels.INFO);
    return;
  end

  M.cleanup(bufnr);
  vim.notify("AI: Edit review finalized.", vim.log.levels.INFO);
end

--- Finalize and discard (Revert original buffer? Or just close suggestion?)
--- Logic: We assume the user has been editing 'bufnr' directly.
--- 'reject' just clears the suggestion.
function M.reject(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr);
  local relative_name = vim.fn.fnamemodify(name, ":.");
  
  if M.pending_deletions[relative_name] then
    M.pending_deletions[relative_name] = nil;
    vim.notify("AI: Deletion rejected: " .. relative_name, vim.log.levels.INFO);
    return;
  end

  M.cleanup(bufnr);
  vim.notify("AI: Suggestion discarded.", vim.log.levels.INFO);
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
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_call(win, function() vim.cmd("diffoff") end);
    end
  end
end

function M.get_count()
  local count = 0;
  for _ in pairs(M.pending_reviews) do count = count + 1 end
  for _ in pairs(M.pending_deletions) do count = count + 1 end
  return count;
end

function M.has_pending_diff(bufnr)
  return M.pending_reviews[bufnr] ~= nil or M.pending_deletions[vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.")] ~= nil;
end

return M;
