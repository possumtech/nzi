-- E2E Test: Directive Projections (LIVE BRIDGE)
local nzi = require("nzi");
local run_tool = require("nzi.tools.run");
local session = require("nzi.dom.session");
local helper = require("test.e2e.xml_helper");
local config = require("nzi.core.config");

print("Testing Unified Directive Model Projections...");

-- 1. Run Pass Projection
print("  Testing Run Pass projection...");
session.clear();
config.options.yolo = true; -- avoid confirm dialog

-- Execute a simple command
run_tool.run("echo 'hello world'", nil, nil, true);

-- Wait for it to finish and sync
vim.wait(5000, function() 
  local xml = session.format();
  return xml:match("hello world") ~= nil
end, 100);

local xml = session.format();
local results = helper.xpath(xml, "//turn/user/act/selection[@type='run' and @status='pass']");
if #results > 0 then
  print("    [PASS] Run Pass projected as <selection type='run' status='pass'>")
else
  error("    [FAIL] Run Pass projection failed.\nXML:\n" .. xml)
end

-- 2. Run Fail Projection
print("  Testing Run Fail projection...");
run_tool.run("ls /nonexistent_directory_xyz", nil, nil, true);

vim.wait(5000, function() 
  local xml = session.format();
  return xml:match("nonexistent") ~= nil
end, 100);

xml = session.format();
results = helper.xpath(xml, "//turn/user/act/selection[@type='run' and @status='fail']");
if #results > 0 then
  print("    [PASS] Run Fail projected as <selection type='run' status='fail'>")
else
  error("    [FAIL] Run Fail projection failed.\nXML:\n" .. xml)
end

-- 3. Test Projection
print("  Testing Test Pass projection...");
config.options.test_command = "echo 'tests passed'";
require("nzi.core.commands").actions.test("");

vim.wait(5000, function() 
  local xml = session.format();
  return xml:match("tests passed") ~= nil
end, 100);

xml = session.format();
results = helper.xpath(xml, "//turn/user/act/selection[@type='test' and @status='pass']");
if #results > 0 then
  print("    [PASS] Test Pass projected as <selection type='test' status='pass'>")
else
  error("    [FAIL] Test Pass projection failed.\nXML:\n" .. xml)
end

-- 4. Ralph Loop (Automated Retry)
print("  Testing Ralph Loop (Automated Retry)...");
session.clear();
config.options.yolo = true;
config.options.ralph_command = "false"; -- Force immediate failure

-- Ensure bridge is not busy
require("nzi.service.llm.bridge").is_busy = false;

require("nzi.core.commands").actions.ralph("");

-- We verify by checking if a NEW turn appeared after the failure
-- Turn 1: ralph command (fail)
-- Turn 2: automated diagnosis instruction
vim.wait(10000, function() 
  local xml = session.format();
  return xml:match("id=\"2\"") and xml:match("Diagnose and resolve")
end, 200);

local xml = session.format();
if xml:match("id=\"2\"") and xml:match("Diagnose and resolve") then
  print("    [PASS] Ralph failure automatically triggered a diagnosis loop.")
else
  error("    [FAIL] Ralph Loop failed to trigger a new turn.\nXML:\n" .. xml)
end

-- 5. Answer Flow (Prompt User -> Answer)
print("  Testing Answer Flow...");
session.clear();
vim.wait(2000); -- Stabilize bridge

-- Mock vim.ui.select to pick the second option ("Lua")
local original_select = vim.ui.select;
vim.ui.select = function(options, opts, on_choice)
  on_choice("Lua", 2);
end

-- Simulating assistant turn with prompt_user
session.add_turn("Initialization", "<prompt_user>Should we use Python or Lua?\n- [ ] Python\n- [ ] Lua</prompt_user>", 100);

-- Manually trigger propose_choice (which handles prompt_user logic in effector)
require("nzi.service.vim.effector").propose_choice({
  content = "Should we use Python or Lua?\n- [ ] Python\n- [ ] Lua"
});

-- Wait for answer to be projected
vim.wait(5000, function() 
  local xml = session.format();
  return xml:match("Lua") ~= nil
end, 100);

xml = session.format();
results = helper.xpath(xml, "//turn/user/act/selection[@type='answer']");
if #results > 0 and results[1]:match("Lua") then
  print("    [PASS] Prompt User response projected as <selection type='answer'>")
else
  error("    [FAIL] Answer Flow projection failed.\nXML:\n" .. xml)
end

vim.ui.select = original_select;

print("Directive Projections E2E tests complete.");
vim.cmd("qa!");
