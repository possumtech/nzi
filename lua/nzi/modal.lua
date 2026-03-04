local M = {};

M.bufnr = nil;
M.winid = nil;

--- Create or retrieve the modal buffer
local function get_or_create_buffer()
  if not M.bufnr or not vim.api.nvim_buf_is_valid(M.bufnr) then
    M.bufnr = vim.api.nvim_create_buf(false, true);
    vim.api.nvim_set_option_value("filetype", "markdown", { buf = M.bufnr });
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = M.bufnr });
    vim.api.nvim_set_option_value("bufhidden", "hide", { buf = M.bufnr });
  end
  return M.bufnr;
end

--- Open the modal window
function M.open()
  local bufnr = get_or_create_buffer();
  
  -- If window already exists, focus it
  if M.winid and vim.api.nvim_win_is_valid(M.winid) then
    vim.api.nvim_set_current_win(M.winid);
    return;
  end

  local width = math.floor(vim.o.columns * 0.8);
  local height = math.floor(vim.o.lines * 0.8);
  
  M.winid = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    width = width,
    height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2,
    style = "minimal",
    border = "rounded",
    title = " nzi Modal ",
    title_pos = "center",
  });

  -- Keybindings for the modal
  local opts = { buffer = bufnr, silent = true };
  vim.keymap.set("n", "q", M.close, opts);
end

--- Close the modal window
function M.close()
  if M.winid and vim.api.nvim_win_is_valid(M.winid) then
    vim.api.nvim_win_close(M.winid, true);
  end
  M.winid = nil;
end

--- Toggle the modal window
function M.toggle()
  if M.winid and vim.api.nvim_win_is_valid(M.winid) then
    M.close();
  else
    M.open();
  end
end

--- Write text to the modal buffer
--- @param text string
--- @param append boolean | nil: Whether to append or overwrite
function M.write(text, append)
  local bufnr = get_or_create_buffer();
  local lines = vim.split(text, "\n");
  
  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr });
  if append then
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, lines);
  else
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines);
  end
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr });
  
  -- Automatically open if text is written? 
  -- Maybe only if the model "requires attention."
end

return M;
