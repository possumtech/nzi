local M = {};

--- Resilient bridge-based parser for <model:*> tags and markdown code blocks
function M.create_parser()
  return {
    buffer = "",
    actions = {},
    
    feed = function(self, chunk)
      self.buffer = self.buffer .. chunk
      
      -- If chunk is empty, it's the end of the stream. Perform full parse.
      if chunk == "" then
        local config = require("nzi.core.config");
        local python_cmd = config.options.python_cmd[1] or "python3";
        local bridge_script = vim.fn.getcwd() .. "/lua/nzi/dom/bridge.py";

        local request = {
          action = "parse",
          text = self.buffer
        };

        local res = vim.fn.system({ python_cmd, bridge_script }, vim.fn.json_encode(request));
        local ok, data = pcall(vim.fn.json_decode, res);
        
        if ok and data.success then
          self.actions = data.actions or {};
          self.buffer = ""; -- Clear buffer after successful full parse
        else
          config.log("Parse Error: " .. (data and data.error or "JSON Parse Error"), "PROTOCOL");
        end
      end
    end,

    get_actions = function(self)
      local acts = self.actions
      self.actions = {}
      return acts
    end,

    get_remaining = function(self)
      local rem = self.buffer
      self.buffer = ""
      return rem
    end
  }
end

function M.get_attr(attr, key)
  if not attr then return nil end
  -- Handle new structured attributes table
  if type(attr) == "table" then
    return attr[key]
  end
  -- Legacy string pattern matching for attributes
  local pattern1 = key .. "%s*=%s*\"([^\"]+)\""
  local pattern2 = key .. "%s*=%s*'([^']+)'"
  return attr:match(pattern1) or attr:match(pattern2)
end

--- Parse a single line for AI instructs
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

--- Execute an XPath query on an XML string
--- @param xml_str string: The raw XML
--- @param xpath string: The XPath expression
--- @return table: List of results (strings)
function M.xpath(xml_str, xpath)
  local config = require("nzi.core.config");
  local python_cmd = config.options.python_cmd[1] or "python3";
  local bridge_script = vim.fn.getcwd() .. "/lua/nzi/dom/bridge.py";

  local request = {
    action = "xpath",
    xml = xml_str,
    query = xpath
  };

  local res = vim.fn.system({ python_cmd, bridge_script }, vim.fn.json_encode(request));
  local ok, data = pcall(vim.fn.json_decode, res);
  
  if not ok or not data.success then
    config.log("XPath Error: " .. (data and data.error or "JSON Parse Error"), "PROTOCOL");
    return {};
  end
  
  return data.results or {};
end

return M;
