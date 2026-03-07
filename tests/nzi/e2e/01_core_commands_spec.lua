local assert = require("luassert")
local config = require("nzi.core.config")
local commands = require("nzi.core.commands")
local modal = require("nzi.ui.modal")

describe("1. Initialization & Core Commands", function()
  before_each(function()
    require("nzi").setup({})
    require("nzi.dom.session").clear()
    modal.clear()
    -- reset config to defaults
    config.setup({})
  end)

  after_each(function()
    modal.close()
  end)

  it("should have :AI command registered", function()
    local cmds = vim.api.nvim_get_commands({})
    assert.truthy(cmds.AI, ":AI command should be registered")
  end)

  it("should toggle the modal with :AI/toggle", function()
    -- initially modal is closed
    assert.falsy(modal.winid)
    
    -- simulate :AI/toggle
    vim.cmd("AI/toggle")
    assert.truthy(modal.winid, "Modal should be open after toggle")
    assert.truthy(vim.api.nvim_win_is_valid(modal.winid))
    
    vim.cmd("AI/toggle")
    assert.falsy(modal.winid, "Modal should be closed after second toggle")
  end)

  it("should switch the active model with :AI/model <name>", function()
    local initial_model = config.options.active_model
    assert.equals("defaultModel", initial_model)
    
    -- Inject temporary models for the test
    config.options.models["mock_model"] = { provider = "ollama", model = "mock" }
    config.options.models["deepseek"] = { provider = "openrouter", model = "deepseek" }
    
    vim.cmd("AI/model mock_model")
    assert.equals("mock_model", config.options.active_model, "Model should switch to mock_model")
    
    -- Switch back
    vim.cmd("AI/model deepseek")
    assert.equals("deepseek", config.options.active_model, "Model should switch back to deepseek")
  end)

  it("should notify on unknown model alias", function()
    -- Mock vim.notify
    local notifications = {}
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notifications, {msg=msg, level=level})
    end
    
    vim.cmd("AI/model unknown_model")
    
    assert.equals(1, #notifications)
    assert.match("Unknown model alias", notifications[1].msg)
    assert.equals(vim.log.levels.ERROR, notifications[1].level)
    
    -- restore
    vim.notify = orig_notify
  end)

  it("should respect configuration overrides via setup()", function()
    require("nzi").setup({
      max_turns = 10,
      yolo = true
    })
    
    assert.equals(10, config.options.max_turns)
    assert.True(config.options.yolo)
    
    -- restore
    require("nzi").setup({ max_turns = 5, yolo = false })
  end)
end)
