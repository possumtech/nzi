local M = {};

--- Queue for maintaining agent actions and passive confirmations
M.action_queue = {};
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

--- Add a passive confirmation/status to the buffer (e.g. Success Acks)
--- These do not trigger turns immediately but are piggybacked later.
--- @param msg string: The XML-namespaced message (e.g. <agent:ack>...</agent:ack>)
function M.add_passive(msg)
  table.insert(M.passive_buffer, msg);
end

--- Get and clear all passive messages for piggybacking
--- @return string | nil: The combined XML block or nil if empty
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
  return M.blocked_by_interaction or #M.action_queue > 0;
end

--- Pop a single instruction for serial processing if one exists
function M.pop_instruction()
  if #M.action_queue > 0 then
    return table.remove(M.action_queue, 1);
  end
  return nil;
end

return M;
