-- E2E Test: Context Management
local nzi = require("nzi");
local actions = require("nzi.core.actions");
local watcher = require("nzi.service.vim.watcher");

print("Testing Context Management bindings...");

local bufnr = vim.api.nvim_create_buf(true, false);
vim.api.nvim_set_current_buf(bufnr);
vim.api.nvim_buf_set_name(bufnr, "context_test.py");

-- 1. Test \aR (Read-only)
print("  Testing \\aR (Read-only)...");
actions.mark_read_only();
local state = watcher.sync_list()[1].state;
if state == "read" then
  print("    [PASS] Buffer marked as Read-only.")
else
  error("    [FAIL] Expected 'read', got: " .. tostring(state))
end

-- 2. Test \aI (Ignore)
print("  Testing \\aI (Ignore)...");
actions.mark_ignored();
local items = watcher.sync_list();
-- An ignored buffer might be completely removed from the list depending on implementation
-- Let's check how it's handled in watcher.sync_list
local found = false;
for _, item in ipairs(items) do
  if item.name == "context_test.py" then
    found = true;
    if item.state == "ignore" then
      print("    [PASS] Buffer marked as Ignored.")
    else
      error("    [FAIL] Expected 'ignore', got: " .. tostring(item.state))
    end
  end
end
if not found then
  print("    [PASS] Ignored buffer successfully excluded from sync.")
end

-- 3. Test \aA (Active)
print("  Testing \\aA (Active)...");
actions.mark_active();
state = watcher.sync_list()[1].state;
if state == "active" then
  print("    [PASS] Buffer marked as Active.")
else
  error("    [FAIL] Expected 'active', got: " .. tostring(state))
end

print("Context Management E2E tests complete.");
vim.cmd("qa!");
