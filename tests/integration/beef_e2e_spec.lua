local assert = require("luassert");
local ai = require("nzi");
local job = require("nzi.service.llm.job");
local config = require("nzi.core.config");

describe("BEEF E2E: Real LLM Integration", function()
  
  before_each(function()
    -- Ensure we are using the environment variables
    require("nzi").setup();
    require("nzi.dom.session").clear();
  end);

  it("should answer 'Where's the beef?' using a real LLM call", function()
    local model_alias = config.options.active_model;
    local model_cfg = config.get_active_model();

    -- Check if we have an API key or a local endpoint
    if not model_cfg or (not model_cfg.api_key and not (model_cfg.api_base or ""):match("192%.168")) then
      pending("Skipping Beef E2E: No API key or local model configured for " .. tostring(model_alias));
      return;
    end

    local model_output = "";
    local done = false;
    local success_result = false;

    print("\n[BEEF E2E] Sending request to model: " .. model_alias .. " (" .. (model_cfg.model or "unknown") .. ")\n");

    job.run("Say exactly 'Where's the beef?' and nothing else.", function(success, result)
      success_result = success;
      model_output = result;
      done = true;
    end, function(chunk, type)
      if type == "content" then
        io.write(chunk);
        io.flush();
      end
    end);

    -- 30s timeout for real network call
    local wait_success = vim.wait(30000, function()
      return done
    end);

    print("\n[BEEF E2E] Final Output: " .. model_output .. "\n");

    assert.is_true(wait_success, "Beef E2E timed out after 30 seconds.");
    assert.is_true(success_result, "Beef E2E job failed: " .. tostring(model_output));
    assert.match("Where's the beef", model_output, 1, true);
  end);
end);
