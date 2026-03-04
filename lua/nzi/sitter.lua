-- lua/nzi/sitter.lua
local M = {}

--- Map of filetypes to tree-sitter queries for symbol extraction
M.queries = {
  lua = [[
    (function_declaration name: (identifier) @name)
    (function_declaration name: (dot_index_expression) @name)
  ]],
  python = [[
    (class_definition name: (identifier) @name)
    (function_definition name: (identifier) @name)
  ]],
  javascript = [[
    (class_definition name: (identifier) @name)
    (function_definition name: (identifier) @name)
    (variable_declarator id: (identifier) @name)
  ]],
  typescript = [[
    (class_definition name: (identifier) @name)
    (function_definition name: (identifier) @name)
    (interface_declaration name: (identifier) @name)
  ]],
}

--- Extract a skeleton (symbols) from a file path
--- @param path string: Relative path to the file
--- @return string: A concise summary of symbols
function M.get_skeleton(path)
  local filetype = vim.filetype.match({ filename = path })
  local query_str = M.queries[filetype]
  if not query_str then return "[No metadata available]" end

  -- Load file content into a temporary hidden buffer
  local lines = vim.fn.readfile(path)
  if #lines == 0 then return "[Empty File]" end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  
  local lang = vim.treesitter.language.get_lang(filetype) or filetype
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
  if not ok or not parser then
    vim.api.nvim_buf_delete(bufnr, { force = true })
    return "[Tree-sitter parser not found]"
  end

  local tree = parser:parse()[1]
  local root = tree:root()
  local query = vim.treesitter.query.parse(lang, query_str)

  local symbols = {}
  for _, node, _ in query:iter_captures(root, bufnr, 0, -1) do
    local text = vim.treesitter.get_node_text(node, bufnr)
    if text ~= "" then
      table.insert(symbols, text)
    end
  end

  vim.api.nvim_buf_delete(bufnr, { force = true })

  if #symbols == 0 then return "[No symbols found]" end
  return "Symbols: " .. table.concat(symbols, ", ")
end

return M
