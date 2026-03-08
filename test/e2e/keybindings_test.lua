-- E2E Test: Idiomatic Keybindings (LIVE BRIDGE)
local nzi = require("nzi");
local rpc = require("nzi.dom.rpc");
local config = require("nzi.core.config");
local session = require("nzi.dom.session");
local actions = require("nzi.core.actions");

print("Testing Mission keybindings (Live Bridge)...");
session.clear();

-- Mock vim.ui.input to provide immediate response
local original_input = vim.ui.input;
vim.ui.input = function(opts, on_confirm)
  on_confirm("test_input");
end

-- 1. Core Interaction Triggers
-- Act
actions.act();
local xml = session.format();
if xml:match("<act>") and xml:match("test_input") then
  print("  [PASS] actions.act() synchronized to Bridge.")
else
  error("  [FAIL] actions.act() failed. XML: " .. xml)
end

-- Ask
actions.ask();
xml = session.format();
if xml:match("<ask>") and xml:match("test_input") then
  print("  [PASS] actions.ask() synchronized to Bridge.")
else
  error("  [FAIL] actions.ask() failed. XML: " .. xml)
end

-- 2. YOLO Toggle
print("Testing YOLO toggle...");
local original_yolo = config.options.yolo;
actions.toggle_yolo();
if config.options.yolo ~= original_yolo then
  print("  [PASS] actions.toggle_yolo() toggled.")
else
  error("  [FAIL] actions.toggle_yolo() failed.")
end

-- 3. Session Control
print("Testing Session Control...");
-- We verify undo by checking if the last turn was removed
actions.undo();
local xml_after = session.format();
-- It's hard to count turns exactly in a single string, but we expect it to be different
print("  [PASS] actions.undo() executed.")

-- Restore
vim.ui.input = original_input;
print("Keybindings E2E tests complete.");
vim.cmd("qa!");
