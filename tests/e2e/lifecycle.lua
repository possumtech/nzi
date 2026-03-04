-- tests/e2e/lifecycle.lua
local current_dir = vim.fn.getcwd()
vim.opt.runtimepath:append(current_dir)

-- 1. Use the already initialized environment from tests/init.lua
local engine = require("nzi.engine")
local modal = require("nzi.modal")
local history = require("nzi.history")

-- Track errors
local last_error = nil
local original_write = modal.write
modal.write = function(text, type, append)
  if type == "error" and not text:match("^Warning") then last_error = text end
  original_write(text, type, append)
end

-- 2. Execution
engine.handle_question("Say hello", false)

-- Wait for completion or error (Fast 30s timeout)
local success = vim.wait(30000, function()
  -- Check if history has been added
  local h = require("nzi.history").get_all()
  return last_error ~= nil or #h > 0
end, 500)

-- Final safety pause for all scheduled UI/History tasks
vim.wait(1000, function() return false end)

if not success and not last_error then
  print("\n[E2E FAILED] Interaction Timed Out.")
  os.exit(1)
end

-- 3. Verify Completion
local history = require("nzi.history")
if #history.get_all() ~= 1 then
  print("\n[E2E FAILED] Expected 1 history turn, found " .. #history.get_all())
  if last_error then
    print("\n[E2E ERROR TRACE] " .. tostring(last_error))
  end
  os.exit(1)
end

print("\n[E2E] LIFECYCLE TEST PASSED.")
vim.cmd("qa!")
