local config = require("nzi.config");
local sitter = require("nzi.sitter");

local M = {};

-- Map of buffer IDs to their state (nil means default)
-- States: 'active' (read/write), 'read' (read-only context), 'ignore' (no context)
M.states = {};

--- Get the current state of a buffer
--- @param bufnr number
--- @return string
function M.get_state(bufnr)
  -- 1. Explicit User Override (Always wins)
  if M.states[bufnr] then return M.states[bufnr]; end

  local full_path = vim.api.nvim_buf_get_name(bufnr);
  if full_path == "" then return "ignore"; end

  -- 2. Git Authority (Active Ignore)
  -- If git explicitly ignores it (e.g. .env), it is ignored by default even if open.
  if M.is_git_ignored(full_path) then
    return "ignore";
  end

  -- 3. Passive Intent
  -- If it's a real buffer and not git-ignored, we default to active.
  return "active";
end

--- Set the state of a buffer and handle its lifecycle
--- @param bufnr_or_path any: Number or string path
--- @param state string: 'active', 'read', 'ignore', or 'map'
function M.set_state(bufnr_or_path, state)
  local bufnr;
  if type(bufnr_or_path) == "number" then
    bufnr = bufnr_or_path;
  else
    local num = tonumber(bufnr_or_path);
    if num then
      bufnr = num;
    else
      -- Only bufadd if it's a non-numeric string path
      local ok, res = pcall(vim.fn.bufadd, bufnr_or_path);
      if ok then bufnr = res; end
    end
  end
  
  -- Validation: If it's a number but not a valid buffer, we still track its state 
  -- (for unit tests like context_spec which uses arbitrary IDs)
  if not bufnr or type(bufnr) ~= "number" or bufnr == -1 then return end
  
  if state == "map" then
    -- "Dropping" to map means we stop holding the whole file in context.
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
      local is_modified = vim.api.nvim_get_option_value("modified", { buf = bufnr });
      local windows = vim.fn.win_findbuf(bufnr);
      
      if not is_modified and #windows == 0 then
        -- Safe to quietly close
        vim.api.nvim_buf_delete(bufnr, { unload = false });
      end
    end
    M.states[bufnr] = nil;
    return;
  end

  local valid_states = { active = true, read = true, ignore = true };
  if valid_states[state] then
    M.states[bufnr] = state;
    
    -- If setting to active/read, ensure it's loaded in the background
    if (state == "active" or state == "read") and vim.api.nvim_buf_is_valid(bufnr) and not vim.api.nvim_buf_is_loaded(bufnr) then
      vim.fn.bufload(bufnr);
    end
  end
end

--- Check if a path is ignored by git
--- @param path string
--- @return boolean
function M.is_git_ignored(path)
  if path == "" then return true; end
  -- git check-ignore returns 0 if ignored, 1 if not.
  vim.fn.system(string.format("git check-ignore -q '%s'", path));
  return vim.v.shell_error == 0;
end

--- Determine if a buffer is a "real" file buffer
--- @param bufnr number
--- @return boolean
function M.is_real_buffer(bufnr)
  if not vim.api.nvim_buf_is_loaded(bufnr) then return false; end
  if not vim.api.nvim_get_option_value("buflisted", { buf = bufnr }) then return false; end

  local name = vim.api.nvim_buf_get_name(bufnr);
  local buftype = vim.api.nvim_get_option_value("buftype", { buf = bufnr });
  local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr });

  -- Ignore special UI/system buftypes
  if buftype ~= "" and buftype ~= "acwrite" then return false; end

  -- Ignore specific filetypes from config (UI plugins)
  local opts = config.options.context;
  for _, ft in ipairs(opts.ignore_filetypes) do
    if filetype == ft then return false; end
  end

  -- Ignore unnamed buffers
  local short_name = vim.fn.fnamemodify(name, ":.");
  if short_name == "" or short_name == "." or short_name:match("^%s*$") then return false; end

  return true;
end

--- Get the "Universe" of files in the current project
--- @return table: List of relative paths tracked by git
function M.get_universe()
  -- Check if we are in a git repo first
  local is_git = vim.fn.system("git rev-parse --is-inside-work-tree 2>/dev/null"):match("true");
  if not is_git then return {}; end

  -- ONLY get tracked and staged files. 
  -- Untracked files (like .swp) are NOT part of the universe.
  local files = vim.fn.systemlist("git ls-files --cached --exclude-standard 2>/dev/null");
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

  -- Track which files we've handled
  local handled_files = {};

  -- 1. Process Open Buffers
  for _, bufnr in ipairs(buffers) do
    if M.is_real_buffer(bufnr) then
      local full_path = vim.api.nvim_buf_get_name(bufnr);
      local name = vim.fn.fnamemodify(full_path, ":.");
      local state = M.get_state(bufnr);

      -- Mark as handled so we don't duplicate it from the universe map
      handled_files[name] = true;

      if state ~= "ignore" then
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
        local content = table.concat(lines, "\n");
        
        table.insert(context, {
          bufnr = bufnr,
          name = name,
          state = state,
          content = content,
          size = #content,
        });
      end
    end
  end

  -- 2. Process Remaining Universe Files (Project Map)
  for _, path in ipairs(universe) do
    if not handled_files[path] then
      -- Mapped project files are already filtered by git ls-files --exclude-standard
      local content, err = sitter.get_skeleton(path);
      table.insert(context, {
        bufnr = nil, 
        name = path,
        state = "map",
        content = content,
        err = err,
        size = vim.fn.getfsize(path),
      });
    end
  end

  return context;
end

return M;
