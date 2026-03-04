local assert = require("luassert");
local modal = require("nzi.modal");

--- A deterministic XML structural validator for Nzi Tags
local function validate_xml_integrity(lines)
  local stack = {};
  local full_text = table.concat(lines, "\n");
  for tag_type, name in full_text:gmatch("<(/?)(agent:[%w_]+)>") do
    if tag_type == "" then
      table.insert(stack, name);
    else
      if #stack == 0 then return false, "Found closing tag </" .. name .. "> with no open tag." end
      local last = table.remove(stack);
      if last ~= name then return false, "Tag mismatch: expected </" .. last .. ">, got </" .. name .. ">" end
    end
  end
  if #stack > 0 then return false, "Unclosed tags remaining: " .. table.concat(stack, ", ") end
  return true;
end

describe("AI modal structural integrity", function()
  before_each(function()
    modal.clear();
  end);

  it("should maintain valid XML structure across multiple transitions", function()
    modal.write("System rules", "system", false);
    modal.write("Context data", "context", true);
    modal.write("User question", "user", true);
    modal.write("Thinking...", "reasoning_content", true);
    modal.write("Final answer", "content", true);
    modal.close_tag();
    
    local lines = vim.api.nvim_buf_get_lines(modal.bufnr, 0, -1, false);
    local ok, err = validate_xml_integrity(lines);
    assert.is_true(ok, err);
  end);

  it("should correctly handle append=false mid-interaction", function()
    modal.write("Turn 1", "user", false);
    modal.write("Reply 1", "assistant", true);
    
    -- New interaction closes previous
    modal.write("Turn 2", "user", false);
    modal.close_tag();
    
    local lines = vim.api.nvim_buf_get_lines(modal.bufnr, 0, -1, false);
    local text = table.concat(lines, "\n");
    
    assert.match("<agent:user>%s*Turn 1%s*</agent:user>", text);
    assert.match("<agent:assistant>%s*Reply 1%s*</agent:assistant>", text);
    assert.match("<agent:user>%s*Turn 2%s*</agent:user>", text);
    
    local ok, err = validate_xml_integrity(lines);
    assert.is_true(ok, err);
  end);

  it("should produce valid XML even with complex multi-line content", function()
    modal.write("Line 1\nJust some text\nLine 2", "user", false);
    modal.write("Code block\n```lua\nlocal x = 1\n```", "assistant", true);
    modal.close_tag();
    
    local lines = vim.api.nvim_buf_get_lines(modal.bufnr, 0, -1, false);
    local ok, err = validate_xml_integrity(lines);
    assert.is_true(ok, err);
  end);
end);
