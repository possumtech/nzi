-- LEGACY BRIDGE: Live Proxy to new services
local M = {};

M.is_busy = false;

function M.run_loop(...)
  return require("nzi.service.llm.bridge").start_loop(...);
end

function M.get_visual_selection(...)
  return require("nzi.service.llm.bridge").get_visual_selection(...);
end

function M.execute_range(...)
  return require("nzi.service.llm.bridge").execute_range(...);
end

function M.execute_current_line(...)
  return require("nzi.service.llm.bridge").execute_current_line(...);
end

return M;
