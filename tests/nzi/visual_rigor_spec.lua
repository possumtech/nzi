local assert = require("luassert");
local modal = require("nzi.ui.modal");
local xml = require("tests.xml_helper");

describe("AI modal rigorous validation", function()
  before_each(function()
    modal.clear();
  end);

  it("should pass structure and visual rigor for a full interaction round-trip", function()
    -- 1. Simulate Turn 0 (Preamble)
    modal.write("System Preamble", "system", false, 0);
    modal.close_tag();

    -- 2. Simulate Turn 1 (User Ask)
    modal.write("What is the meaning of life?", "user", false, 1);
    
    -- 3. Simulate Assistant Response
    modal.write("Thinking...", "reasoning_content", false, 1);
    modal.write("42", "content", false, 1);
    modal.write("Answered.", "assistant", false, 1);
    
    modal.close_tag(); -- Close Turn 1
    
    -- 4. Rigorous validation of the full buffer XML
    local bufnr = modal.bufnr;
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
    local full_xml = table.concat(lines, "\n");
    
    xml.assert_valid(full_xml);
  end);

  it("should ensure telemetry and tags are ALWAYS white on black (NziTelemetry)", function()
    modal.write("Hello", "user", false, 0);
    
    local ns_id = modal.ns_id;
    
    -- Telemetry/Tags are on the first few lines of a turn
    local marks1 = vim.api.nvim_buf_get_extmarks(modal.bufnr, ns_id, {0, 0}, {0, -1}, { details = true });
    local marks2 = vim.api.nvim_buf_get_extmarks(modal.bufnr, ns_id, {1, 0}, {1, -1}, { details = true });
    
    assert.are.equal("NziTelemetry", marks1[1][4].hl_group, "Line 1 must be NziTelemetry");
    assert.are.equal("NziTelemetry", marks2[1][4].hl_group, "Line 2 must be NziTelemetry");
  end);
end);
