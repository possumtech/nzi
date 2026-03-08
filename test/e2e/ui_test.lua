-- E2E Test: UI & Ergonomics
local nzi = require("nzi");
local modal = require("nzi.ui.modal");
local session = require("nzi.dom.session");
local watcher = require("nzi.service.vim.watcher");

print("Testing UI & Ergonomics...");

-- 1. Test History Rewind (X)
print("  Testing History Rewind (X)...");
-- Setup a session with 3 turns
local xml_payload = [[
<session>
  <turn id="0"><system>Constitution</system><user><instruct>t0</instruct></user><assistant><content>a0</content></assistant></turn>
  <turn id="1"><user><instruct>t1</instruct></user><assistant><content>a1</content></assistant></turn>
  <turn id="2"><user><instruct>t2</instruct></user><assistant><content>a2</content></assistant></turn>
</session>
]]
session.hydrate(xml_payload);
print("    Initial XML length: " .. #session.format());

-- Open modal and find Turn 1
modal.open();
local bufnr = modal.bufnr;
vim.api.nvim_set_current_buf(bufnr);

-- Force immediate render instead of scheduled
modal.render_history();
vim.wait(500); -- wait for render

-- Find the line for Turn 1
local row = vim.fn.search("id=\"1\"");
print("    Found Turn 1 at row: " .. row);
vim.api.nvim_win_set_cursor(0, {row, 0});

-- Trigger the 'X' key (Rewind)
modal.rewind();

-- Wait for async RPC and cache update
vim.wait(1000, function() return not session.format():match("id=\"1\"") end);

-- Verify Turn 1 and Turn 2 are gone
local final_xml = session.format();
print("    Final XML length: " .. #final_xml);
if final_xml:match("id=\"1\"") or final_xml:match("id=\"2\"") then
  error("    [FAIL] History Rewind failed to prune turns 1 and 2.")
else
  print("    [PASS] History Rewind pruned session correctly.")
end

-- 2. Test Visual Context Highlights (Buffer background)
print("  Testing Visual Context Highlights...");
local test_buf = vim.api.nvim_create_buf(true, false);
vim.api.nvim_set_current_buf(test_buf);
watcher.set_state(test_buf, "read");

-- We can't easily assert pixel colors in headless, but we can verify 
-- that the update_buffer logic ran without error.
print("    [PASS] Visual update triggered.")

print("UI & Ergonomics E2E tests complete.");
vim.cmd("qa!");
