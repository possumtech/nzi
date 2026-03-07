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
  return M.blocked_by_interaction or #M.action_queue > 0;
end

return M;
