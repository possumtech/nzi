local M = {};

--- Resolve a relative path to an absolute path within the workspace
--- @param relative_path string
--- @return string|nil, string|nil (path, error)
function M.resolve(relative_path)
  if not relative_path or relative_path == "" then return nil, "No path provided" end
  
  -- Clean up leading ./
  local clean = relative_path:gsub("^%./", "");
  
  local cwd = vim.fn.getcwd();
  local full = cwd .. "/" .. clean;
  
  if vim.fn.filereadable(full) == 1 or vim.fn.isdirectory(full) == 1 then
    return clean, nil;
  end
  
  return nil, "File not found: " .. clean;
end

return M;
