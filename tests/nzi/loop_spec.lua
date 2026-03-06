local assert = require("luassert");
local engine = require("nzi.engine.engine");
local history = require("nzi.context.history");
local config = require("nzi.core.config");

describe("AI Engine Multi-Turn Loop", function()
  before_each(function()
    history.clear();
    config.options.yolo = true; -- Skip confirm for tests
  end);

  it("should handle a multi-turn grep discovery loop", function()
    -- This test requires mocking require("nzi.engine.job").run
    local job = require("nzi.engine.job");
    local old_run = job.run;
    
    local turns = 0;
    job.run = function(messages, callback, on_stdout)
      turns = turns + 1;
      if turns == 1 then
        -- First turn: Model wants to grep
        on_stdout("<model:grep>Agentic</model:grep>", "content");
        callback(true, "<model:grep>Agentic</model:grep>");
      else
        -- Second turn: Model has the grep results and answers
        callback(true, "I found 'Agentic' in README.md.");
      end
      return { kill = function() end };
    end

    engine.run_loop("Where is 'Agentic'?");
    
    -- Wait for the loop to finish (async)
    -- 1. User -> Grep
    -- 2. Grep Result -> Answer
    vim.wait(2000, function() return #history.get_all() == 2 end);
    
    local all_history = history.get_all();
    assert.equals(2, #all_history);
    assert.match("I found 'Agentic'", all_history[#all_history].assistant);
    
    job.run = old_run;
  end);

  it("should handle ralph auto-retry on test failure", function()
    local job = require("nzi.engine.job");
    local old_run = job.run;
    
    config.options.auto_test = "false"; -- Always fails
    config.options.ralph = true;
    
    local turns = 0;
    job.run = function(messages, callback, on_stdout)
      turns = turns + 1;
      if turns == 1 then
        -- First turn: Model gives a wrong answer that fails tests
        callback(true, "I am a buggy response.");
      else
        -- Second turn: Model sees <agent:test> output and fixes it
        callback(true, "I have fixed the bug.");
      end
      return { kill = function() end };
    end

    engine.run_loop("Fix the bug.");
    
    -- Wait for two assistant turns
    vim.wait(1000, function() return #history.get_all() >= 3 end);
    
    local all_history = history.get_all();
    -- History should have:
    -- 1. instruct/ask turn (initial)
    -- 2. assistant turn (buggy)
    -- 3. user turn (test failure)
    -- 4. assistant turn (fixed)
    assert.True(#all_history >= 3);
    assert.match("fixed the bug", all_history[#all_history].assistant);
    
    config.options.auto_test = nil;
    config.options.ralph = false;
    job.run = old_run;
  end);
end);
