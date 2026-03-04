local M = {};

-- Array of turns: { id = number, type = string, user = string, assistant = string }
M.turns = {};
local next_id = 1;

--- Escape special characters for XML safety
local function xml_escape(text)
  if not text then return ""; end
  return text:gsub("&", "&amp;")
             :gsub("<", "&lt;")
             :gsub(">", "&gt;")
             :gsub("\"", "&quot;")
             :gsub("'", "&apos;")
end

--- Format text with line numbers
local function add_line_numbers(text)
  local lines = vim.split(text, "\n");
  local output = {};
  for i, line in ipairs(lines) do
    table.insert(output, string.format("%d: %s", i, line));
  end
  return table.concat(output, "\n");
end

--- Add a completed turn to history
--- @param type string: 'question' or 'directive'
--- @param user_content string
--- @param assistant_content string
function M.add(type, user_content, assistant_content)
  table.insert(M.turns, {
    id = next_id,
    type = type,
    user = user_content,
    assistant = assistant_content
  });
  next_id = next_id + 1;
end

--- Get all turns
--- @return table
function M.get_all()
  return M.turns;
end

--- Format history into a structured, line-numbered XML block
--- @return string
function M.format()
  if #M.turns == 0 then return ""; end

  local parts = { "<history>" };
  for _, turn in ipairs(M.turns) do
    -- We escape and number both user and assistant content for absolute safety
    local user_safe = add_line_numbers(xml_escape(turn.user));
    local assistant_safe = add_line_numbers(xml_escape(turn.assistant));
    
    table.insert(parts, string.format("  <turn id=\"%d\" type=\"%s\">\n    <user>\n%s\n    </user>\n    <assistant>\n%s\n    </assistant>\n  </turn>",
      turn.id, turn.type, user_safe, assistant_safe));
  end
  table.insert(parts, "</history>");
  
  return table.concat(parts, "\n");
end

--- Clear the session history
function M.clear()
  M.turns = {};
  next_id = 1;
end

return M;
