local M = {};

--- Resilient state-machine parser for <model:*> tags and markdown code blocks
--- This version handles tags that are never explicitly closed.
function M.create_parser()
  return {
    buffer = "",
    actions = {},
    
    --- Feed a new chunk of text into the parser
    --- @param chunk string
    feed = function(self, chunk)
      self.buffer = self.buffer .. chunk
      
      -- 1. Check for markdown-fenced code blocks (sh and bash) -> Shell
      while true do
        local s_start, e_end, lang, content = self.buffer:find("```([sb][ha][sh]?)%s*\n(.-)```")
        if s_start then
          table.insert(self.actions, { 
            name = "shell", 
            attr = nil, 
            content = content:gsub("^%s*", ""):gsub("%s*$", "") 
          })
          self.buffer = self.buffer:sub(e_end + 1)
        else
          break
        end
      end

      -- 2. "Secret" Full-File Replacement fallback
      while true do
        local s_start, e_end, lang, content = self.buffer:find("```(%a+)%s*\n(.-)```")
        if s_start then
          local first_lines = content:match("^[^\n]*\n?[^\n]*")
          local path = first_lines:match("[%-%/][%-%/]%s*([%a%d%_%-%./]+)")
          if path and path:match("%.") then 
            table.insert(self.actions, {
              name = "replace_all",
              attr = "file=\"" .. path .. "\"",
              content = content
            })
          end
          self.buffer = self.buffer:sub(e_end + 1)
        else
          break
        end
      end

      local function is_inside_backticks(pos)
        local prefix = self.buffer:sub(1, pos - 1)
        local _, count = prefix:gsub("`", "")
        return (count % 2) ~= 0
      end

      -- 3. Check for block tags: <model:tag ...>content</model:tag>
      while true do
        local s_start, s_end, tag_name, attr, content = self.buffer:find("<model:([%a_]+)([^>]*)>(.-)</model:%1>")
        
        if s_start then
          if not is_inside_backticks(s_start) then
            table.insert(self.actions, { 
              name = tag_name, 
              attr = attr, 
              content = content 
            })
            self.buffer = self.buffer:sub(s_end + 1)
          else
            local next_search = self.buffer:find("<model:", s_start + 1)
            if not next_search then break end
            break 
          end
        else
          break
        end
      end
      
      -- 4. Check for self-closing tags: <model:tag file="..." />
      while true do
        local s_start, e_end, tag_name, attr = self.buffer:find("<model:([%a_]+)([^>]-)%s*/>")
        
        if s_start then
          if not is_inside_backticks(s_start) then
            table.insert(self.actions, { 
              name = tag_name, 
              attr = attr, 
              content = nil 
            })
            self.buffer = self.buffer:sub(e_end + 1)
          else
            break
          end
        else
          break
        end
      end

      -- 5. FINALIZATION: If chunk is empty, handle unclosed tags
      if chunk == "" then
        -- Look for an open <model:tag> that never closed
        local s_start, s_end, tag_name, attr = self.buffer:find("<model:([%a_]+)([^>]*)>")
        if s_start and not is_inside_backticks(s_start) then
          local content = self.buffer:sub(s_end + 1)
          table.insert(self.actions, {
            name = tag_name,
            attr = attr,
            content = content
          })
          self.buffer = ""
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

function M.get_attr(attr_str, key)
  if not attr_str then return nil end
  -- Pattern matches key="value" or key='value' with optional whitespace
  local pattern1 = key .. "%s*=%s*\"([^\"]+)\""
  local pattern2 = key .. "%s*=%s*'([^']+)'"
  return attr_str:match(pattern1) or attr_str:match(pattern2)
end

--- Execute an XPath query on an XML string
--- @param xml_str string: The raw XML (will be wrapped in <session>)
--- @param xpath string: The XPath expression
--- @return table: List of results (strings)
function M.xpath(xml_str, xpath)
  local config = require("nzi.core.config");
  local python_cmd = config.options.python_cmd[1];
  
  local wrapped = xml_str;

  local script = [[
import sys
from lxml import etree
try:
    xml_str = sys.stdin.read()
    root = etree.fromstring(xml_str)
    ns = {"nzi": "nzi", "agent": "nzi", "model": "nzi"}
    results = root.xpath("]] .. xpath .. [[", namespaces=ns)
    print("---XPATH_RESULTS_START---")
    for r in results:
        if isinstance(r, etree._Element):
            print(etree.tostring(r, encoding='unicode').strip())
        else:
            print(str(r).strip())
except Exception as e:
    print("---XPATH_ERROR---")
    print(str(e))
    sys.exit(1)
]];

  local res = vim.fn.system({ python_cmd, "-c", script }, wrapped);
  local lines = vim.split(res, "\n", { trimempty = true });
  local final_results = {};
  local in_results = false;
  local err_msg = nil;
  local in_error = false;
  
  for _, line in ipairs(lines) do
    if line == "---XPATH_RESULTS_START---" then
      in_results = true;
    elseif line == "---XPATH_ERROR---" then
      in_error = true;
    elseif in_error then
      err_msg = (err_msg or "") .. line .. "\n";
    elseif in_results then
      table.insert(final_results, line);
    end
  end

  if in_error then
    config.log("XPath Error: " .. (err_msg or "unknown"), "PROTOCOL");
    return {};
  end
  
  return final_results;
end

return M;
