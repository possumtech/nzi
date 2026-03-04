local assert = require("luassert");
local config = require("nzi.config");

describe("TRUE E2E: Full UI Lifecycle", function()
  
  local model_alias = vim.env.NZI_DEFAULT_MODEL or "coder";
  local model_cfg = config.options.models[model_alias];

  before_each(function()
    require("nzi").setup();
    require("nzi.history").clear();
    require("nzi.modal").clear();
    -- Close the modal window if it's open
    pcall(vim.cmd, "close");
    
    -- Ensure commands are available in the headless state
    vim.cmd("runtime plugin/nzi.lua")
  end);

  it("should execute :AI command and populate the UI modal with the response", function()
    if not model_cfg or (not model_cfg.api_key and not model_cfg.api_base:match("localhost")) then
      pending("Skipping True E2E: No API key or local model configured for " .. model_alias);
      return;
    end

    print("\n[TRUE E2E] Executing :AI? Say exactly 'Where's the beef?' and nothing else.\n");

    -- 1. Execute the command exactly as a user would
    vim.cmd("AI? Say exactly 'Where's the beef?' and nothing else.");

    -- 2. Wait for the modal buffer to appear and finish streaming
    local modal = require("nzi.modal")
    local success = vim.wait(45000, function()
      local b = modal.bufnr
      if b and vim.api.nvim_buf_is_valid(b) then
        -- Check if it contains the closing tag or an error
        local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
        local content = table.concat(lines, "\n")
        if content:match("</agent:content>") or content:match("</agent:error>") then
          return true
        end

      end
      return false
    end);

    -- 3. Scrape the UI buffer to assert
    assert.is_not_nil(modal.bufnr, "Modal buffer was never created.");
    
    local final_lines = vim.api.nvim_buf_get_lines(modal.bufnr, 0, -1, false);
    local final_content = table.concat(final_lines, "\n");
    
    print("\n[TRUE E2E] Scraped Modal Content:\n" .. final_content .. "\n");

    assert.is_true(success, "True E2E timed out waiting for UI to update.");
    
    if final_content:match("<agent:error>") then
      error("API Error returned in UI: " .. final_content);
    end

    assert.match("Where's the beef", final_content, 1, true);
    
    -- Structural Integrity Check
    assert.match("<agent:system>", final_content, 1, true);
    assert.match("<agent:user>", final_content, 1, true);
    assert.match("<agent:content>", final_content, 1, true);
    assert.match("</agent:content>", final_content, 1, true);
    
    -- Negative check: ensure no mangled "disemvoweled" tags
    assert.is_nil(final_content:match("<ntsr>"), "Detected mangled tag <ntsr>");
    assert.is_nil(final_content:match("<nt:rr>"), "Detected mangled tag <nt:rr>");
  end);
end);
