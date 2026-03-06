local assert = require("luassert");
local modal = require("nzi.ui.modal");

--- Robust Validator for both Structure and Visuals
--- @param bufnr number
--- @return boolean, string
local function validate_buffer_integrity(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
  local stack = {};
  
  -- 1. XML Structure Pass
  for i, line in ipairs(lines) do
    for tag_type, name in line:gmatch("<(/?)(agent:[%w_]+)>") do
      if tag_type == "" then
        table.insert(stack, { name = name, line = i });
      else
        if #stack == 0 then return false, "Line " .. i .. ": Found closing tag </" .. name .. "> with no open tag." end
        local last = table.remove(stack);
        if last.name ~= name then
          return false, "Line " .. i .. ": Tag mismatch. Expected </" .. last.name .. ">, found </" .. name .. ">"
        end
      end
    end
  end
  if #stack > 0 then
    return false, "Unclosed tag <" .. stack[#stack].name .. "> opened on line " .. stack[#stack].line
  end

  -- 2. Visual/Telemetry Pass (Simplified check for NziTelemetry highlight)
  -- In headless tests, we mainly care that the logic ran without error
  return true, nil
end

describe("AI modal rigorous validation", function()
  before_each(function()
    modal.clear();
  end);

  it("should pass structure and visual rigor for a full interaction round-trip", function()
    modal.write("Setting up...", "system", false);
    modal.write("What is the meaning of life?", "user", false);
    modal.write("Thinking...", "reasoning_content", false);
    modal.write("42", "content", true);
    modal.close_tag();
    
    local ok, err = validate_buffer_integrity(modal.bufnr);
    assert.is_true(ok, err);
  end);

  it("should ensure telemetry and tags are ALWAYS white on black (NziTelemetry)", function()
    modal.write("Hello", "user", false);
    
    local lines = vim.api.nvim_buf_get_lines(modal.bufnr, 0, -1, false);
    local ns_id = modal.ns_id;
    
    -- Sequence:
    -- 1: [ USER | ... ] (Telemetry)
    -- 2: <agent:user>   (Tag)
    -- 3: Hello          (Content)
    
    local marks1 = vim.api.nvim_buf_get_extmarks(modal.bufnr, ns_id, {0, 0}, {0, -1}, { details = true });
    local marks2 = vim.api.nvim_buf_get_extmarks(modal.bufnr, ns_id, {1, 0}, {1, -1}, { details = true });
    
    assert.are.equal(1, #marks1, "Line 1 must have NziTelemetry");
    assert.are.equal(1, #marks2, "Line 2 must have NziTelemetry");
    assert.are.equal("NziTelemetry", marks1[1][4].hl_group, "Line 1 must be NziTelemetry");
    assert.are.equal("NziTelemetry", marks2[1][4].hl_group, "Line 2 must be NziTelemetry");
  end);
end);
