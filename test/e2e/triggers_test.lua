-- E2E Test: Interaction Triggers (Expanded)
local nzi = require("nzi");
local bridge = require("nzi.service.llm.bridge");
local rpc = require("nzi.dom.rpc");

local last_request = nil;
rpc.request_sync = function(method, params)
  last_request = { method = method, params = params };
end

-- 1. AI? Trigger (Ask)
print("Testing 'AI?' trigger on save...");
local bufnr = vim.api.nvim_create_buf(true, false);
vim.api.nvim_set_current_buf(bufnr);
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "AI? Is this a test?", "print('yes')" });
vim.cmd("doautocmd BufWritePost");

if last_request and last_request.params.mode == "ask" then
  print("  [PASS] 'AI?' trigger detected.")
else
  error("  [FAIL] 'AI?' trigger NOT detected.")
end

-- 2. AI! Trigger (Run)
-- Note: 'run' type currently delegates to effector.run_shell in bridge.lua
-- We need to check if the effector was called.
local effector = require("nzi.service.vim.effector");
local last_shell_cmd = nil;
effector.run_shell = function(cmd) last_shell_cmd = cmd end

print("Testing 'AI!' trigger on save...");
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "AI! ls -la", "print('run')" });
vim.cmd("doautocmd BufWritePost");

if last_shell_cmd == "ls -la" then
  print("  [PASS] 'AI!' trigger detected.")
else
  error("  [FAIL] 'AI!' trigger failed. Got: " .. tostring(last_shell_cmd))
end

-- 3. Visual Mode Selection Projection
print("Testing Visual Selection projection...");
last_request = nil;
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line one", "line two", "AI: fix this" });

-- In headless, we must enter visual mode via feedkeys to set the mode() correctly
vim.api.nvim_win_set_cursor(0, {1, 0});
vim.api.nvim_feedkeys("v", "nx", false);
vim.api.nvim_win_set_cursor(0, {2, 8});
-- Use x to ensure keys are processed
vim.api.nvim_feedkeys("", "x", false);

-- Trigger AI: on the last line, including the selection range
bridge.execute_range(1, 3);

if last_request and last_request.params.user_data.selection then
  local sel = last_request.params.user_data.selection;
  if sel.text:match("line one") and sel.text:match("line two") then
    print("  [PASS] Visual selection correctly wrapped in mission.")
  else
    error("  [FAIL] Visual selection text mismatch: " .. sel.text)
  end
else
  error("  [FAIL] Visual selection NOT found in request.")
end

-- Restore mock
vim.ui.input = original_input;

print("Expanded Triggers E2E tests complete.");
vim.cmd("qa!");
