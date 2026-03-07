local assert = require("luassert");
local engine = require("nzi.service.llm.bridge");
local history = require("nzi.dom.session");
local config = require("nzi.core.config");
local job = require("nzi.service.llm.job");
local queue = require("nzi.core.queue");

describe("AI Edit Loop Integration", function()
  local test_file = "test_edit.lua";
  local full_path = vim.fn.getcwd() .. "/" .. test_file;

  before_each(function()
    history.clear();
    queue.clear_actions();
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

  local function wait_for_history(count, timeout_ms)
    local start = vim.loop.now();
    while (vim.loop.now() - start) < (timeout_ms or 5000) do
      if #history.get_all() >= count and engine.is_busy == false then 
        return true 
      end
      vim.wait(50);
    end
    return false;
  end

  it("should parse and apply a surgical <model:edit> (Passive Turn)", function()
    local old_run = job.run;
    
    job.run = function(messages, callback, on_stdout)
      local msg = string.format([[
<model:edit file="%s">
<<<<<<< SEARCH
local val = 1
=======
local val = 42
>>>>>>> REPLACE
</model:edit>
<model:summary>Updated value.</model:summary>
]], test_file);
      if on_stdout then on_stdout(msg, "content") end
      callback(true, msg);
      return { kill = function() end };
    end

    engine.run_loop("Update val to 42", "instruct", true, test_file);
    
    assert.True(wait_for_history(1, 5000), "Edit loop failed to complete turn");
    
    -- Ensure buffer is loaded and updated
    local bufnr = vim.fn.bufadd(test_file);
    vim.fn.bufload(bufnr);
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
    assert.equals("local val = 42", lines[1]);
    
    job.run = old_run;
  end);

  it("should handle 'secret' full-file replacement via markdown blocks", function()
    local old_run = job.run;
    
    job.run = function(messages, callback, on_stdout)
      local msg = string.format([[
```lua
-- %s
local val = 100
```
<model:summary>Replaced file.</model:summary>
]], test_file);
      if on_stdout then on_stdout(msg, "content") end
      callback(true, msg);
      return { kill = function() end };
    end

    engine.run_loop("Replace the whole file", "instruct", true, test_file);

    assert.True(wait_for_history(1, 5000), "Edit loop failed to complete turn");
    
    local bufnr = vim.fn.bufadd(test_file);
    vim.fn.bufload(bufnr);
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
    local found = false;
    for _, l in ipairs(lines) do if l:match("val = 100") then found = true end end
    assert.True(found, "Did not find expected content in replacement.");
    
    job.run = old_run;
  end);
end);
