local config = require("nzi.config");

local M = {};

--- Setup function for nzi plugin
--- @param opts table | nil: Configuration options
function M.setup(opts)
  config.setup(opts);
  
  -- Placeholder for registering commands and autocommands
  -- These will be implemented in subsequent phases
end

return M;
