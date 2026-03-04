local assert = require("luassert");
local nzi = require("nzi");
local config = require("nzi.config");

describe("AI configuration", function()
  it("should allow user overrides for active_model and model aliases", function()
    nzi.setup({
      active_model = "test-model",
      models = {
        ["test-model"] = {
          model = "gpt-5",
          api_base = "https://frontier.api",
          role_preference = "developer"
        }
      }
    });
    
    assert.are.equal("test-model", config.options.active_model);
    local active = config.get_active_model();
    assert.are.equal("gpt-5", active.model);
    assert.are.equal("developer", active.role_preference);
  end);

  it("should handle model_options like penalties and stop sequences", function()
    nzi.setup({
      model_options = {
        frequency_penalty = 0.5,
        stop = { "\n\n" }
      }
    });
    
    assert.are.equal(0.5, config.options.model_options.frequency_penalty);
    assert.are.same({ "\n\n" }, config.options.model_options.stop);
  end);
end);
