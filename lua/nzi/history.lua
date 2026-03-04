local M = {};

-- Array of turns: { id = number, type = string, user = string, assistant = string }
-- Content is stored WITH line numbers (e.g. "1: text")
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

--- Remove line numbers from text
--- @param text string
--- @return string
function M.strip_line_numbers(text)
  if not text then return ""; end
  local lines = vim.split(text, "\n");
  local output = {};
  for _, line in ipairs(lines) do
    local clean = line:gsub("^%d+: ", "", 1);
    table.insert(output, clean);
  end
  return table.concat(output, "\n");
end

--- Add a completed turn to history
--- @param type string: 'question', 'directive', or 'shell'
--- @param user_content string
--- @param assistant_content string
function M.add(type, user_content, assistant_content)
  table.insert(M.turns, {
    id = next_id,
    type = type,
    user = add_line_numbers(user_content),
    assistant = add_line_numbers(assistant_content)
  });
  next_id = next_id + 1;
end

--- Get all turns
--- @return table
function M.get_all()
  return M.turns;
end

--- Format history into a structured XML block for the model
--- @return string
function M.format()
  if #M.turns == 0 then return ""; end

  local parts = {};
  for _, turn in ipairs(M.turns) do
    local user_clean = M.strip_line_numbers(turn.user);
    local assistant_clean = M.strip_line_numbers(turn.assistant);
    
    local user_safe = xml_escape(user_clean);
    local assistant_safe = xml_escape(assistant_clean);
    
    table.insert(parts, string.format("  <nzi:turn id=\"%d\" type=\"%s\">\n    <nzi:user>%s</nzi:user>\n    <nzi:assistant>%s</nzi:assistant>\n  </nzi:turn>",
      turn.id, turn.type, user_safe, assistant_safe));
  end
  
  return "<nzi:history>\n" .. table.concat(parts, "\n") .. "\n</nzi:history>";
end

--- Remove the last turn from history
function M.pop()
  if #M.turns > 0 then
    table.remove(M.turns);
    next_id = next_id - 1;
    return true;
  end
  return false;
end

--- Clear the session history
function M.clear()
  M.turns = {};
  next_id = 1;
end

return M;
