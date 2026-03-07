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
--- @param metadata table | nil: { model = string, duration = number, changes = number }
function M.add(type, user_content, assistant_content, metadata)
  local config = require("nzi.core.config");
  config.log(string.format("Type: %s\nUser: %s\nAssistant: %s", type, user_content or "", assistant_content or ""), "TURN");

  table.insert(M.turns, {
    id = next_id,
    type = type,
    user = add_line_numbers(user_content),
    assistant = add_line_numbers(assistant_content),
    metadata = metadata or {}
  });
  next_id = next_id + 1;
end

--- Get all turns
--- @return table
function M.get_all()
  return M.turns;
end

--- Get the ID of the next turn to be added
--- @return number
function M.get_next_id()
  return next_id;
end

--- Format history into a structured XML block for the modal view
--- @return string
function M.format()
  if #M.turns == 0 then return ""; end

  local parts = {};
  for _, turn in ipairs(M.turns) do
    local user_clean = M.strip_line_numbers(turn.user);
    local assistant_clean = M.strip_line_numbers(turn.assistant);
    
    local meta = string.format(" id=\"%d\" model=\"%s\" duration=\"%.2f\" acts=\"%d\"", 
      turn.id, turn.metadata.model or "unknown", turn.metadata.duration or 0, turn.metadata.changes or 0);

    local turn_xml = string.format("<agent:turn%s>", meta);
    
    if user_clean ~= "" then
      turn_xml = turn_xml .. string.format("\n<agent:user>\n%s\n</agent:user>", M.xml_escape(user_clean));
    end
    
    if assistant_clean ~= "" then
      -- assistant_clean is usually a sequence of <model:*> tags
      turn_xml = turn_xml .. "\n" .. assistant_clean;
    end
    
    turn_xml = turn_xml .. "\n</agent:turn>";
    table.insert(parts, turn_xml);
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

    local meta = string.format(" id=\"%d\" model=\"%s\" duration=\"%.2f\" acts=\"%d\"", 
      turn.id, turn.metadata.model or "unknown", turn.metadata.duration or 0, turn.metadata.changes or 0);

    -- Wrap the entire turn context for the model's awareness
    if user_clean ~= "" then
      table.insert(messages, { 
        role = "user", 
        content = string.format("<agent:turn%s>\n<agent:user>\n%s\n</agent:user>\n</agent:turn>", meta, user_clean)
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

--- Remove a specific turn by ID
--- @param id number
function M.delete_at(id)
  for i, turn in ipairs(M.turns) do
    if turn.id == id then
      table.remove(M.turns, i);
      -- We don't decrement next_id here to avoid collisions if more are added
      return true;
    end
  end
  return false;
end

--- Remove a turn and everything that follows it
--- @param id number
function M.delete_after(id)
  local found_idx = -1;
  for i, turn in ipairs(M.turns) do
    if turn.id == id then
      found_idx = i;
      break;
    end
  end
  
  if found_idx ~= -1 then
    local to_remove = #M.turns - found_idx + 1;
    for _ = 1, to_remove do
      table.remove(M.turns, found_idx);
    end
    -- Reset next_id based on what's left
    if #M.turns > 0 then
      next_id = M.turns[#M.turns].id + 1;
    else
      next_id = 1;
    end
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
