local assert = require("luassert");
local ai = require("nzi");
local job = require("nzi.job");

describe("AI job wrapper (Pure Lua)", function()
  
  before_each(function()
    ai.setup({
      api_base = "http://localhost:11434/v1",
      api_key = "test-key",
      active_model = "default",
      models = {
        default = {
          model = "test-model",
          api_base = "http://localhost:11434/v1",
          api_key = "test-key",
        }
      }
    });
  end);

  it("should successfully parse OpenAI-compatible SSE chunks", function(done)
    -- This test verifies the parsing logic without network calls
    local prompt = "Hello Mock";
    
    -- Mock the system call to simulate a curl response
    local original_system = vim.system;
    vim.system = function(cmd, opts, on_exit)
      assert.are.equal("curl", cmd[1]);
      
      -- Simulate two chunks of SSE data
      opts.stdout(nil, "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n");
      opts.stdout(nil, "data: {\"choices\":[{\"delta\":{\"content\":\" World\"}}]}\n");
      opts.stdout(nil, "data: [DONE]\n");
      
      on_exit({ code = 0, stdout = "ignored", stderr = "" });
      return { stop = function() end };
    end

    job.run(prompt, function(success, result)
      assert.is_true(success);
      assert.are.equal("Hello World", result);
      
      -- Restore original
      vim.system = original_system;
      done();
    end, function(chunk, type)
      -- This is called for each chunk
    end);
  end);

  it("should handle reasoning/thought tokens in SSE stream", function(done)
    local original_system = vim.system;
    vim.system = function(cmd, opts, on_exit)
      -- DeepSeek/OpenAI O1 style reasoning
      opts.stdout(nil, "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"I am thinking\"}}]}\n");
      opts.stdout(nil, "data: {\"choices\":[{\"delta\":{\"content\":\"Final answer\"}}]}\n");
      opts.stdout(nil, "data: [DONE]\n");
      
      on_exit({ code = 0, stdout = "ignored", stderr = "" });
      return { stop = function() end };
    end

    local thoughts = "";
    job.run("Think about it", function(success, result)
      assert.is_true(success);
      assert.are.equal("Final answer", result);
      assert.are.equal("I am thinking", thoughts);
      
      vim.system = original_system;
      done();
    end, function(chunk, type)
      if type == "thought" then thoughts = thoughts .. chunk end
    end);
  end);

  it("should fail gracefully on non-zero exit code", function(done)
    local original_system = vim.system;
    vim.system = function(cmd, opts, on_exit)
      on_exit({ code = 7, stdout = "", stderr = "Failed to connect" });
      return { stop = function() end };
    end

    job.run("FAIL", function(success, result)
      assert.is_false(success);
      assert.match("API failed with code 7", result);
      
      vim.system = original_system;
      done();
    end);
  end);
end);
