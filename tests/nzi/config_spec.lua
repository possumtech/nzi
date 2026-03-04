local assert = require("luassert");
local nzi = require("nzi");
local config = require("nzi.config");

describe("nzi configuration", function()
  it("should have default settings", function()
    assert.are.equal("litellm", config.options.litellm_cmd);
    assert.are.equal("gpt-4-turbo", config.options.default_model);
  end);

  it("should allow user overrides via setup", function()
    nzi.setup({
      litellm_cmd = "custom-llm",
      default_model = "claude-3-opus",
    });
    
    assert.are.equal("custom-llm", config.options.litellm_cmd);
    assert.are.equal("claude-3-opus", config.options.default_model);
  end);

  it("should preserve defaults for non-overridden keys", function()
    nzi.setup({
      litellm_cmd = "new-path",
    });
    
    assert.are.equal("new-path", config.options.litellm_cmd);
    assert.are.equal(80, config.options.modal.width); -- Default from config.lua
  end);
end);
