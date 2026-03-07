local job = require("nzi.service.llm.job");
local prompt = require("nzi.service.llm.prompt");
local M = {};

--- Execute a completion job based on current DOM state
--- @param on_finish function: (success, result)
--- @param on_chunk function|nil: (chunk, type)
--- @return table|nil: The job object
function M.complete(on_finish, on_chunk)
  local messages = prompt.build_messages();
  return job.run(messages, on_finish, on_chunk);
end

return M;
