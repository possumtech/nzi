-- lua/nzi/sitter.lua
local M = {}

--- Map of filetypes to tree-sitter queries for symbol extraction
M.queries = {
  lua = [[
    (function_declaration name: [
      (identifier) @name
      (dot_index_expression) @name
    ] parameters: (parameters) @args)
    (assignment_statement 
      (variable_list 
        (variable (identifier) @name))
      (expression_list
        (function_definition parameters: (parameters) @args)))
  ]],
  python = [[
    (class_definition name: (identifier) @name)
    (function_definition 
      name: (identifier) @name 
      parameters: (parameters) @args)
  ]],
  javascript = [[
    (class_definition name: (identifier) @name)
    (function_declaration 
      name: (identifier) @name 
      parameters: (formal_parameters) @args)
    (variable_declarator 
      id: (identifier) @name
      value: (arrow_function parameters: (formal_parameters) @args))
  ]],
  typescript = [[
    (class_definition name: (identifier) @name)
    (function_declaration 
      name: (identifier) @name 
      parameters: (formal_parameters) @args)
    (interface_declaration name: (identifier) @name)
    (method_definition 
      name: (property_identifier) @name
      parameters: (formal_parameters) @args)
  ]],
}

--- Extract a skeleton (symbols and signatures) from a file path
--- @param path string: Relative path to the file
--- @return string | nil: The symbol skeleton
--- @return string | nil: Error message for user feedback
function M.get_skeleton(path)
  local filetype = vim.filetype.match({ filename = path })
  local query_str = M.queries[filetype]
  if not query_str then return nil, nil end

  -- Load file content into a temporary hidden buffer
  local ok_read, lines = pcall(vim.fn.readfile, path)
  if not ok_read or #lines == 0 then return nil, nil end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  local lang = vim.treesitter.language.get_lang(filetype) or filetype
  local ok_parser, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
  if not ok_parser or not parser then
    vim.api.nvim_buf_delete(bufnr, { force = true })
    return nil, string.format("Missing Tree-sitter parser for '%s'", filetype)
  end

  local tree = parser:parse()[1]
  local root = tree:root()
  local query = vim.treesitter.query.parse(lang, query_str)

  local symbols = {}
  local current_symbol = nil

  for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
    local name = query.captures[id]
    local text = vim.treesitter.get_node_text(node, bufnr)

    if name == "name" then
      if current_symbol then table.insert(symbols, current_symbol) end
      current_symbol = text
    elseif name == "args" and current_symbol then
      current_symbol = current_symbol .. text
      table.insert(symbols, current_symbol)
      current_symbol = nil
    end
  end
  if current_symbol then table.insert(symbols, current_symbol) end

  vim.api.nvim_buf_delete(bufnr, { force = true })

  if #symbols == 0 then return nil, nil end
  return "Symbols: " .. table.concat(symbols, ", ")
end

return M
