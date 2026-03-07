local M = {};

--- Parse a single line for AI instructs in-buffer (Legacy feature)
function M.parse_line(line)
  local patterns = {
    instruct = ":[Aa][Ii]:",
    ask = ":[Aa][Ii]%?",
    run = ":[Aa][Ii]!",
    internal = ":[Aa][Ii]/"
  };

  for type, prefix in pairs(patterns) do
    local match = line:match("^" .. prefix .. "%s*(.*)$");
    if match then
      local content = match:gsub("%s*[-]*>$", ""):gsub("%s*%*/$", ""):gsub("%s*#]$", "");
      return type, content;
    end
  end
  return nil, nil;
end

--- Find the first AI instruct in a range of lines
function M.find_in_lines(lines)
  for i, line in ipairs(lines) do
    local type, content = M.parse_line(line);
    if type then return i, type, content; end
  end
  return nil, nil, nil;
end

--- Execute an XPath query on an XML string (Delegated to Python SSOT)
--- @param xml_str string: Ignored (SSOT is in Python memory)
--- @param query string: The XPath expression
--- @return table: List of results (strings)
function M.xpath(xml_str, query)
  local session = require("nzi.dom.session");
  return session.xpath(query);
end

function M.get_attr(xml_node, key)
  if not xml_node then return nil end
  -- Heuristic extraction since we don't want to round-trip back to python for every attribute
  local pattern1 = key .. "%s*=%s*\"([^\"]+)\""
  local pattern2 = key .. "%s*=%s*'([^']+)'"
  return xml_node:match(pattern1) or xml_node:match(pattern2)
end

return M;
