local assert = require("luassert");
local engine = require("nzi.engine.engine");
local buffers = require("nzi.ui.buffers");
local history = require("nzi.context.history");
local job = require("nzi.engine.job");

describe("AI Interpolation and Visual Mode", function()
  local test_buf;
  local old_run = job.run;

  before_each(function()
    history.clear();
    test_buf = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_buf_set_name(test_buf, "test_file.lua");
    vim.api.nvim_set_current_buf(test_buf);
    
    -- Mock job.run to be synchronous for tests
    job.run = function(messages, callback, on_stdout)
      callback(true, "Mock Response");
      return { kill = function() end };
    end
  end);

  after_each(function()
    job.run = old_run;
    if vim.api.nvim_buf_is_valid(test_buf) then
      vim.api.nvim_buf_delete(test_buf, { force = true });
    end
  end);

  it("should handle Interpolation on Save (BufWritePre)", function()
    local lines = {
      "local x = 1",
      ":AI? How does this work?",
      "local y = 2"
    };
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, lines);
    
    -- Simulate the save trigger
    buffers.interpolate(test_buf);
    
    -- 1. Directive line should be gone
    local new_lines = vim.api.nvim_buf_get_lines(test_buf, 0, -1, false);
    assert.equals(2, #new_lines);
    assert.equals("local x = 1", new_lines[1]);
    
    -- 2. History should contain the content
    vim.wait(1000, function() return #history.get_all() > 0 end);
    local all = history.get_all();
    assert.True(#all > 0);
    local user_msg = history.strip_line_numbers(all[1].user);
    assert.match("How does this work?", user_msg);
  end);

  it("should handle visual range execution with a directive", function()
    local lines = {
      "function test()",
      ":AI: optimize this",
      "  return 1 + 1",
      "end"
    };
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, lines);
    
    -- Execute range 1-4
    engine.execute_range(1, 4);
    
    -- 1. Buffer should have 3 lines (AI: line removed)
    local new_lines = vim.api.nvim_buf_get_lines(test_buf, 0, -1, false);
    assert.equals(3, #new_lines);
    
    -- 2. Structured tag should have precise range and content
    vim.wait(1000, function() return #history.get_all() > 0 end);
    local all = history.get_all();
    assert.True(#all > 0);
    local user_msg = history.strip_line_numbers(all[1].user);
    assert.match("start=\"1:1\"", user_msg);
    assert.match("end=\"4:3\"", user_msg);
    assert.match("optimize this", user_msg);
    -- Content should be the code minus the :AI: line
    assert.match("function test%(%)", user_msg);
    assert.match("return 1 %+ 1", user_msg);
  end);

  it("should handle raw visual selection with no directive (fallback to input)", function()
    local lines = { "line 1", "line 2" };
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, lines);
    
    -- Mock vim.ui.input to simulate user typing "Explain"
    local old_input = vim.ui.input;
    vim.ui.input = function(opts, on_confirm)
      on_confirm("Explain");
    end
    
    -- Simulate visual selection 1,1 to 2,6
    vim.api.nvim_win_set_cursor(0, {1, 0});
    vim.cmd("normal! v");
    vim.api.nvim_win_set_cursor(0, {2, 5});
    vim.cmd("normal! \27"); -- ESC to exit visual mode and set '< '> marks

    engine.execute_range(1, 2);
    
    vim.wait(1000, function() return #history.get_all() > 0 end);
    local all = history.get_all();
    assert.True(#all > 0);
    local user_msg = history.strip_line_numbers(all[1].user);
    assert.match("Explain", user_msg);
    assert.match("start=\"1:1\"", user_msg);
    assert.match("line 1", user_msg);
    
    vim.ui.input = old_input;
  end);
end);
