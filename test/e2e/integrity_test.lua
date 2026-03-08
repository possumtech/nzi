-- E2E Test: Boundary & Integrity
local nzi = require("nzi");
local effector = require("nzi.service.vim.effector");
local resolver = require("nzi.dom.resolver");

print("Testing Boundary & Integrity...");

-- 1. Path Safety (resolver)
print("  Testing Path Safety (resolver)...");

local unsafe_paths = {
  "/etc/passwd",
  "../../.ssh/id_rsa",
  "~/.bashrc",
  "/tmp/some_file"
}

for _, path in ipairs(unsafe_paths) do
  local resolved, err = resolver.resolve(path);
  if resolved then
    error("    [FAIL] Unsafe path was resolved: " .. path .. " -> " .. tostring(resolved))
  else
    print("    [PASS] Correctly blocked unsafe path: " .. path .. " (" .. tostring(err) .. ")")
  end
end

-- 2. Effector Path Safety
print("  Testing Effector Path Safety...");
-- Effector should not attempt to edit/create files outside project root
-- Even if someone bypasses the resolver (unlikely, but effector is hardware gate)

local original_notify = vim.notify;
local last_error = nil;
vim.notify = function(msg, level)
  if level == vim.log.levels.ERROR then last_error = msg end
end

effector.propose_edit({ file = "/etc/passwd", blocks = {} });
if last_error and last_error:match("Could not resolve") then
  print("    [PASS] effector.propose_edit blocked absolute path.")
else
  error("    [FAIL] effector.propose_edit did not block absolute path.")
end

vim.notify = original_notify;

-- 3. XML Validation (DOM strictness)
print("  Testing XML Validation (DOM strictness)...");
local session = require("nzi.dom.session");
session.clear();

-- Attempt to hydrate with invalid XML (missing closing tag)
local ok, err = pcall(session.hydrate, [[
<session>
  <turn id="1">
    <user><instruct>broken</instruct></user>
    <assistant><content>
      <edit file="test.py">
      SEARCH
      foo
      =======
      bar
      REPLACE
    </assistant>
  </turn>
</session>
]])

if not ok and err:match("Bridge Error") then
  print("    [PASS] Invalid XML rejected by Python DOM.")
else
  error("    [FAIL] Invalid XML was not rejected or gave wrong error: " .. tostring(err))
end

-- 4. Large File Handling
print("  Testing Large File Handling...");
local large_file = "large_test.txt";
local f = io.open(large_file, "w");
for i = 1, 10000 do
  f:write("Line " .. i .. ": This is a fairly long line to increase file size substantially.\n");
end
f:close();

-- Test context sync with large file
local watcher = require("nzi.service.vim.watcher");
local bufnr = vim.fn.bufadd(large_file);
vim.fn.bufload(bufnr);
require("nzi.core.actions").mark_active();

local ok_sync, err_sync = pcall(function()
  local items = watcher.sync_list();
  session.update_context(items);
end)

if ok_sync then
  print("    [PASS] Large file (approx 1MB) synced to DOM successfully.")
else
  error("    [FAIL] Large file sync failed: " .. tostring(err_sync))
end
os.remove(large_file);

-- 5. External File Permissions
print("  Testing External File Permissions...");
local ext_file = "/tmp/nzi_external_test.txt";
local f = io.open(ext_file, "w");
f:write("secret external content");
f:close();

local ext_buf = vim.fn.bufadd(ext_file);
vim.fn.bufload(ext_buf);

-- Initially it should be 'map' (heuristic) and NOT permitted because it's external
local items = watcher.sync_list();
local found = false;
for _, item in ipairs(items) do
  if item.path == ext_file then found = true end
end
if found then
  error("    [FAIL] External file was included in sync without explicit permission.")
else
  print("    [PASS] External file correctly excluded by default.")
end

-- Now explicitly mark as Read-only
watcher.set_state(ext_buf, "read");
items = watcher.sync_list();
found = false;
for _, item in ipairs(items) do
  if item.path == ext_file then found = true end
end
if found then
  print("    [PASS] External file included after explicit \aR.")
else
  error("    [FAIL] External file still excluded after explicit \aR.")
end

os.remove(ext_file);

-- 6. User Instruction Queue (Live Bridge)
print("  Testing User Instruction Queue (Live)...");
local bridge = require("nzi.service.llm.bridge");

session.clear();

-- Manually block the bridge to force enqueuing
bridge.is_busy = true;

-- This should enqueue
bridge.run_loop("Queued turn", "ask");

if #bridge.queue == 1 then
  print("    [PASS] Turn successfully enqueued.")
else
  error("    [FAIL] Queue size mismatch: " .. #bridge.queue)
end

-- Now unblock and trigger finish
bridge.is_busy = false; 
bridge.finish();

-- Wait for the turn to actually hit the DOM
vim.wait(5000, function() 
  local xml = session.format();
  return xml:match("Queued turn") ~= nil 
end, 100);

local xml = session.format();
if xml:match("Queued turn") then
  print("    [PASS] Enqueued turn processed correctly by Bridge.")
else
  error("    [FAIL] Bridge did not receive enqueued turn. XML: " .. xml)
end

print("Boundary & Integrity E2E tests complete.");
vim.cmd("qa!");
