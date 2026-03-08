-- E2E Test: Idiomatic Keybindings
local nzi = require("nzi");
local rpc = require("nzi.dom.rpc");
local config = require("nzi.core.config");

local last_request = nil;
rpc.request_sync = function(method, params)
  last_request = { method = method, params = params };
end

-- Mock vim.ui.input
local original_input = vim.ui.input;
vim.ui.input = function(opts, on_confirm)
  on_confirm("test_input");
end

local actions = require("nzi.core.actions");

-- 1. Mission Keybindings
print("Testing Mission keybindings...");
last_request = nil;
actions.instruct();
if last_request and last_request.params.mode == "instruct" then
  print("  [PASS] actions.instruct() triggered correctly.")
else
  error("  [FAIL] actions.instruct() failed.")
end

last_request = nil;
actions.ask();
if last_request and last_request.params.mode == "ask" then
  print("  [PASS] actions.ask() triggered correctly.")
else
  error("  [FAIL] actions.ask() failed.")
end

-- 3. YOLO Toggle
print("Testing YOLO toggle...");
local original_yolo = config.options.yolo;
actions.toggle_yolo();
if config.options.yolo ~= original_yolo then
  print("  [PASS] actions.toggle_yolo() toggled YOLO mode.")
else
  error("  [FAIL] actions.toggle_yolo() failed.")
end

-- Restore
vim.ui.input = original_input;
-- 4. Session Logic Mappings
print("Testing Session actions...");
local commands = require("nzi.core.commands");
local called_action = nil;

-- Wrap M.actions to track calls
for name, func in pairs(commands.actions) do
  local original = func;
  commands.actions[name] = function(...)
    called_action = name;
    -- we don't call original to avoid side effects in headless
  end
end

actions.toggle_modal();
if called_action == "toggle" then
  print("  [PASS] actions.toggle_modal() linked to commands.actions.toggle")
else
  error("  [FAIL] actions.toggle_modal() linkage failed.")
end

called_action = nil;
actions.save_session();
if called_action == "save" then
  print("  [PASS] actions.save_session() linked to commands.actions.save")
else
  error("  [FAIL] actions.save_session() linkage failed.")
end

called_action = nil;
actions.undo();
if called_action == "undo" then
  print("  [PASS] actions.undo() linked to commands.actions.undo")
else
  error("  [FAIL] actions.undo() linkage failed.")
end

print("Keybindings E2E tests complete.");
vim.cmd("qa!");
