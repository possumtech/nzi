-- LEGACY BRIDGE: Redirects to new dom.query
local query = require("nzi.dom.query");
local M = {};

M.instruction_queue = {}; 
M.passive_buffer = {};

function M.is_blocked()
  return query.is_blocked();
end

function M.add_passive(xml_tag)
  table.insert(M.passive_buffer, xml_tag);
end

function M.flush_passive()
  if #M.passive_buffer == 0 then return nil; end
  local res = table.concat(M.passive_buffer, "\n");
  M.passive_buffer = {};
  return res;
end

function M.enqueue_instruction(content, mode, target_file, selection)
  table.insert(M.instruction_queue, {
    instruction = content,
    mode = mode,
    target_file = target_file,
    selection = selection
  });
end

function M.pop_instruction()
  if #M.instruction_queue == 0 then return nil; end
  return table.remove(M.instruction_queue, 1);
end

function M.clear_actions() end
function M.clear_instructions() M.instruction_queue = {} end
function M.set_blocked() end
function M.enqueue_action() end

return M;
