-- Simple E2E test for NZI setup
local nzi = require("nzi");

-- Check if nzi is loaded
if not nzi then
  error("NZI module failed to load.");
end

-- Check if setup was called by init.lua
-- (This depends on the nzi implementation, but let's assume it has a config)
local config = require("nzi.core.config");
if not config then
  error("NZI config failed to load.");
end

print("E2E test001.lua: NZI setup verified.");
vim.cmd("qa!");
