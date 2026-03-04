-- tests/e2e/lifecycle.lua
local current_dir = vim.fn.getcwd()
vim.opt.runtimepath:append(current_dir)

-- 1. Setup
require("nzi").setup({
  active_model = "coder",
  models = {
    coder = {
      model = "qwen/qwen-2.5-coder-32b-instruct",
      api_base = "https://openrouter.ai/api/v1",
      api_key = os.getenv("OPENROUTER_API_KEY"),
      role_preference = "developer",
    }
  }
})

local engine = require("nzi.engine")
local modal = require("nzi.modal")
local history = require("nzi.history")

-- Track errors
local last_error = nil
local original_write = modal.write
modal.write = function(text, type, append)
  if type == "error" then last_error = text end
  original_write(text, type, append)
end

-- 2. Execution
engine.handle_question("What is the origin of \"Where is the beef?\"", false)

-- Wait for completion or error (Fast 30s timeout)
local success = vim.wait(30000, function()
  return last_error ~= nil or (modal.timer == nil and #history.get_all() == 1)
end, 200)

-- Extra pause to ensure schedule tasks (like close_tag) run
vim.wait(500, function() return false end)

if not success and not last_error then
  print("\n[E2E FAILED] Interaction Timed Out.")
  os.exit(1)
end

-- 3. Verify Completion
local history = require("nzi.history")
if #history.get_all() ~= 1 then
  print("\n[E2E FAILED] Expected 1 history turn, found " .. #history.get_all())
  os.exit(1)
end

print("\n[E2E] LIFECYCLE TEST PASSED.")
nvim.cmd("qa!")
