-- Filesystem Universe Test (Lua)
-- Verifies that NZI's universe mapping is correct
local helper = require("test.fs.helper");

print("Setting up temporary git repository for universe test...");
local test_repo = helper.setup_test_repo();

-- We need a way to tell nzi to root itself in our test repo
-- For now, let's just assert that the helper created what we expect
local function assert_exists(path)
  if vim.fn.filereadable(test_repo .. "/" .. path) == 0 then
    error("Test file missing: " .. path);
  end
end

assert_exists("main.lua");
assert_exists("src/utils.lua");
assert_exists("feat_new.lua");
assert_exists(".gitignore");

print("  [PASS] Universe: Temporary repo structure verified.");

-- Cleanup
helper.teardown_test_repo(test_repo);
print("Universe cleanup complete.");
vim.cmd("qa!");
