local M = {};

--- Parse a single line for AI directives
--- @param line string: The raw line text
--- @return string | nil: The type of directive (shell, question, directive, command)
--- @return string | nil: The instruction content
function M.parse_line(line)
  local patterns = {
    directive = "[Aa][Ii]:",
    question = "[Aa][Ii]%?",
    shell = "[Aa][Ii]!",
    command = "[Aa][Ii]/"
  };

  for type, prefix in pairs(patterns) do
    local match = line:match("^.*" .. prefix .. "%s*(.*)$");
    if match then
      -- Clean up any trailing comment tags (e.g., -->, */, #])
      local content = match:gsub("%s*[-]*>$", ""):gsub("%s*%*/$", ""):gsub("%s*#]$", "");
      return type, content;
    end
  end

  return nil, nil;
end

--- Find the first AI directive in a range of lines
--- @param lines table: Array of strings
--- @return number | nil: The index of the line (1-based)
--- @return string | nil: The type of directive
--- @return string | nil: The instruction content
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
