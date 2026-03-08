-- E2E Test: Idiomatic Keybindings
local nzi = require("nzi");
local rpc = require("nzi.dom.rpc");
local config = require("nzi.core.config");

local last_request = nil;
rpc.request_sync = function(method, params)
  last_request = { method = method, params = params };
end

-- Mock Effector run to avoid side effects
local last_shell_cmd = nil;
require("nzi.service.vim.effector").run = function(cmd)
  last_shell_cmd = cmd;
end

local last_internal_cmd = nil;
require("nzi.core.commands").run = function(cmd)
  last_internal_cmd = cmd;
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

last_request = nil;
last_shell_cmd = nil;
actions.run();
if last_shell_cmd == "test_input" then
  print("  [PASS] actions.run() triggered correctly.")
else
  error("  [FAIL] actions.run() failed: " .. tostring(last_shell_cmd))
end

last_request = nil;
last_internal_cmd = nil;
actions.internal();
if last_internal_cmd == "test_input" then
  print("  [PASS] actions.internal() triggered correctly.")
else
  error("  [FAIL] actions.internal() failed: " .. tostring(last_internal_cmd))
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

called_action = nil;
actions.stop();
if called_action == "stop" then
  print("  [PASS] actions.stop() linked to commands.actions.stop")
else
  error("  [FAIL] actions.stop() linkage failed.")
end

called_action = nil;
actions.reset();
if called_action == "clear" then
  print("  [PASS] actions.reset() linked to commands.actions.stop/clear")
else
  error("  [FAIL] actions.reset() linkage failed: " .. tostring(called_action))
end

called_action = nil;
actions.load_session();
if called_action == "load" then
  print("  [PASS] actions.load_session() linked to commands.actions.load")
else
  error("  [FAIL] actions.load_session() linkage failed.")
end

-- 5. Command Aliases
print("Testing command aliases...");
local last_cmd = nil;
vim.cmd = function(cmd) last_cmd = cmd end

actions.accept_diff();
if last_cmd == "AI/accept" then
  print("  [PASS] actions.accept_diff() triggers AI/accept")
else
  error("  [FAIL] actions.accept_diff() failed: " .. tostring(last_cmd))
end

actions.reject_diff();
if last_cmd == "AI/reject" then
  print("  [PASS] actions.reject_diff() triggers AI/reject")
else
  error("  [FAIL] actions.reject_diff() failed: " .. tostring(last_cmd))
end

actions.next_diff();
if last_cmd == "AI/next" then
  print("  [PASS] actions.next_diff() triggers AI/next")
else
  error("  [FAIL] actions.next_diff() failed: " .. tostring(last_cmd))
end

actions.prev_diff();
if last_cmd == "AI/prev" then
  print("  [PASS] actions.prev_diff() triggers AI/prev")
else
  error("  [FAIL] actions.prev_diff() failed: " .. tostring(last_cmd))
end

called_action = nil;
actions.run_tests();
if called_action == "test" then
  print("  [PASS] actions.run_tests() linked to commands.actions.test")
else
  error("  [FAIL] actions.run_tests() linkage failed.")
end

actions.run_ralph();
if last_cmd:match("^AI/ralph") then
  print("  [PASS] actions.run_ralph() triggers AI/ralph")
else
  error("  [FAIL] actions.run_ralph() failed: " .. tostring(last_cmd))
end

-- Restore
vim.ui.input = original_input;
print("Keybindings E2E tests complete.");
vim.cmd("qa!");
