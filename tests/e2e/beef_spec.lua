-- tests/e2e/beef_spec.lua
local modal = require("nzi.ui.modal")
local history = require("nzi.context.history")

-- Track errors via the actual UI path
local last_error = nil
local original_write = modal.write
modal.write = function(text, type, append)
  if type == "error" and not text:match("^Warning") then last_error = text end
  original_write(text, type, append)
end

print("\n[E2E] STARTING TRUE COMMAND-LINE BEEF TEST...")

history.clear()
modal.clear()

-- Create real context: A heavy buffer to replicate the failure condition
local bufnr = vim.api.nvim_create_buf(true, false)
local mandates = vim.fn.readfile(vim.fn.getcwd() .. "/AGENTS.md")
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, mandates)
vim.api.nvim_buf_set_name(bufnr, vim.fn.getcwd() .. "/CONTEXT_AGENTS.md")
vim.api.nvim_set_current_buf(bufnr)

-- Provide a second test file just like the live environment often has
local bufnr2 = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(bufnr2, 0, -1, false, { "TEST_KEY_A = 1234" })
vim.api.nvim_buf_set_name(bufnr2, vim.fn.getcwd() .. "/vault_a.txt")
vim.api.nvim_set_option_value("buflisted", true, { buf = bufnr2 })

-- EXECUTE THE ACTUAL COMMAND
vim.cmd(":AI ? Where's the beef")

-- Wait for completion or error
local success = vim.wait(30000, function()
  return last_error ~= nil or #history.get_all() == 1
end, 500)

-- Safety pause
vim.wait(1000, function() return false end)

if last_error then
  print("\n[E2E FAILED] API Error during Command Test: " .. last_error)
  os.exit(1)
end

if not success then
  print("\n[E2E FAILED] Interaction Timed Out (Command failed to complete).")
  os.exit(1)
end

print("\n[E2E] TRUE COMMAND-LINE BEEF TEST PASSED.")
vim.api.nvim_buf_delete(bufnr, { force = true })
vim.cmd("qa!")
