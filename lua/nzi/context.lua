local config = require("nzi.config");
local sitter = require("nzi.sitter");

local M = {};

-- Map of buffer IDs to their state (nil means default: 'active')
-- States: 'active' (read/write), 'read' (read-only context), 'ignore' (no context)
M.states = {};

--- Get the current state of a buffer
--- @param bufnr number
--- @return string
function M.get_state(bufnr)
  return M.states[bufnr] or "active";
end

--- Set the state of a buffer
--- @param bufnr number
--- @param state string: 'active', 'read', 'ignore'
function M.set_state(bufnr, state)
  local valid_states = { active = true, read = true, ignore = true };
  if valid_states[state] then
    M.states[bufnr] = state;
  end
end

--- Determine if a buffer should be ignored based on name or filetype
--- @param name string
--- @param filetype string
--- @return boolean
function M.should_ignore(name, filetype)
  local opts = config.options.context;
  
  -- Check filetype ignore list
  for _, ft in ipairs(opts.ignore_filetypes) do
    if filetype == ft then return true; end
  end
  
  -- Check name ignore patterns
  for _, pattern in ipairs(opts.ignore_files) do
    if name:find(pattern, 1, true) then return true; end
  end
  
  return false;
end

--- Get the "Universe" of files in the current project
--- @return table: List of relative paths in the git repo
function M.get_universe()
  -- Check if we are in a git repo first
  local is_git = vim.fn.system("git rev-parse --is-inside-work-tree 2>/dev/null"):match("true");
  if not is_git then return {}; end

  -- Get all files known to git (committed, staged, and untracked)
  local files = vim.fn.systemlist("git ls-files --cached --others --exclude-standard 2>/dev/null");
  if vim.v.shell_error ~= 0 then return {}; end

  local universe = {};
  local seen = {};

  for _, path in ipairs(files) do
    if path ~= "" and not seen[path] then
      table.insert(universe, path);
      seen[path] = true;
    end
  end
  
  table.sort(universe);
  return universe;
end

--- Gather all relevant buffer content for the model context
--- @return table: List of buffer objects with name, state, and content
function M.gather()
  local universe = M.get_universe();
  local buffers = vim.api.nvim_list_bufs();
  local context = {};

  -- Track which files we've handled (including ignored ones)
  local handled_files = {};

  -- 1. Process Open Buffers (Highest Priority)
  for _, bufnr in ipairs(buffers) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_get_option_value("buflisted", { buf = bufnr }) then
      local full_path = vim.api.nvim_buf_get_name(bufnr);
      local name = vim.fn.fnamemodify(full_path, ":.");
      local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr });
      local state = M.get_state(bufnr);

      -- Mark as handled regardless of state (active, read, or ignore)
      if name ~= "" then
        handled_files[name] = true;
      end

      if state ~= "ignore" and not M.should_ignore(name, filetype) then
        -- Skip unnamed/unsaved scratch buffers and dot-paths
        if name == "" or name == "." or name:match("^%s*$") then goto continue end

        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
        -- Skip buffers that are effectively empty (no content)
        if #lines == 0 or (#lines == 1 and lines[1] == "") then goto continue end
        
        local content = table.concat(lines, "\n");
        
        table.insert(context, {
          bufnr = bufnr,
          name = name,
          state = state,
          content = content,
          size = #content,
        });
      end
      ::continue::
    end
  end

  -- 2. Process Remaining Universe Files (Project Map)
  for _, path in ipairs(universe) do
    if not handled_files[path] then
      local filetype = vim.filetype.match({ filename = path });
      if not M.should_ignore(path, filetype or "") then
        local content, err = sitter.get_skeleton(path);
        table.insert(context, {
          bufnr = nil, -- Not in an open buffer
          name = path,
          state = "map",
          content = content,
          err = err,
          size = vim.fn.getfsize(path),
        });
      end
    end
  end

  return context;
end

return M;
