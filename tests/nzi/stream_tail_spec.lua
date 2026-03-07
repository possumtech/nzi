local assert = require("luassert");
local nzi = require("nzi");
local job = require("nzi.service.llm.job");

describe("AI stream tail processing", function()
  
  before_each(function()
    nzi.setup({
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

  it("MUST process the final chunk even if it lacks a trailing newline", function(done)
    local prompt = "Test Tail";
    
    local original_system = vim.system;
    vim.system = function(cmd, opts, on_exit)
      -- 1. Send valid line with newline
      opts.stdout(nil, "data: {\"choices\":[{\"delta\":{\"content\":\"First part \"}}]}\n");
      
      -- 2. Send the "TAIL": valid JSON but NO NEWLINE at the end of the stream
      opts.stdout(nil, "data: {\"choices\":[{\"delta\":{\"content\":\"Second part\"}}]}");
      
      -- 3. Exit the process
      on_exit({ code = 0, stdout = "", stderr = "" });
      return { stop = function() end };
    end

    local captured_stream = "";
    job.run(prompt, function(success, result)
      -- The final result should contain BOTH parts
      assert.are.equal("First part Second part", result);
      assert.are.equal("First part Second part", captured_stream);
      
      vim.system = original_system;
      done();
    end, function(chunk, type)
      if type == "content" then
        captured_stream = captured_stream .. chunk
      end
    end);
  end);

  it("should handle the data: [DONE] marker correctly", function(done)
    local original_system = vim.system;
    vim.system = function(cmd, opts, on_exit)
      opts.stdout(nil, "data: {\"choices\":[{\"delta\":{\"content\":\"Final\"}}]}\n");
      opts.stdout(nil, "data: [DONE]\n");
      on_exit({ code = 0, stdout = "", stderr = "" });
      return { stop = function() end };
    end

    job.run("DONE TEST", function(success, result)
      assert.are.equal("Final", result);
      vim.system = original_system;
      done();
    end);
  end);

  it("MUST handle mid-stream errors gracefully", function(done)
    local original_system = vim.system;
    vim.system = function(cmd, opts, on_exit)
      opts.stdout(nil, "data: {\"choices\":[{\"delta\":{\"content\":\"First part \"}}]}\n");
      -- Simulate an OpenRouter error chunk
      opts.stdout(nil, "data: {\"error\":{\"code\":500,\"message\":\"Internal Server Error\"}}\n");
      on_exit({ code = 0, stdout = "", stderr = "" });
      return { stop = function() end };
    end

    job.run("ERROR TEST", function(success, result)
      assert.is_false(success);
      assert.match("Internal Server Error", result);
      vim.system = original_system;
      done();
    end);
  end);
end);
