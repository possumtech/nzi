local assert = require("luassert");
local engine = require("nzi.service.llm.bridge");
local history = require("nzi.dom.session");
local config = require("nzi.core.config");
local job = require("nzi.service.llm.job");

describe("AI New Features E2E", function()
  local test_buf;

  before_each(function()
    require("nzi").setup({});
    history.clear();
    test_buf = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_set_current_buf(test_buf);
  end);

  after_each(function()
    if vim.api.nvim_buf_is_valid(test_buf) then
      vim.api.nvim_buf_delete(test_buf, { force = true });
    end
  end);

  it("should handle new :AI: prefix for directives", function()
    local lines = {
      "local x = 1",
      ":AI: optimize this",
      "local y = 2"
    };
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, lines);
    vim.api.nvim_win_set_cursor(0, {2, 0});

    local old_run = job.run;
    local called = false;
    job.run = function(messages, callback)
      called = true;
      assert.match("optimize this", messages[#messages].content);
      callback(true, "Optimized");
      return { kill = function() end };
    end

    -- Trigger current line execution (which uses parser.parse_line)
    engine.execute_current_line();

    assert.is_true(called, "Job was never called with :AI: prefix");
    job.run = old_run;
  end);

  it("should handle <leader>ax (abort) and <leader>aX (abort+reset)", function()
    local old_run = job.run;
    local killed = false;
    job.run = function(messages, callback)
      return { kill = function() killed = true end };
    end

    -- 1. Test Abort
    engine.handle_ask("Long running task");
    vim.cmd("AI/stop"); -- Equivalent to <leader>ax
    assert.is_true(killed, "Job was not killed by AI/stop");
    assert.is_false(engine.is_busy, "Engine still busy after stop");

    -- 2. Test Reset
    history.add("ask", "test user", "test assistant");
    assert.are.equal(1, #history.get_all());
    
    -- Simulate <leader>aX (calls stop then reset)
    vim.cmd("AI/stop");
    vim.cmd("AI/reset");
    
    assert.are.equal(0, #history.get_all(), "History not cleared by reset");
    
    job.run = old_run;
  end);

  it("should handle <leader>aK (Ralph mode test)", function()
    local old_run = job.run;
    local turns = 0;
    
    -- Mock a failing test first, then success or just check if it was sent back
    job.run = function(messages, callback)
      turns = turns + 1;
      if turns == 1 then
        -- This is the turn triggered by the test failure
        assert.match("<test>", messages[#messages].content);
        assert.match("FAKE_FAILURE", messages[#messages].content);
        callback(true, "I will fix it");
      end
      return { kill = function() end };
    end

    -- Simulate <leader>aK by calling the AI/ralph command
    -- We must use a valid command that works with the "./run_tests.sh" prefix if not overridden
    config.options.test_command = "sh -c";
    vim.cmd("AI/ralph 'echo FAKE_FAILURE; exit 1'");

    -- Wait for the async chain (verify_state -> handle_ask -> job.run)
    local success = vim.wait(2000, function() return turns > 0 end);
    assert.is_true(success, "Ralph mode did not trigger a follow-up turn on failure");
    assert.are.equal(1, turns);

    job.run = old_run;
  end);
end);
