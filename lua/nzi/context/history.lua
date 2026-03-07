local M = {};

-- Array of turns: { id = number, type = string, user = string, assistant = string }
-- Content is stored WITH line numbers (e.g. "1: text")
M.turns = {};
local next_id = 1;

--- Escape special characters for XML safety
function M.xml_escape(text)
  if not text then return ""; end
  return text:gsub("&", "&amp;")
             :gsub("<", "&lt;")
             :gsub(">", "&gt;")
             :gsub("\"", "&quot;")
             :gsub("'", "&apos;")
end

--- Format text with line numbers (skips if structured)
local function add_line_numbers(text)
  if not text then return nil; end
  -- Skip line numbering for ANY structured XML turn
  if text:match("^<agent:") or text:match("^<model:") or text:match("^%d+: ") then return text; end
  
  local lines = vim.split(text, "\n");
  local output = {};
  for i, line in ipairs(lines) do
    table.insert(output, string.format("%d: %s", i, line));
  end
  return table.concat(output, "\n");
end

--- Remove line numbers from text (only if it was numbered by us)
--- @param text string
--- @return string
function M.strip_line_numbers(text)
  if not text or text == "" then return ""; end
  -- If it's structured XML, don't touch it
  if text:match("^<agent:") or text:match("^<model:") then return text; end
  
  local lines = vim.split(text, "\n");
  local output = {};
  for _, line in ipairs(lines) do
    local clean = line:gsub("^%d+: ", "", 1);
    table.insert(output, clean);
  end
  return table.concat(output, "\n");
end

--- Add a completed or partial turn to history
--- @param type string: 'ask', 'instruct', etc.
--- @param user_content string | nil
--- @param assistant_content string | nil
function M.add(type, user_content, assistant_content)
  local config = require("nzi.core.config");
  config.log(string.format("Type: %s\nUser: %s\nAssistant: %s", type, user_content or "", assistant_content or ""), "TURN");

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

--- Format history into a structured XML block for the modal view
--- @return string
function M.format()
  if #M.turns == 0 then return ""; end

  local parts = {};
  for _, turn in ipairs(M.turns) do
    local user_clean = M.strip_line_numbers(turn.user);
    local assistant_clean = M.strip_line_numbers(turn.assistant);
    
    -- Format history as a sequence of XML-wrapped turns
    if user_clean ~= "" then
      table.insert(parts, string.format("<agent:user>\n%s\n</agent:user>", M.xml_escape(user_clean)));
    end
    if assistant_clean ~= "" then
      -- assistant_clean is usually the <model:summary> and other actions
      table.insert(parts, assistant_clean);
    end
  end
  
  return table.concat(parts, "\n\n");
end

--- Get history as an array of OpenAI-style messages
--- @return table: Array of { role = string, content = string }
function M.get_as_messages()
  local messages = {};
  for _, turn in ipairs(M.turns) do
    local user_clean = M.strip_line_numbers(turn.user);
    local assistant_clean = M.strip_line_numbers(turn.assistant);

    -- Order MUST be User then Assistant
    if user_clean ~= "" then
      table.insert(messages, { 
        role = "user", 
        content = user_clean
      });
    end
    if assistant_clean ~= "" then
      table.insert(messages, { 
        role = "assistant", 
        content = assistant_clean 
      });
    end
  end
  return messages;
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
