local assert = require("luassert");
local config = require("nzi.core.config");
local modal = require("nzi.ui.modal");

describe("NZI: THE BRUTAL E2 drill", function()
  
  local api_key = vim.env.NZI_API_KEY or vim.env.OPENROUTER_API_KEY;

  before_each(function()
    require("nzi").setup({
      yolo = true
    });
    require("nzi.dom.session").clear();
    require("nzi.ui.modal").clear();
    pcall(vim.cmd, "close");
    vim.cmd("runtime plugin/nzi.lua")
  end);

  local function wait_for_turn(expected_count, timeout)
    return vim.wait(timeout or 30000, function()
      local b = modal.bufnr
      if b and vim.api.nvim_buf_is_valid(b) then
        local content = table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n")
        local _, count = content:gsub("</turn>", "")
        return count >= expected_count
      end
      return false
    end, 10);
  end

  it("DRILL 1: Ask Mode (AI? ...)", function()
    if not api_key then pending("No API key") return end

    -- Turn 0 exists, we wait for Turn 1 to close
    vim.cmd("AI? Say exactly 'DRILL_SUCCESS' and nothing else.")

    assert.is_true(wait_for_turn(2), "Ask mode failed to return content or close tag.");
    
    local final_content = table.concat(vim.api.nvim_buf_get_lines(modal.bufnr, 0, -1, false), "\n");
    assert.match("<turn id=\"1\"", final_content);
    assert.match("<content>DRILL_SUCCESS</content>", final_content);
  end);

  it("DRILL 2: Run Mode (AI! ...)", function()
    -- Wait for preamble
    assert.is_true(wait_for_turn(1), "Turn 0 not ready");

    local bufnr = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_set_current_buf(bufnr);
    
    vim.cmd("AI ! echo 'SHELL_SUCCESS'")
    
    local success = vim.wait(10000, function()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false);
      for _, line in ipairs(lines) do
        if line:match("SHELL_SUCCESS") then return true end
      end
      return false
    end);

    assert.is_true(success, "Run mode failed to inject shell output into buffer.");
    -- Run mode adds a turn (Turn 1)
    assert.is_true(wait_for_turn(2), "Run mode turn never finalized.");
  end);

  it("DRILL 3: Instruct Mode (AI: ...)", function()
    if not api_key then pending("No API key") return end

    -- Ensure Turn 0 is ready
    assert.is_true(wait_for_turn(1), "Turn 0 not ready before Drill 3");

    local test_file = "drill_test.txt";
    local f = io.open(test_file, "w");
    f:write("Original Content\n");
    f:close();

    vim.cmd("edit " .. test_file);
    
    vim.cmd("AI: Replace 'Original' with 'DRILL'")

    assert.is_true(wait_for_turn(2), "Instruct mode failed to propose an edit.");
    
    local session = require("nzi.dom.session");
    local xml = session.format();
    assert.match("<edit file=\"drill_test.txt\">", xml);
    
    os.remove(test_file);
  end);

  it("DRILL 4: Visual Selection Context", function()
    if not api_key then pending("No API key") return end

    -- Ensure Turn 0 is ready
    assert.is_true(wait_for_turn(1), "Turn 0 not ready before Drill 4");

    local bufnr = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Line 1", "Line 2", "Line 3" });
    vim.api.nvim_set_current_buf(bufnr);
    
    -- Select Line 2
    vim.fn.cursor(2, 1);
    vim.cmd("normal! V");
    
    vim.cmd("AI? What is this selection?")

    assert.is_true(wait_for_turn(2), "Visual selection query failed.");
    
    local session = require("nzi.dom.session");
    local xml = session.format();
    assert.match("<selection", xml);
    assert.match("Line 2", xml);
  end);
end);
