local assert = require("luassert");
local modal = require("nzi.modal");

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
        if last.name ~= name then return false, "Line " .. i .. ": Tag mismatch. Expected </" .. last.name .. ">, got </" .. name .. ">" end
      end
    end
  end
  if #stack > 0 then return false, "Unclosed tags: " .. stack[1].name .. " at line " .. stack[1].line end

  -- 2. Highlighting Pass (The "Rigor" Check)
  local ns_id = modal.ns_id;
  for i = 0, #lines - 1 do
    local text = lines[i+1];
    -- Check if line is empty/spacer
    if text ~= "" then
      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, {i, 0}, {i, -1}, { details = true });
      
      if #extmarks == 0 then
        return false, "Line " .. (i+1) .. " is see-through! Missing Nzi highlight: '" .. text .. "'";
      end
      
      local hl_group = extmarks[1][4].hl_group;
      if not hl_group:match("^Nzi") then
        return false, "Line " .. (i+1) .. " has invalid highlight: " .. hl_group;
      end
      
      -- Telemetry Rigor: Tags <...> and Telemetry [ Brackets ] MUST be NziTelemetry
      if text:match("^<") or text:match("^%[") or text:match("^</") then
        if hl_group ~= "NziTelemetry" then
          return false, "Line " .. (i+1) .. " should be NziTelemetry but is " .. hl_group .. " ('" .. text .. "')";
        end
      end
    end
  end

  return true, "OK";
end

describe("AI modal rigorous validation", function()
  before_each(function()
    modal.clear();
  end);

  it("should pass structure and visual rigor for a full interaction round-trip", function()
    modal.write("System rules", "system", false);
    modal.write("Context data", "context", true);
    modal.write("User question", "user", true);
    modal.write("Thinking...", "reasoning_content", true);
    modal.write("Final answer", "content", true);
    modal.close_tag();
    
    local ok, err = validate_buffer_integrity(modal.bufnr);
    assert.is_true(ok, err);
  end);

  it("should ensure telemetry and tags are ALWAYS white on black (NziTelemetry)", function()
    modal.write("Hello", "user", false);
    modal.close_tag();
    
    local lines = vim.api.nvim_buf_get_lines(modal.bufnr, 0, -1, false);
    local ns_id = modal.ns_id;
    
    -- Sequence:
    -- 1: [ USER | ... ] (Telemetry)
    -- 2: <agent:user>      (Tag)
    -- 3: Hello          (Content)
    -- 4: </agent:user>     (Tag)
    
    local marks1 = vim.api.nvim_buf_get_extmarks(modal.bufnr, ns_id, {0, 0}, {0, -1}, { details = true });
    local marks2 = vim.api.nvim_buf_get_extmarks(modal.bufnr, ns_id, {1, 0}, {1, -1}, { details = true });
    local marks4 = vim.api.nvim_buf_get_extmarks(modal.bufnr, ns_id, {3, 0}, {3, -1}, { details = true });
    
    assert.are.equal("NziTelemetry", marks1[1][4].hl_group, "Line 1 must be NziTelemetry");
    assert.are.equal("NziTelemetry", marks2[1][4].hl_group, "Line 2 must be NziTelemetry");
    assert.are.equal("NziTelemetry", marks4[1][4].hl_group, "Line 4 must be NziTelemetry");
  end);
end);
