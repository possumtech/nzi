local assert = require("luassert");
local ai = require("nzi");
local job = require("nzi.job");

describe("AI job wrapper (LiteLLM Bridge)", function()
  
  before_each(function()
    ai.setup({
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

  it("should successfully parse bridge output", function(done)
    -- This test verifies the parsing logic without network calls
    local messages = {{ role = "user", content = "Hello Mock" }};
    
    -- Mock the system call to simulate a bridge response
    local original_system = vim.system;
    vim.system = function(cmd, opts, on_exit)
      assert.are.equal("python3", cmd[1]);
      
      -- Bridge outputs raw JSON chunks (one per line)
      opts.stdout(nil, "{\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n");
      opts.stdout(nil, "{\"choices\":[{\"delta\":{\"content\":\" World\"}}]}\n");
      
      on_exit({ code = 0, stdout = "", stderr = "" });
      return { kill = function() end };
    end

    job.run(messages, function(success, result)
      assert.is_true(success);
      assert.are.equal("Hello World", result);
      
      -- Restore original
      vim.system = original_system;
      done();
    end, function(chunk, type)
      -- This is called for each chunk
    end);
  end);

  it("should handle reasoning/thought tokens from bridge", function(done)
    local original_system = vim.system;
    vim.system = function(cmd, opts, on_exit)
      -- Bridge outputs raw JSON chunks
      opts.stdout(nil, "{\"choices\":[{\"delta\":{\"reasoning_content\":\"I am thinking\"}}]}\n");
      opts.stdout(nil, "{\"choices\":[{\"delta\":{\"content\":\"Final answer\"}}]}\n");
      
      on_exit({ code = 0, stdout = "", stderr = "" });
      return { kill = function() end };
    end

    local thoughts = "";
    job.run({{role="user", content="Think"}}, function(success, result)
      assert.is_true(success);
      assert.are.equal("Final answer", result);
      assert.are.equal("I am thinking", thoughts);
      
      vim.system = original_system;
      done();
    end, function(chunk, type)
      if type == "reasoning_content" then thoughts = thoughts .. chunk end
    end);
  end);

  it("should fail gracefully on non-zero exit code", function(done)
    local original_system = vim.system;
    vim.system = function(cmd, opts, on_exit)
      on_exit({ code = 1, stdout = "", stderr = "ModuleNotFoundError: No module named 'litellm'" });
      return { kill = function() end };
    end

    job.run({{role="user", content="FAIL"}}, function(success, result)
      assert.is_false(success);
      assert.match("Dependency missing: LiteLLM not found", result);
      
      vim.system = original_system;
      done();
    end);
  end);
end);
