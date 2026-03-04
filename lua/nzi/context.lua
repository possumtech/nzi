local config = require("nzi.config");

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

--- Gather all relevant buffer content for the model context
--- @return table: List of buffer objects with name, state, and content
function M.gather()
  local buffers = vim.api.nvim_list_bufs();
  local context = {};

  for _, bufnr in ipairs(buffers) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_get_option_value("buflisted", { buf = bufnr }) then
      local name = vim.api.nvim_buf_get_name(bufnr);
      local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr });
      local state = M.get_state(bufnr);

      if state ~= "ignore" and not M.should_ignore(name, filetype) then
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
        local content = table.concat(lines, "\n");
        
        table.insert(context, {
          bufnr = bufnr,
          name = name,
          state = state,
          content = content,
        });
      end
    end
  end

  return context;
end

return M;
