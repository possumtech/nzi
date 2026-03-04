local M = {};

--- Fetch the code definition for the symbol at the current cursor position
--- @return table | nil: { name = string, content = string, uri = string } or nil
function M.get_symbol_definition()
  local bufnr = vim.api.nvim_get_current_buf();
  local params = vim.lsp.util.make_position_params();
  
  -- Request definition from attached LSP clients (1 second timeout)
  local responses, err = vim.lsp.buf_request_sync(bufnr, "textDocument/definition", params, 1000);
  if err or not responses or vim.tbl_isempty(responses) then
    return nil;
  end

  -- Extract the first valid location from the responses
  local location = nil;
  for _, res in pairs(responses) do
    if res.result and not vim.tbl_isempty(res.result) then
      location = res.result[1] or res.result;
      break;
    end
  end
  
  if not location then return nil; end

  local target_uri = location.uri or location.targetUri;
  local target_buf = vim.uri_to_bufnr(target_uri);
  
  -- Ensure the target buffer is loaded to read its lines
  if not vim.api.nvim_buf_is_loaded(target_buf) then
    vim.fn.bufload(target_buf);
  end

  local range = location.range or location.targetSelectionRange;
  local start_line = range.start.line;
  local end_line = range["end"].line;
  
  -- Capture the definition plus a small window of context (10 lines after)
  local lines = vim.api.nvim_buf_get_lines(target_buf, start_line, end_line + 10, false);
  local content = table.concat(lines, "\n");

  return {
    uri = target_uri,
    content = content,
    line = start_line + 1
  };
end

return M;
