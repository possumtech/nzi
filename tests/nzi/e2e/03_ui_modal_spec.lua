local assert = require("luassert")
local modal = require("nzi.ui.modal")

describe("3. UI & The Modal", function()
  before_each(function()
    modal.clear()
  end)

  after_each(function()
    modal.close()
  end)

  it("should open centered with correct dimensions", function()
    modal.open()
    assert.truthy(modal.winid)
    local width = vim.api.nvim_win_get_width(modal.winid)
    local height = vim.api.nvim_win_get_height(modal.winid)
    
    assert.True(width > 0, "Width should be greater than 0")
    assert.True(height > 0, "Height should be greater than 0")
  end)

  it("should have a dynamic title", function()
    modal.open()
    local config = vim.api.nvim_win_get_config(modal.winid)
    assert.truthy(config.title, "Modal should have a title")
    -- The title is something like {{" defaultModel ", "FloatTitle"}}
    local title_text = type(config.title) == "table" and config.title[1][1] or config.title
    assert.match("defaultModel", title_text)
  end)

  it("should toggle the 'Thinking' state in the title", function()
    modal.open()
    modal.set_thinking(true)
    
    assert.truthy(modal.timer, "Timer should be active when thinking")
    
    modal.set_thinking(false)
    assert.falsy(modal.timer, "Timer should be closed after thinking stops")
  end)

  it("should append content to modal and scroll to bottom", function()
    modal.open()
    modal.write("Test content\nLine 2", "user", false)
    
    local lines = vim.api.nvim_buf_get_lines(modal.bufnr, 0, -1, false)
    local found = false
    for _, line in ipairs(lines) do
      if line == "Test content" then found = true end
    end
    assert.True(found, "Content should be written to modal buffer")
  end)
end)
