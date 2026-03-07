local assert = require("luassert");
local config = require("nzi.core.config");

describe("STRESS E2E: Context and Synthesis", function()
  
  local model_alias = vim.env.NZI_MODEL or "deepseek";
  local model_cfg = config.options.models[model_alias];

  before_each(function()
    require("nzi").setup();
    require("nzi.dom.session").clear();
    require("nzi.ui.modal").clear();
    pcall(vim.cmd, "close");
  end);

  it("should handle large context (AGENTS.md) and answer correctly", function()
    if not model_cfg or (not model_cfg.api_key and not model_cfg.api_base:match("localhost")) then
      pending("Skipping Stress E2E: No config");
      return;
    end

    -- 1. Open AGENTS.md to ensure it's in context
    vim.cmd("edit AGENTS.md");
    
    print("\n[STRESS E2E] Executing :AI? summarize Phase 0 from AGENTS.md\n");

    -- 2. Ask a question that requires reading the context
    vim.cmd("AI? summarize Phase 0 from AGENTS.md exactly as written.");

    -- 3. Wait for full completion
    local modal = require("nzi.ui.modal")
    local success = vim.wait(60000, function()
      local b = modal.bufnr
      if b and vim.api.nvim_buf_is_valid(b) then
        local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
        local content = table.concat(lines, "\n")
        if content:match("</agent:content>") or content:match("</agent:error>") then
          return true
        end
      end
      return false
    end);

    local b = modal.bufnr
    local final_lines = vim.api.nvim_buf_get_lines(b, 0, -1, false);
    local final_content = table.concat(final_lines, "\n");
    
    print("\n[STRESS E2E] Scraped Modal Content:\n" .. final_content .. "\n");

    assert.is_true(success, "Stress E2E timed out.");
    
    if final_content:match("<agent:error>") then
      error("API Error returned in UI: " .. final_content);
    end

    -- Verify it actually read Phase 0 (Infrastructure & Core)
    assert.match("Infrastructure", final_content);
    assert.match("Scaffolding", final_content);
    
    -- Check for the "Phase 0" vs "Phase " mangling
    assert.match("Phase 0", final_content, 1, true);
  end);
end);
