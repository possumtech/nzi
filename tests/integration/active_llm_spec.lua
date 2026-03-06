local assert = require("luassert");
local ai = require("nzi");
local history = require("nzi.context.history");
local engine = require("nzi.engine.engine");
local config = require("nzi.core.config");

describe("AI active model integration", function()
  local original_yolo = config.options.yolo;

  before_each(function()
    history.clear();
    config.options.yolo = true; -- Automate tool turns
  end);

  after_each(function()
    config.options.yolo = original_yolo;
  end);

  --- Custom polling helper that actually allows the event loop to spin
  local function poll_until_settle(timeout_ms)
    local start = vim.loop.now();
    while (vim.loop.now() - start) < timeout_ms do
      if engine.is_busy == false and engine.current_job == nil then
        if #history.get_all() > 0 then
          return true;
        end
      end
      vim.cmd("sleep 500m"); -- Slower spin for real API calls
    end
    return false;
  end

  --- Helper to check if a string exists ANYWHERE in the conversation history
  local function history_contains(pattern)
    local all = history.get_all();
    for _, turn in ipairs(all) do
      local assistant = history.strip_line_numbers(turn.assistant or "");
      if assistant:upper():match(pattern:upper()) then
        return true;
      end
      local user = history.strip_line_numbers(turn.user or "");
      if user:upper():match(pattern:upper()) then
        return true;
      end
    end
    return false;
  end

  it("should handle an ai? question end-to-end", function()
    engine.handle_question("Say exactly 'HELLO WORLD' and nothing else.", false);
    
    assert.True(poll_until_settle(120000), "Interaction timed out");
    assert.True(history_contains("HELLO WORLD"), "Model did not provide expected response in history");
  end);

  it("should handle command-line directive end-to-end", function()
    engine.dispatch({ args = ":AI: Say only 'DIRECTIVE'", line1 = 1, line2 = 1, range = 0 });
    
    assert.True(poll_until_settle(120000), "Interaction timed out");
    assert.True(history_contains("DIRECTIVE"));
  end);

  it("BATTLE TEST: should maintain state across a multi-turn conversation", function()
    -- Turn 1: Establish a fact
    engine.handle_question("My favorite color is Crimson. Remember that.", false);
    assert.True(poll_until_settle(40000), "Turn 1 timed out");

    -- Turn 2: Query the fact
    engine.handle_question("What is my favorite color? Answer in one word.", false);
    assert.True(poll_until_settle(40000), "Turn 2 timed out");

    assert.True(history_contains("CRIMSON"), "Model forgot the fact established in Turn 1");
  end);

  it("BATTLE TEST: should see and synthesize information from multiple buffers", function()
    -- Create two buffers with distinct info
    local b1 = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_buf_set_name(b1, "info1.txt");
    vim.api.nvim_buf_set_lines(b1, 0, -1, false, { "The secret code is 1234" });
    
    local b2 = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_buf_set_name(b2, "info2.txt");
    vim.api.nvim_buf_set_lines(b2, 0, -1, false, { "The other code is 5678" });

    engine.handle_question("What are the two secret codes in my open buffers? Respond with just the numbers.", false);
    
    assert.True(poll_until_settle(120000), "Synthesis timed out");

    assert.True(history_contains("1234"), "Missing first code");
    assert.True(history_contains("5678"), "Missing second code");
    
    -- Cleanup
    vim.api.nvim_buf_delete(b1, { force = true });
    vim.api.nvim_buf_delete(b2, { force = true });
  end);
end);
