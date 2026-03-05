local assert = require("luassert");
local engine = require("nzi.engine");
local history = require("nzi.history");
local config = require("nzi.config");

describe("AI Engine Multi-Turn Loop", function()
  before_each(function()
    history.clear();
    config.options.yolo = true; -- Skip confirm for tests
  end);

  it("should handle a multi-turn grep discovery loop", function()
    -- This test requires mocking require("nzi.job").run
    local job = require("nzi.job");
    local old_run = job.run;
    
    local turns = 0;
    job.run = function(messages, callback, on_stdout)
      turns = turns + 1;
      if turns == 1 then
        -- First turn: Model wants to grep
        vim.schedule(function()
          on_stdout("<model:grep>Agentic</model:grep>", "content");
          callback(true, "<model:grep>Agentic</model:grep>");
        end);
      else
        -- Second turn: Model has the grep results and answers
        vim.schedule(function()
          callback(true, "I found 'Agentic' in README.md.");
        end);
      end
      return { kill = function() end };
    end

    engine.handle_question("Where is 'Agentic'?");
    
    -- Wait for the loop to finish (async)
    vim.wait(1000, function() return #history.get_all() >= 2 end);
    
    local all_history = history.get_all();
    -- Turn 1: Model grep
    -- Turn 2: Tool output (handled internally in run_loop)
    -- Turn 3: Final answer
    assert.True(#all_history >= 2);
    assert.match("I found 'Agentic'", all_history[#all_history].assistant);
    
    job.run = old_run;
  end);
end);
