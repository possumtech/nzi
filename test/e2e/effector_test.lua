-- E2E Test: Assistant Action Effector
local nzi = require("nzi");
local effector = require("nzi.service.vim.effector");
local diff = require("nzi.ui.diff");
local rpc = require("nzi.dom.rpc");
local session = require("nzi.dom.session");

print("Testing Assistant Action Effector...");

-- Setup: Start with a clean session
session.clear();

-- 1. Test <edit> Surgical (vimdiff)
print("  Testing <edit> surgical action...");
local target_file = "test_edit.py"
local f = io.open(target_file, "w")
f:write("line one\nline two\n")
f:close()

-- We must simulate the Python bridge returning an action.
-- Instead of calling effector directly (which bypasses the XML state),
-- we hydrate the DOM with a turn that has an edit action.
local xml_payload = [[
<session>
  <turn id="0">
    <system>You are an assistant.</system>
    <user><instruct>edit</instruct></user>
    <assistant><content><edit file="test_edit.py">
SEARCH
line one
=======
line ALPHA
REPLACE
</edit><summary>done</summary></content></assistant>
  </turn>
</session>
]]

session.hydrate(xml_payload);

-- Now we trigger the effector for the turn we just hydrated
-- This is what bridge.py does at the end of a loop
effector.propose_edit({
  file = target_file,
  blocks = {
    { search = "line one", replace = "line ALPHA", healed = false }
  }
})

-- Verify a diff was opened
-- The cache should now be populated from hydrate
if diff.has_pending_diff(vim.api.nvim_get_current_buf()) then
  print("    [PASS] Surgical edit triggered a pending diff.")
else
  error("    [FAIL] No pending diff found after <edit> action.")
end

-- Cleanup
os.remove(target_file)

-- 4. Test <edit> Healed
print("  Testing <edit> heuristic healing...");
-- Simulate malformed markers
effector.propose_edit({
  file = "test_edit.py",
  blocks = {
    { search = "line two", replace = "line BETA", healed = true }
  }
})
-- Healed edits trigger a notify scold (which we can't easily assert in headless but we verify no crash)
print("    [PASS] Healed edit dispatched.")

-- 5. Test <env> / <shell>
print("  Testing <shell> execution...");
local last_cmd = nil;
local original_shell = require("nzi.tools.shell").run_shell;
require("nzi.tools.shell").run_shell = function(cmd) last_cmd = cmd end

effector.run_shell("ls -la");
if last_cmd == "ls -la" then
  print("    [PASS] <shell> command correctly dispatched to shell tool.")
else
  error("    [FAIL] <shell> command mismatch: " .. tostring(last_cmd))
end
require("nzi.tools.shell").run_shell = original_shell;

-- 6. Test <delete>
print("  Testing <delete> action...");
local del_file = "to_delete.txt"
local f = io.open(del_file, "w")
f:write("bye")
f:close()

effector.propose_delete({ file = del_file })
-- In our effector, propose_delete calls diff.propose_deletion
-- which currently just notifies the user.
print("    [PASS] <delete> action dispatched.")
os.remove(del_file)

print("Effector E2E tests complete.");
vim.cmd("qa!");
