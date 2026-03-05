local context = require("nzi.context");

local M = {};

--- Resolve a messy path from a model into a valid project-relative path
--- @param input_path string: The path provided by the model
--- @return string | nil: The resolved relative path
--- @return string | nil: Error or status message
function M.resolve(input_path)
  if not input_path or input_path == "" then return nil, "Empty path" end

  -- 1. Exact Match (Project Relative)
  if vim.fn.filereadable(vim.fn.getcwd() .. "/" .. input_path) == 1 then
    return input_path, nil
  end

  -- 2. Strip Absolute Path (Training Data Hallucination)
  -- If it looks like /home/user/repo/path/file.lua or C:\path\file.lua
  local stripped = input_path:match(".*/(.*)") or input_path:match(".*\\(.*)") or input_path
  
  -- 3. Universe Search (Fuzzy/Filename matching)
  local universe = context.get_universe();
  local candidates = {};
  
  for _, project_path in ipairs(universe) do
    -- Match if the filename is the same
    local filename = vim.fn.fnamemodify(project_path, ":t");
    if filename == stripped or project_path:match(input_path .. "$") then
      table.insert(candidates, project_path);
    end
  end

  if #candidates == 1 then
    return candidates[1], string.format("Resolved '%s' to '%s'", input_path, candidates[1]);
  elseif #candidates > 1 then
    return nil, string.format("Ambiguous path '%s'. Candidates: %s", input_path, table.concat(candidates, ", "));
  end

  -- 4. Final attempt: Just the filename
  for _, project_path in ipairs(universe) do
    if project_path:match(stripped .. "$") then
      table.insert(candidates, project_path);
    end
  end

  if #candidates == 1 then
    return candidates[1], string.format("Resolved '%s' to '%s'", input_path, candidates[1]);
  end

  return nil, "File not found in project universe: " .. input_path;
end

return M;
