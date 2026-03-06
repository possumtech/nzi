local M = {};

--- Parse a single line for AI instructs
--- @param line string: The raw line text
--- @return string | nil: The type of instruct (shell, ask, instruct, command)
--- @return string | nil: The instruction content
function M.parse_line(line)
  local patterns = {
    instruct = ":[Aa][Ii]:",
    ask = ":[Aa][Ii]%?",
    run = ":[Aa][Ii]!",
    internal = ":[Aa][Ii]/"
  };

  for type, prefix in pairs(patterns) do
    -- Strictly anchor to start of line, no whitespace or comments allowed
    local match = line:match("^" .. prefix .. "%s*(.*)$");
    if match then
      -- Clean up any trailing comment tags (e.g., -->, */, #])
      -- (Though if we are strictly at BOL, these shouldn't exist unless the user put them there)
      local content = match:gsub("%s*[-]*>$", ""):gsub("%s*%*/$", ""):gsub("%s*#]$", "");
      return type, content;
    end
  end

  return nil, nil;
end

--- Find the first AI instruct in a range of lines
--- @param lines table: Array of strings
--- @return number | nil: The index of the line (1-based)
--- @return string | nil: The type of instruct
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
