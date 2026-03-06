local assert = require("luassert")
local engine = require("nzi.engine.engine")
local parser = require("nzi.engine.parser")

describe("4. Input Parsing & Selection", function()
  local test_buf

  before_each(function()
    test_buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(test_buf, "test_parsing.lua")
    vim.api.nvim_set_current_buf(test_buf)
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(test_buf) then
      vim.api.nvim_buf_delete(test_buf, { force = true })
    end
  end)

  it("should parse single line directive and extract it", function()
    local type, content = parser.parse_line(":AI: refactor this")
    assert.equals("directive", type)
    assert.equals("refactor this", content)
  end)

  it("should parse Question, Directive, and Shell prefixes flawlessly", function()
    local type1, content1 = parser.parse_line(":AI? what is this?")
    assert.equals("question", type1)
    assert.equals("what is this?", content1)

    local type2, content2 = parser.parse_line(":AI! ls -la")
    assert.equals("shell", type2)
    assert.equals("ls -la", content2)
  end)

  it("should correctly identify range bounds and extract inline directives", function()
    local lines = {
      "function foo()",
      ":AI: modify the loop",
      "  for i = 1, 10 do",
      "  end",
      "end"
    }
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, lines)
    
    -- Mock the engine run_loop to trap the results
    local captured_content, captured_type, captured_selection
    local orig_run_loop = engine.run_loop
    engine.run_loop = function(content, type, include_lsp, target_file, selection)
      captured_content = content
      captured_type = type
      captured_selection = selection
    end

    engine.execute_range(1, 5)

    -- verify that the directive line was deleted from buffer
    local new_lines = vim.api.nvim_buf_get_lines(test_buf, 0, -1, false)
    assert.equals(4, #new_lines)
    assert.equals("function foo()", new_lines[1])
    assert.equals("  for i = 1, 10 do", new_lines[2])

    -- verify that engine.run_loop received the correct stuff
    assert.equals("modify the loop", captured_content)
    assert.equals("directive", captured_type)
    assert.truthy(captured_selection)
    assert.equals(5, captured_selection.end_line)
    
    engine.run_loop = orig_run_loop
  end)

  it("should capture character-perfect visual selection (v mode)", function()
    vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, { "abcdefg" })
    
    -- simulate visual selection of 'bcd' (col 2 to 4)
    vim.api.nvim_win_set_cursor(0, {1, 1}) -- 0-indexed column 1 is 'b'
    vim.cmd("normal! v")
    vim.api.nvim_win_set_cursor(0, {1, 3}) -- 0-indexed column 3 is 'd'
    vim.cmd("normal! \27") -- exit visual mode
    
    local sel = engine.get_visual_selection()
    assert.equals("bcd", sel.text)
    assert.equals(1, sel.start_line)
    assert.equals(2, sel.start_col)
    assert.equals(1, sel.end_line)
    assert.equals(4, sel.end_col)
    assert.equals("v", sel.mode)
  end)
end)
