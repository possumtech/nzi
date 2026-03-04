local assert = require("luassert");
local nzi = require("nzi");
local job = require("nzi.job");

-- This test requires a local model to be running.
local run_local = os.getenv("NZI_TEST_LOCAL");

describe("nzi local model integration", function()
  if not run_local then
    pending("Skipping local LLM integration tests (NZI_TEST_LOCAL not set)");
    return;
  end

  before_each(function()
    require("nzi").setup({
      api_base = os.getenv("NZI_TEST_LOCAL"),
      default_model = os.getenv("NZI_DEFAULT_MODEL") or "qwenzel",
    });
  end);

  it("should handle an nzi? question end-to-end", function()
    local engine = require("nzi.engine");
    local modal = require("nzi.modal");
    
    local captured_text = "";
    local original_write = modal.write;
    modal.write = function(text, append)
      captured_text = captured_text .. text;
    end

    engine.handle_question("Say the word 'INTEGRATED'", false);

    -- 60s timeout for local models
    vim.wait(60000, function()
      return captured_text:upper():match("INTEGRATED") ~= nil
    end);

    assert.match("INTEGRATED", captured_text:upper());
    
    modal.write = original_write;
  end);

  it("should handle command-line directive end-to-end", function()
    local bufnr = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_set_current_buf(bufnr);
    
    local diff = require("nzi.diff");
    local diff_called = false;
    local original_open_diff = diff.open_diff;
    diff.open_diff = function(b, content)
      diff_called = true;
    end

    require("nzi.directive").run("Say only the word 'MODIFIED'", bufnr, false);

    -- 60s timeout for local models
    vim.wait(60000, function()
      return diff_called
    end);

    assert.is_true(diff_called, "Diff view was not opened. Model might be slow or errored.");

    diff.open_diff = original_open_diff;
    vim.api.nvim_buf_delete(bufnr, { force = true });
  end);
end);
