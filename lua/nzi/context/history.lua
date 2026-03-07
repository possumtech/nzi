-- LEGACY BRIDGE: Redirects to new dom.session
local session = require("nzi.dom.session");
local M = {};

M.add = function(type, user, assistant, metadata)
  return session.add_turn(type, user, assistant, metadata);
end

M.get_all = session.get_all;
M.get_next_id = session.get_next_id;
M.format = session.format;
M.clear = session.clear;
M.delete_after = session.delete_after;
M.xml_escape = session.xml_escape;
M.strip_line_numbers = session.strip_line_numbers;

M.get_as_messages = function()
  local messages = {};
  for _, turn in ipairs(session.get_all()) do
    local meta = string.format(" id=\"%d\" model=\"%s\" duration=\"%.2f\" acts=\"%d\"", 
      turn.id, turn.metadata.model or "unknown", turn.metadata.duration or 0, turn.metadata.changes or 0);

    if turn.user and turn.user ~= "" then
      table.insert(messages, { 
        role = "user", 
        content = string.format("<agent:turn%s>\n<agent:user>\n%s\n</agent:user>\n</agent:turn>", meta, turn.user)
      });
    end
    if turn.assistant and turn.assistant ~= "" then
      table.insert(messages, { role = "assistant", content = turn.assistant });
    end
  end
  return messages;
end

return M;
