local context = require("nzi.context.context");
local parser = require("nzi.engine.parser");

local M = {};

--- Open the buffer management UI in an idiomatic fuzzy-finder style list
function M.open_ui()
  local buffers = vim.api.nvim_list_bufs();
  local items = {};

  for _, b in ipairs(buffers) do
    if context.is_real_buffer(b) then
      local name = vim.api.nvim_buf_get_name(b);
      local state = context.get_state(b);
      local short_name = vim.fn.fnamemodify(name, ":.");
      
      -- Map state to a pretty label
      local state_label = state:sub(1,1):upper() .. state:sub(2);
      local label = string.format("[%s] %s", state_label, short_name);
      
      table.insert(items, { label = label, bufnr = b, name = short_name });
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
    if sa ~= sb then return sa < sb end 
    return a.name < b.name
  end);

  local labels = {};
  for _, item in ipairs(items) do table.insert(labels, item.label) end

  vim.ui.select(labels, {
    prompt = "AI Buffer Context (Manage):",
  }, function(choice)
    if choice then
      local selected = nil;
      for _, item in ipairs(items) do
        if item.label == choice then selected = item; break end
      end
      
      if not selected then return end

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

--- Scan a buffer for AI directives and process them (Interpolation)
--- @param bufnr number
function M.interpolate(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  
  -- We only scan the FIRST 100 lines for performance and to avoid false positives
  -- in deep content, but usually AI: is at the top or in a comment.
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 100, false);
  local row, type, content = parser.find_in_lines(lines);
  
  if type then
    -- 1. Remove the line from the buffer
    vim.api.nvim_buf_set_lines(bufnr, row - 1, row, false, {});
    
    -- 2. Execute via engine (using a schedule to ensure the buffer removal is processed)
    vim.schedule(function()
      local engine = require("nzi.engine.engine");
      if type == "question" then
        engine.handle_question(content, false);
      elseif type == "shell" then
        require("nzi.tools.shell").run(content);
      elseif type == "directive" then
        engine.run_loop(content, "directive", false, vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":."));
      elseif type == "command" then
        require("nzi.core.commands").run(content);
      end
    end);
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("nzi_interpolation", { clear = true });
  
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = group,
    pattern = "*",
    callback = function(args)
      M.interpolate(args.buf);
    end,
  });
end

return M;
