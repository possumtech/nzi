local context = require("nzi.context");

local M = {};

-- Mapping of line numbers in the UI buffer to actual buffer numbers
local line_to_bufnr = {};

--- Open the buffer management UI in an idiomatic fuzzy-finder style list
function M.open_ui()
  local context = require("nzi.context");
  local buffers = vim.api.nvim_list_bufs();
  local items = {};

  for _, b in ipairs(buffers) do
    if vim.api.nvim_buf_is_loaded(b) then
      local name = vim.api.nvim_buf_get_name(b);
      local filetype = vim.api.nvim_get_option_value("filetype", { buf = b });
      
      -- Only show buffers that are not globally ignored
      if not context.should_ignore(name, filetype) then
        local state = context.get_state(b);
        local short_name = name ~= "" and vim.fn.fnamemodify(name, ":.") or "[No Name]";
        
        -- Map state to a pretty label
        local state_label = state:sub(1,1):upper() .. state:sub(2);
        local label = string.format("[%s] %s", state_label, short_name);
        
        table.insert(items, { label = label, bufnr = b, name = short_name });
      end
    end
  end

  if #items == 0 then
    vim.notify("AI: No manageable buffers found.", vim.log.levels.WARN);
    return;
  end

  -- Sort items: Active first, then Read, then Name
  table.sort(items, function(a, b)
    local sa = context.get_state(a.bufnr);
    local sb = context.get_state(b.bufnr);
    if sa ~= sb then return sa < sb end -- alphabetical active < read
    return a.name < b.name
  end);

  local labels = {};
  for _, item in ipairs(items) do table.insert(labels, item.label) end

  vim.ui.select(labels, {
    prompt = "AI Buffer Context (Manage):",
  }, function(choice)
    if choice then
      -- Identify selected buffer
      local selected = nil;
      for _, item in ipairs(items) do
        if item.label == choice then selected = item; break end
      end
      
      if not selected then return end

      -- Provide sub-menu for the selected buffer
      local actions = { "Set Active", "Set Read-only", "Ignore (Remove)", "Wipeout Buffer", "Jump to Buffer" };
      vim.ui.select(actions, {
        prompt = string.format("Action for '%s':", selected.name),
      }, function(action)
        if action == "Set Active" then
          context.set_state(selected.bufnr, "active");
        elseif action == "Set Read-only" then
          context.set_state(selected.bufnr, "read");
        elseif action == "Ignore (Remove)" then
          context.set_state(selected.bufnr, "ignore");
        elseif action == "Wipeout Buffer" then
          vim.api.nvim_buf_delete(selected.bufnr, { force = true });
        elseif action == "Jump to Buffer" then
          vim.api.nvim_set_current_buf(selected.bufnr);
        end
      end);
    end
  end);
end

function M.setup()
    -- Placeholder for future setup logic
end

return M;
