local M = {};

--- Parse a single line for nzi directives
--- @param line string
--- @return string | nil: The type of directive ('directive', 'question', 'shell', 'command')
--- @return string | nil: The content of the directive
function M.parse_line(line)
  local patterns = {
    directive = "nzi:",
    question = "nzi%?",
    shell = "nzi!",
    command = "nzi/"
  };

  for type, prefix in pairs(patterns) do
    -- Match the prefix and everything after it
    local content = line:match(prefix .. "%s*(.*)");
    if content then
      -- Clean up trailing comment markers (e.g., ' */' in C-style languages)
      content = content:gsub("%s*%*/%s*$", "");
      -- Clean up trailing markdown markers if any
      content = content:gsub("%s*-->%s*$", "");
      
      return type, content;
    end
  end

  return nil, nil;
end

--- Find the first nzi directive in a range of lines
--- @param lines table: List of strings
--- @return number | nil: Line index (1-based)
--- @return string | nil: Type
--- @return string | nil: Content
function M.find_in_lines(lines)
  for i, line in ipairs(lines) do
    local type, content = M.parse_line(line);
    if type then
      return i, type, content;
    end
  end
  return nil, nil, nil;
end

return M;
