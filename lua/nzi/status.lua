local M = {};

-- Track the number of active nzi-diff windows/buffers
M.active_diffs = 0;

--- Get the current status for the statusline
--- @return string
function M.get_status()
  if M.active_diffs == 0 then
    return "";
  end
  return string.format("nzi: %d diffs", M.active_diffs);
end

--- Increment the active diff count
function M.inc()
  M.active_diffs = M.active_diffs + 1;
  vim.api.nvim_exec_autocmds("User", { pattern = "NziStateChanged" });
end

--- Decrement the active diff count
function M.dec()
  M.active_diffs = math.max(0, M.active_diffs - 1);
  vim.api.nvim_exec_autocmds("User", { pattern = "NziStateChanged" });
end

return M;
