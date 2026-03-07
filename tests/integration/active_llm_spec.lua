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
  local function poll_until_settle(expected_turns, timeout_ms)
    local start = vim.loop.now();
    
    -- We wait for at least expected_turns AND for the engine to be idle.
    -- DeepSeek might take multiple turns to respond if it chooses to analyze.
    while (vim.loop.now() - start) < timeout_ms do
      local current_turns = #history.get_all();
      if engine.is_busy == false and engine.current_job == nil then
        if current_turns >= expected_turns then
          return true;
        end
      end
      vim.wait(2000); -- Spin the loop, give model time
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

  it("should complete a series of real LLM interactions (CONSOLIDATED)", function()
    -- 1. HELLO WORLD
    engine.run_loop("Say exactly 'HELLO WORLD' and nothing else.", "ask", false);
    assert.True(poll_until_settle(1, 60000), "HELLO WORLD turn failed");
    assert.True(history_contains("HELLO WORLD"));

    -- 2. BATTLE TEST (Multi-turn State)
    local base_turns = #history.get_all();
    engine.run_loop("My favorite color is Crimson. Remember that.", "ask", false);
    -- Allow for analysis turns if model chooses
    assert.True(poll_until_settle(base_turns + 1, 120000), "State establishment failed");

    local turns_after_2 = #history.get_all();
    engine.run_loop("What is my favorite color? Answer in one word.", "ask", false);
    assert.True(poll_until_settle(turns_after_2 + 1, 60000), "State query failed");
    assert.True(history_contains("CRIMSON"));

    -- 3. BATTLE TEST (Multi-buffer)
    local base_turns_3 = #history.get_all();
    local b1 = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_buf_set_name(b1, "info1.txt");
    vim.api.nvim_buf_set_lines(b1, 0, -1, false, { "The secret code is 1234" });
    
    local b2 = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_buf_set_name(b2, "info2.txt");
    vim.api.nvim_buf_set_lines(b2, 0, -1, false, { "The other code is 5678" });

    engine.run_loop("What are the two secret codes in my open buffers? Respond with just the numbers.", "ask", false);
    assert.True(poll_until_settle(base_turns_3 + 1, 120000), "Multi-buffer synthesis failed");

    assert.True(history_contains("1234"), "Missing code 1234");
    assert.True(history_contains("5678"), "Missing code 5678");
    
    -- Cleanup
    vim.api.nvim_buf_delete(b1, { force = true });
    vim.api.nvim_buf_delete(b2, { force = true });
  end);
end);
