local assert = require("luassert");
local engine = require("nzi.engine.engine");
local history = require("nzi.context.history");
local config = require("nzi.core.config");

describe("AI Engine Multi-Turn Loop", function()
  before_each(function()
    history.clear();
    local queue = require("nzi.core.queue");
    queue.clear_actions();
    queue.clear_instructions();
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
        callback(true, "<model:summary>I found 'Agentic' in README.md.</model:summary>");
      end
      return { kill = function() end };
    end

    engine.run_loop("Where is 'Agentic'?");
    
    -- Wait for the loop to finish (async)
    -- 1. User -> Grep
    -- 2. Grep Result -> Answer
    vim.wait(2000, function() return #history.get_all() >= 2 end);
    
    local all_history = history.get_all();
    assert.truthy(#all_history >= 2);
    local second_assistant = history.strip_line_numbers(all_history[2].assistant);
    assert.truthy(second_assistant:find("I found 'Agentic'"));
    
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
    -- Turn 1: Initial User + Buggy Assistant
    -- Turn 2: Test Failure + Fixed Assistant
    local success = vim.wait(5000, function() return #history.get_all() >= 2 end);
    if not success then
      print("TIMEOUT! History count: " .. #history.get_all());
      for i, t in ipairs(history.get_all()) do
        print(string.format("Turn %d Assistant: %s", i, t.assistant or "nil"));
      end
    end
    
    local all_history = history.get_all();
    assert.truthy(#all_history >= 2);
    local last_assistant = history.strip_line_numbers(all_history[#all_history].assistant);
    assert.truthy(last_assistant:find("fixed the bug"));
    
    config.options.auto_test = nil;
    config.options.ralph = false;
    job.run = old_run;
  end);
end);
