local config = require("nzi.core.config");

local M = {};

-- 1. Instruction Queue (User -> Model)
-- Staging area for instructions while the model is busy or diffs are pending
M.instruction_queue = {};

-- 2. Action Queue (Model -> User)
-- Parsed model actions (edits, shell, etc.) awaiting user resolution
M.action_queue = {};

--- Add a user instruction to the queue
function M.enqueue_instruction(instruction, type, target_file, selection)
  table.insert(M.instruction_queue, {
    instruction = instruction,
    type = type,
    target_file = target_file,
    selection = selection,
    timestamp = os.time()
  });
  config.log("Enqueued user instruction: " .. instruction, "QUEUE");
end

--- Get and remove the next instruction from the queue
function M.pop_instruction()
  if #M.instruction_queue == 0 then return nil end
  return table.remove(M.instruction_queue, 1);
end

--- Add a model action to the queue
function M.enqueue_action(action)
  action.status = "pending";
  table.insert(M.action_queue, action);
  config.log(string.format("Enqueued model action: %s", action.name), "QUEUE");
end

--- Clear the action queue
function M.clear_actions()
  M.action_queue = {};
end

-- 3. Acknowledgment Queue (System -> User/Model)
-- Environment changes (accepted diffs, etc.) to be reported in the NEXT turn
M.ack_queue = {};

--- Enqueue an environment update for the next turn
function M.enqueue_ack(msg)
  table.insert(M.ack_queue, msg);
  config.log("Enqueued environment ack: " .. msg, "QUEUE");
end

--- Drain and format all pending acks
function M.pop_acks()
  if #M.ack_queue == 0 then return "" end
  local res = "<agent:status>\n" .. table.concat(M.ack_queue, "\n") .. "\n</agent:status>\n\n"
  M.ack_queue = {};
  return res;
end

--- Check if we are blocked by outstanding model actions (diffs, choices, etc.)
function M.is_blocked()
  local diff = require("nzi.ui.diff");
  if diff.get_count() > 0 then return true end
  
  for _, a in ipairs(M.action_queue) do
    -- Actions like choice, create, delete, shell require user resolution or acknowledgment
    if a.status == "pending" and (a.name == "choice" or a.name == "create" or a.name == "delete" or a.name == "shell") then
      return true
    end
  end
  return false;
end

--- Check if there is work to do in the instruction queue
function M.has_work()
  return #M.instruction_queue > 0;
end

return M;
