local M = {};

--- Queue for maintaining agent actions, passive confirmations, and pending instructions
M.action_queue = {};
M.instruction_queue = {}; -- Queue for new model tasks when engine is busy
M.passive_buffer = {};
M.blocked_by_interaction = false;

--- Add a high-priority action that must be handled by the user (e.g. Edit)
function M.enqueue_action(action)
  table.insert(M.action_queue, action);
end

--- Get all currently enqueued actions
function M.get_actions()
  return M.action_queue;
end

--- Clear the active action queue
function M.clear_actions()
  M.action_queue = {};
  M.blocked_by_interaction = false;
end

--- Queue a new model task for later processing
function M.enqueue_instruction(content, type, target_file, selection)
  table.insert(M.instruction_queue, {
    instruction = content,
    type = type or "ask",
    target_file = target_file,
    selection = selection
  });
end

--- Pop a single instruction for serial processing if one exists
function M.pop_instruction()
  if #M.instruction_queue > 0 then
    return table.remove(M.instruction_queue, 1);
  end
  return nil;
end

--- Clear the instruction queue
function M.clear_instructions()
  M.instruction_queue = {};
end

--- Add a passive confirmation/status to the buffer (e.g. Success Acks)
function M.add_passive(msg)
  table.insert(M.passive_buffer, msg);
end

--- Get and clear all passive messages for piggybacking
function M.flush_passive()
  if #M.passive_buffer == 0 then return nil; end
  local combined = table.concat(M.passive_buffer, "\n");
  M.passive_buffer = {};
  return combined;
end

--- Mark the queue as blocked until user resolves a choice or edit
function M.set_blocked(blocked)
  M.blocked_by_interaction = blocked;
end

--- Check if the engine should wait for user input
function M.is_blocked()
  local history = require("nzi.context.history");
  local protocol = require("nzi.protocol.protocol");
  
  local xml = history.format();
  if xml == "" then return false; end

  -- A session is blocked if:
  -- 1. The LAST turn is a model turn with blocking tags
  -- 2. AND there is no subsequent user/agent turn resolving it.
  
  -- Optimization: We only care about the very last model actions that haven't been "acked"
  -- XPath logic: Find turns that contain blocking elements but aren't followed by a resolving turn
  -- Actually, let's keep it simpler for now: Is there ANY unresolved <model:edit/create/delete/choice>?
  
  -- Find all blocking elements
  local blocking_query = "//model:edit | //model:create | //model:delete | //model:choice";
  local blockers = protocol.xpath(xml, blocking_query);
  if #blockers == 0 then return false; end

  -- Find all resolving elements
  local resolving_query = "//agent:ack | //agent:choice | //agent:status[@status='denied']";
  local resolvers = protocol.xpath(xml, resolving_query);

  -- If we have more blockers than resolvers, we are likely blocked.
  -- This is a heuristic that works because our turns are sequential.
  return #blockers > #resolvers;
end

return M;
