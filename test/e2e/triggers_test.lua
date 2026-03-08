-- E2E Test: Interaction Triggers (LIVE BRIDGE)
local nzi = require("nzi");
local session = require("nzi.dom.session");

print("Testing Interaction Triggers (Live Bridge)...");
session.clear();

local bufnr = vim.api.nvim_create_buf(true, false);
vim.api.nvim_set_current_buf(bufnr);

-- 1. Test AI: Act interpolation (writing to buffer and saving)
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "AI: test act" });
vim.cmd("w! test_trigger.txt");

-- Wait for interpolation to trigger and sync
vim.wait(3000, function() 
  local xml = session.format();
  return xml:match("test act") ~= nil
end, 100);

local xml = session.format();
if xml:match("<act>") and xml:match("test act") then
  print("  [PASS] AI: Act interpolation synced.")
else
  error("  [FAIL] AI: Act interpolation failed. XML: " .. xml)
end

-- 2. Test AI? Ask interpolation
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "AI? test ask" });
vim.cmd("w!");

vim.wait(3000, function() 
  local xml = session.format();
  return xml:match("test ask") ~= nil
end, 100);

xml = session.format();
if xml:match("<ask>") and xml:match("test ask") then
  print("  [PASS] AI? Ask interpolation synced.")
else
  error("  [FAIL] AI? Ask interpolation failed. XML: " .. xml)
end

os.remove("test_trigger.txt");
print("Interaction Triggers E2E complete.");
vim.cmd("qa!");
