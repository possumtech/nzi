local M = {};

--- Resolve a relative path to an absolute path within the workspace
--- @param relative_path string
--- @return string|nil, string|nil (path, error)
function M.resolve(relative_path)
  if not relative_path or relative_path == "" then return nil, "No path provided" end
  
  -- 1. Block Absolute Paths (Hardware Rule)
  if relative_path:match("^/") or relative_path:match("^~") then
    return nil, "Absolute or home paths are forbidden: " .. relative_path;
  end

  -- 2. Normalize and check containment
  local cwd = vim.fn.getcwd();
  -- fnamemodify :p makes it absolute, simplify resolves ..
  local full = vim.fn.simplify(vim.fn.fnamemodify(cwd .. "/" .. relative_path, ":p"));
  
  -- PERMISSION OVERRIDE: Check if this file is explicitly in the user's sync list
  local watcher = require("nzi.service.vim.watcher");
  local items = watcher.sync_list();
  for _, item in ipairs(items) do
    -- watcher uses path for the relative or absolute name it sent to DOM
    if item.path == relative_path or item.path == full then
      return relative_path, nil;
    end
  end

  -- Escape CWD for pattern matching
  local escaped_cwd = cwd:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1");
  
  if not full:match("^" .. escaped_cwd) then
    return nil, "Path escapes project boundary: " .. relative_path;
  end

  -- 3. Return the relative path from CWD
  local final_rel = full:sub(#cwd + 2); -- +2 for the trailing slash
  
  -- Clean up double slashes or trailing slash
  final_rel = final_rel:gsub("//+", "/"):gsub("/$", "");
  
  return final_rel, nil;
end

return M;
