local assert = require("luassert");
local ai = require("nzi");
local job = require("nzi.job");
local history = require("nzi.history");
local engine = require("nzi.engine");

describe("AI active model integration", function()
  -- These tests use the active model alias configured in the environment
  -- or the default 'deepseek'.
  
  local config = require("nzi.config");
  local original_yolo = config.options.yolo;

  before_each(function()
    config.options.yolo = true; -- Automate tool turns for integration tests
  end);

  after_each(function()
    config.options.yolo = original_yolo;
  end);
  
  local model_output = "";
  local original_write;

  local function setup_capture()
    model_output = "";
    original_write = require("nzi.modal").write;
    require("nzi.modal").write = function(text, type, append)
      if type == "assistant" or type == "content" or type == "response" then
        model_output = model_output .. text;
      end
      -- still call original but ignore its internal UI errors if any
      pcall(original_write, text, type, append);
    end
  end

  local function teardown_capture()
    require("nzi.modal").write = original_write;
  end

  it("should handle an ai? question end-to-end", function()
    setup_capture();
    engine.handle_question("Say exactly 'HELLO WORLD' and nothing else.", false);
    
    -- Wait for response (up to 20s for slow APIs)
    vim.wait(20000, function() 
      return model_output:match("HELLO WORLD") ~= nil 
    end);

    teardown_capture();
    assert.match("HELLO WORLD", model_output);
  end);

  it("should handle command-line directive end-to-end", function()
    setup_capture();
    engine.dispatch({ args = ":Say only 'DIRECTIVE'", line1 = 1, line2 = 1, range = 0 });
    
    vim.wait(20000, function() 
      return model_output:match("DIRECTIVE") ~= nil 
    end);

    teardown_capture();
    assert.match("DIRECTIVE", model_output);
  end);

  it("BATTLE TEST: should maintain state across a multi-turn conversation", function()
    history.clear();
    
    -- Turn 1: Establish a fact
    setup_capture();
    engine.handle_question("My favorite color is Crimson. Remember that.", false);
    
    vim.wait(20000, function() 
      return #history.get_all() >= 1 
    end);
    teardown_capture();
    assert.True(#history.get_all() >= 1, "Turn 1 was not added to history.");

    -- Turn 2: Query the fact
    setup_capture();
    engine.handle_question("What is my favorite color? Answer in one word.", false);
    
    vim.wait(20000, function() 
      return model_output:upper():match("CRIMSON") ~= nil 
    end);
    teardown_capture();

    assert.match("CRIMSON", model_output:upper());
  end);

  it("BATTLE TEST: should see and synthesize information from multiple buffers", function()
    history.clear();
    
    -- Create two buffers with distinct info
    local b1 = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_buf_set_name(b1, "info1.txt");
    vim.api.nvim_buf_set_lines(b1, 0, -1, false, { "The secret code is 1234" });
    
    local b2 = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_buf_set_name(b2, "info2.txt");
    vim.api.nvim_buf_set_lines(b2, 0, -1, false, { "The other code is 5678" });

    setup_capture();
    engine.handle_question("What are the two secret codes in my open buffers? Respond with just the numbers.", false);
    
    local success = vim.wait(20000, function() 
      return model_output:match("1234") and model_output:match("5678")
    end);

    teardown_capture();
    
    -- Cleanup
    vim.api.nvim_buf_delete(b1, { force = true });
    vim.api.nvim_buf_delete(b2, { force = true });
    
    if not success then
      error("Synthesis test timed out. Model output: " .. model_output)
    end

    assert.match("1234", model_output);
    assert.match("5678", model_output);
  end);
end);
