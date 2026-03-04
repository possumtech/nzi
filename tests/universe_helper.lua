-- tests/universe_helper.lua
local M = {}

--- Create a temporary git repository for testing universe mapping
--- @return string: The path to the temporary repository
function M.setup_test_repo()
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  local old_cwd = vim.fn.getcwd()
  vim.cmd("cd " .. root)

  local function run(cmd)
    local out = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 then
      print("ERROR running: " .. cmd)
      print(out)
    end
    return out
  end

  -- Initialize git
  run("git init")
  run("git config user.email 'test@nzi.ai'")
  run("git config user.name 'Nzi Tester'")

  -- 1. Tracked file
  vim.fn.writefile({ "function main_task() print('hello') end" }, "main.lua")
  run("git add main.lua")
  run("git commit --no-verify -m 'feat: initial commit'")

  -- 2. Tracked file in subdir
  vim.fn.mkdir("src", "p")
  vim.fn.writefile({ "function util() end" }, "src/utils.lua")
  run("git add src/utils.lua")
  run("git commit --no-verify -m 'feat: add utils'")

  -- 3. Untracked file (should be mapped by default)
  vim.fn.writefile({ "-- new feature" }, "feat_new.lua")

  -- 4. Ignored file (should be invisible)
  vim.fn.writefile({ "secret_key=1234" }, ".env")
  vim.fn.writefile({ ".env" }, ".gitignore")
  run("git add .gitignore")
  run("git commit --no-verify -m 'feat: add gitignore'")

  -- 5. Staged but not committed
  vim.fn.writefile({ "-- staged content" }, "staged.lua")
  run("git add staged.lua")

  vim.cmd("cd " .. old_cwd)
  return root
end

--- Cleanup the temporary test repository
--- @param path string
function M.teardown_test_repo(path)
  vim.fn.delete(path, "rf")
end

return M
