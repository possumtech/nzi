local assert = require("luassert");
local nzi = require("nzi");
local config = require("nzi.config");

describe("AI configuration", function()
  it("should allow user overrides via setup", function()
    nzi.setup({
      model_cmd = { "custom-python", "script.py" },
      default_model = "claude-3-opus",
    });
    
    assert.are.same({ "custom-python", "script.py" }, config.options.model_cmd);
    assert.are.equal("claude-3-opus", config.options.default_model);
  end);

  it("should preserve defaults for non-overridden keys", function()
    nzi.setup({
      api_base = "http://localhost:11434",
    });
    
    assert.are.equal("http://localhost:11434", config.options.api_base);
    assert.are.equal(80, config.options.modal.width); -- Default from config.lua
  end);
end);
