local assert = require("luassert");
local engine = require("nzi.engine.engine");
local history = require("nzi.context.history");
local config = require("nzi.core.config");
local job = require("nzi.engine.job");

describe("AI Edit Loop Integration", function()
  local test_file = "test_edit.lua";
  local full_path = vim.fn.getcwd() .. "/" .. test_file;

  before_each(function()
    history.clear();
    config.options.yolo = true;
    -- Create a dummy file to edit
    vim.fn.writefile({ "local val = 1", "function get() return val end" }, full_path);
    -- Ensure the buffer is totally clean from previous runs
    local bufnr = vim.fn.bufnr(test_file)
    if bufnr ~= -1 then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end);

  after_each(function()
    os.remove(full_path);
    local bufnr = vim.fn.bufnr(test_file)
    if bufnr ~= -1 then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end);

  local function poll_until_settle(timeout_ms)
    local start = vim.loop.now();
    while (vim.loop.now() - start) < (timeout_ms or 5000) do
      if engine.is_busy == false and engine.current_job == nil then 
        if #history.get_all() > 0 then
          return true 
        end
      end
      vim.cmd("sleep 100m");
    end
    return false;
  end

  it("should parse and apply a surgical <model:edit>", function()
    local old_run = job.run;
    local turns = 0;
    
    job.run = function(messages, callback, on_stdout)
      turns = turns + 1;
      if turns == 1 then
        local msg = string.format([[
<model:edit file="%s">
<<<<<<< SEARCH
local val = 1
=======
local val = 42
>>>>>>> REPLACE
</model:edit>
]], test_file);
        if on_stdout then on_stdout(msg, "content") end
        callback(true, msg);
      else
        local msg = "Done editing.";
        if on_stdout then on_stdout(msg, "content") end
        callback(true, msg);
      end
      return { kill = function() end };
    end

    engine.handle_question("Update val to 42");
    
    assert.True(poll_until_settle(5000), "Edit loop timed out");
    
    -- Ensure buffer is saved to disk before reading
    local bufnr = vim.fn.bufnr(test_file)
    if bufnr ~= -1 and vim.api.nvim_get_option_value("modified", {buf=bufnr}) then
      vim.api.nvim_buf_call(bufnr, function() vim.cmd("silent! write") end)
    end
    
    local lines = vim.fn.readfile(full_path);
    assert.equals("local val = 42", lines[1]);
    
    job.run = old_run;
  end);

  it("should handle 'secret' full-file replacement via markdown blocks", function()
    local old_run = job.run;
    local turns = 0;
    
    job.run = function(messages, callback, on_stdout)
      turns = turns + 1;
      if turns == 1 then
        local msg = string.format([[
```lua
-- %s
local val = 100
```
]], test_file);
        if on_stdout then on_stdout(msg, "content") end
        callback(true, msg);
      else
        local msg = "Done replacing.";
        if on_stdout then on_stdout(msg, "content") end
        callback(true, msg);
      end
      return { kill = function() end };
    end

    engine.handle_question("Replace the whole file");
    
    assert.True(poll_until_settle(5000), "Replacement loop timed out");
    
    local lines = vim.fn.readfile(full_path);
    local found = false;
    for _, l in ipairs(lines) do if l:match("val = 100") then found = true end end
    assert.True(found, "Did not find expected content in: " .. table.concat(lines, "\n"));
    
    job.run = old_run;
  end);
end);
