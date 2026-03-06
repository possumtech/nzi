local M = {};

-- Map of original buffer IDs to metadata (sugg_buf, tab_id)
M.pending_diffs = {};
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
    vim.api.nvim_buf_call(bufnr, function() vim.cmd("silent! write!") end);
  end
end

--- Open a diff view from a raw string result
--- @param bufnr number
--- @param result string
function M.open_diff(bufnr, result)
  local config = require("nzi.core.config");
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
  local existing = M.pending_diffs[bufnr];
  
  if existing then
    -- Reuse existing suggestion buffer
    if vim.api.nvim_buf_is_valid(existing.suggestion_buf) then
      vim.api.nvim_buf_set_lines(existing.suggestion_buf, 0, -1, false, new_lines);
      vim.notify("AI: Updated existing diff for " .. vim.fn.fnamemodify(name, ":."), vim.log.levels.INFO);
      return;
    else
      -- Stale metadata, clean it up
      M.pending_diffs[bufnr] = nil;
    end
  end

  -- Create a scratch buffer for the suggestion
  local suggestion_buf = vim.api.nvim_create_buf(false, true);
  local sugg_name = name .. " (AI Suggestion)";
  
  -- If buffer name already exists (rare collision), try to find/delete it or use a unique name
  local old_sugg = vim.fn.bufnr(sugg_name);
  if old_sugg ~= -1 then
    vim.api.nvim_buf_delete(old_sugg, { force = true });
  end

  vim.api.nvim_buf_set_name(suggestion_buf, sugg_name);
  vim.api.nvim_set_option_value("filetype", ft, { buf = suggestion_buf });
  vim.api.nvim_buf_set_lines(suggestion_buf, 0, -1, false, new_lines);
  
  -- Use native Neovim tabs/windows for the diff
  vim.cmd("tab split");
  local tab_id = vim.api.nvim_get_current_tabpage();
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
  
  M.pending_diffs[bufnr] = { 
    suggestion_buf = suggestion_buf,
    tab_id = tab_id
  };

  vim.notify("AI: Diff mode active. Use 'do'/'dp' to merge. Close tab when finished.", vim.log.levels.INFO);
end

--- Propose a file deletion for diff
--- @param file_path string: The file to delete
function M.propose_deletion(file_path)
  M.pending_deletions[file_path] = true;
  vim.notify("AI: Marked for deletion: " .. file_path .. ". Use AI/accept to confirm.", vim.log.levels.WARN);
end

--- Find the original buffer ID if given a suggestion buffer ID
--- @param bufnr number
--- @return number|nil
function M.find_original_buffer(bufnr)
  if M.pending_diffs[bufnr] then return bufnr end
  for orig_buf, diff in pairs(M.pending_diffs) do
    if diff.suggestion_buf == bufnr then
      return orig_buf;
    end
  end
  return nil;
end

--- Finalize the diff (Accept the current state of original buffer)
function M.accept(bufnr)
  local actual_buf = M.find_original_buffer(bufnr);
  local config = require("nzi.core.config");
  if not actual_buf then
    -- Check for deletions
    local name = vim.api.nvim_buf_get_name(bufnr);
    local relative_name = vim.fn.fnamemodify(name, ":.");
    if M.pending_deletions[relative_name] then
      config.log(relative_name, "DIFF:DELETE");
      os.remove(vim.fn.getcwd() .. "/" .. relative_name);
      M.pending_deletions[relative_name] = nil;
      vim.api.nvim_buf_delete(bufnr, { force = true });
      vim.notify("AI: File deleted: " .. relative_name, vim.log.levels.INFO);
      return;
    end
    vim.notify("AI: No pending diff for this buffer.", vim.log.levels.WARN);
    return;
  end

  -- SAVE THE BUFFER (User requested)
  local name = vim.api.nvim_buf_get_name(actual_buf);
  local relative_name = vim.fn.fnamemodify(name, ":.");
  config.log(relative_name, "DIFF:ACCEPT");
  if name ~= "" and vim.api.nvim_buf_is_valid(actual_buf) then
    vim.api.nvim_buf_call(actual_buf, function() 
      vim.cmd("silent! write!");
    end);
  end

  M.cleanup(actual_buf);
  vim.notify("AI: Edit diff finalized and saved.", vim.log.levels.INFO);
end

--- Finalize and discard (Revert original buffer? Or just close suggestion?)
function M.reject(bufnr)
  local actual_buf = M.find_original_buffer(bufnr);
  local config = require("nzi.core.config");
  if not actual_buf then
    local name = vim.api.nvim_buf_get_name(bufnr);
    local relative_name = vim.fn.fnamemodify(name, ":.");
    if M.pending_deletions[relative_name] then
      config.log(relative_name, "DIFF:REJECT_DELETE");
      M.pending_deletions[relative_name] = nil;
      vim.notify("AI: Deletion rejected: " .. relative_name, vim.log.levels.INFO);
      return;
    end
    vim.notify("AI: No pending diff for this buffer.", vim.log.levels.WARN);
    return;
  end

  local name = vim.api.nvim_buf_get_name(actual_buf);
  local relative_name = vim.fn.fnamemodify(name, ":.");
  config.log(relative_name, "DIFF:REJECT");

  M.cleanup(actual_buf);
  vim.notify("AI: Suggestion discarded.", vim.log.levels.INFO);
end

--- Cleanup diff state and close suggest buffer
function M.cleanup(bufnr)
  local diff = M.pending_diffs[bufnr];
  if not diff then return end

  local sugg_buf = diff.suggestion_buf;
  local tab_id = diff.tab_id;
  
  M.pending_diffs[bufnr] = nil;

  if sugg_buf and vim.api.nvim_buf_is_valid(sugg_buf) then
    vim.api.nvim_buf_delete(sugg_buf, { force = true });
  end
  
  if tab_id and vim.api.nvim_tabpage_is_valid(tab_id) then
    vim.api.nvim_set_current_tabpage(tab_id);
    vim.cmd("tabclose");
  end

  -- Turn off diff mode in all windows showing this buffer if any are left
  if vim.api.nvim_buf_is_valid(bufnr) then
    local wins = vim.fn.win_findbuf(bufnr);
    for _, win in ipairs(wins) do
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_call(win, function() vim.cmd("diffoff") end);
      end
    end
  end
end

function M.get_count()
  local count = 0;
  for _ in pairs(M.pending_diffs) do count = count + 1 end
  for _ in pairs(M.pending_deletions) do count = count + 1 end
  return count;
end

function M.has_pending_diff(bufnr)
  return M.pending_diffs[bufnr] ~= nil or M.pending_deletions[vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":.")] ~= nil;
end

return M;
