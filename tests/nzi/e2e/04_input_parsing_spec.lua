local assert = require("luassert")
local engine = require("nzi.engine.engine")
local parser = require("nzi.dom.parser")
local bridge = require("nzi.service.llm.bridge")

describe("4. Input Parsing & Selection", function()
  local test_buf

  before_each(function()
    test_buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(test_buf)
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(test_buf) then
      vim.api.nvim_buf_delete(test_buf, { force = true })
    end
  end)

  it("should parse single line instruct and extract it", function()
    local line = ":AI: Optimize this loop"
    local type, content = parser.parse_line(line)
    assert.equals("instruct", type)
    assert.equals("Optimize this loop", content)
  end)

  it("should parse Ask, Instruct, and Shell prefixes flawlessly", function()
    assert.equals("ask", (parser.parse_line(":AI? What is this?")))
    assert.equals("instruct", (parser.parse_line(":AI: fix bug")))
    assert.equals("run", (parser.parse_line(":AI! echo 123")))
  end)

  it("should correctly identify range bounds and extract inline instructs", function()
    local lines = {
      "function foo()",
      "  for i = 1, 10 do",
      ":AI: modify the loop",
      "  end",
      "end"
    }
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, lines)
    
    -- Mock the bridge start_loop to trap the results
    local captured_content, captured_type, captured_selection
    local old_start = bridge.start_loop
    bridge.start_loop = function(content, type, include_lsp, target_file, selection)
      captured_content = content
      captured_type = type
      captured_selection = selection
    end

    engine.execute_range(1, 5)

    -- Wait for the async call to be trapped
    local success = vim.wait(2000, function() return captured_content ~= nil end);
    assert.is_true(success, "Bridge was never called by execute_range");

    -- verify that the instruct line was deleted from buffer
    local new_lines = vim.api.nvim_buf_get_lines(test_buf, 0, -1, false)
    assert.equals(4, #new_lines)
    assert.equals("function foo()", new_lines[1])
    assert.equals("  for i = 1, 10 do", new_lines[2])

    -- verify that engine.run_loop received the correct stuff
    assert.equals("modify the loop", captured_content)
    assert.equals("instruct", captured_type)
    assert.truthy(captured_selection)
    assert.equals(5, captured_selection.end_line)
    
    bridge.start_loop = old_start
  end)

  it("should capture character-perfect visual selection (v mode)", function()
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, { "abcdefg" })
    
    -- simulate visual selection of 'bcd' (col 2 to 4)
    vim.api.nvim_win_set_cursor(0, {1, 1}) -- 0-indexed column 1 is 'b'
    vim.cmd("normal! v")
    vim.api.nvim_win_set_cursor(0, {1, 3}) -- 0-indexed column 3 is 'd'
    vim.cmd("normal! \27") -- exit visual mode
    
    local sel = bridge.get_visual_selection()
    assert.equals("bcd", sel.text)
    assert.equals(1, sel.start_line)
    assert.equals(2, sel.start_col)
    assert.equals(1, sel.end_line)
    assert.equals(4, sel.end_col)
    assert.equals("v", sel.mode)
  end)
end)
