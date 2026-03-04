local context = require("nzi.context");

local M = {};

-- Mapping of line numbers in the UI buffer to actual buffer numbers
local line_to_bufnr = {};

--- Refresh the content of the buffer list UI
--- @param ui_bufnr number
function M.refresh(ui_bufnr)
  vim.api.nvim_set_option_value("modifiable", true, { buf = ui_bufnr });
  
  local buffers = vim.api.nvim_list_bufs();
  local lines = { " AI Buffer Context Manager", " ---------------------------", "" };
  line_to_bufnr = {};

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
        local line = string.format(" [%-7s] %d: %s", state_label, b, short_name);
        
        table.insert(lines, line);
        line_to_bufnr[#lines] = b;
      end
    end
  end

  table.insert(lines, "");
  table.insert(lines, " Actions: (a)active (r)read (i)ignore (q)quit");

  vim.api.nvim_buf_set_lines(ui_bufnr, 0, -1, false, lines);
  vim.api.nvim_set_option_value("modifiable", false, { buf = ui_bufnr });
end

--- Open the buffer management UI in a floating window
function M.open_ui()
  local ui_bufnr = vim.api.nvim_create_buf(false, true);
  vim.api.nvim_set_option_value("filetype", "aiBuffers", { buf = ui_bufnr });
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = ui_bufnr });

  local function set_state_and_refresh(state)
    local cursor = vim.api.nvim_win_get_cursor(0);
    local target_buf = line_to_bufnr[cursor[1]];
    if target_buf then
      context.set_state(target_buf, state);
      M.refresh(ui_bufnr);
      vim.api.nvim_win_set_cursor(0, cursor);
    end
  end

  -- Define UI keybindings
  local map_opts = { buffer = ui_bufnr, silent = true };
  vim.keymap.set("n", "a", function() set_state_and_refresh("active") end, map_opts);
  vim.keymap.set("n", "r", function() set_state_and_refresh("read") end, map_opts);
  vim.keymap.set("n", "i", function() set_state_and_refresh("ignore") end, map_opts);
  vim.keymap.set("n", "q", ":q<CR>", map_opts);

  M.refresh(ui_bufnr);

  -- Configure floating window
  local width = math.min(80, vim.o.columns - 4);
  local height = math.min(20, vim.o.lines - 4);
  
  vim.api.nvim_open_win(ui_bufnr, true, {
    relative = "editor",
    width = width,
    height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2,
    style = "minimal",
    border = "rounded",
    title = " AI Buffers ",
    title_pos = "center",
  });
end

function M.setup()
    -- Placeholder for future setup logic
end

return M;
