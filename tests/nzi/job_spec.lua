local assert = require("luassert");
local nzi = require("nzi");
local job = require("nzi.job");

describe("nzi job wrapper", function()
  -- Use the mock LLM script for testing
  local mock_llm = vim.fn.getcwd() .. "/tests/mock_llm.sh";

  before_each(function()
    nzi.setup({
      model_cmd = { mock_llm },
      default_model = "test-model",
    });
  end);

  it("should successfully run a mock job and return stdout", function(done)
    local prompt = "Hello Mock";
    
    job.run(prompt, function(success, result)
      assert.is_true(success);
      assert.is_string(result);
      assert.match("MOCK_RESPONSE", result);
      assert.match("test-model", result);
      assert.match("Hello Mock", result);
      done();
    end);
  end);

  it("should fail and return stderr when the job exits with non-zero code", function(done)
    local prompt = "FAIL_ME";
    
    job.run(prompt, function(success, result)
      assert.is_false(success);
      assert.match("Job failed with code 1", result);
      assert.match("Simulated LLM failure message", result);
      done();
    end);
  end);
end);
