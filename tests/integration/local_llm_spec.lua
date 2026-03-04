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

  it("BATTLE TEST: should maintain state across a multi-turn conversation", function()
    local engine = require("nzi.engine");
    local history = require("nzi.history");
    history.clear();

    local captured = "";
    local modal = require("nzi.modal");
    local original_write = modal.write;
    modal.write = function(text, append) captured = captured .. text end

    -- Turn 1: Establish a fact
    engine.handle_question("My favorite color is Crimson. Remember that.", false);
    
    -- Wait for history to be populated (this confirms turn 1 is fully finished and scheduled)
    vim.wait(30000, function() 
      return #history.get_all() == 1 
    end);
    
    assert.are.equal(1, #history.get_all(), "Turn 1 was not added to history.");

    -- Turn 2: Query the fact
    captured = "";
    engine.handle_question("What is my favorite color? Answer in one word.", false);
    
    vim.wait(30000, function() 
      return captured:upper():match("CRIMSON") ~= nil 
    end);

    assert.match("CRIMSON", captured:upper(), 1, true);
    
    modal.write = original_write;
  end);

  it("BATTLE TEST: should see and synthesize information from multiple buffers", function()
    -- Create two distinct buffers
    local buf1 = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_buf_set_lines(buf1, 0, -1, false, { "SECRET_CODE_A = 1234" });
    vim.api.nvim_buf_set_name(buf1, "vault_a.txt");

    local buf2 = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_buf_set_lines(buf2, 0, -1, false, { "SECRET_CODE_B = 5678" });
    vim.api.nvim_buf_set_name(buf2, "vault_b.txt");

    local captured = "";
    local modal = require("nzi.modal");
    local original_write = modal.write;
    modal.write = function(text, append) captured = captured .. text end

    require("nzi.engine").handle_question("What are the values of SECRET_CODE_A and SECRET_CODE_B?", false);

    vim.wait(20000, function()
      return captured:match("1234") and captured:match("5678")
    end);

    assert.match("1234", captured);
    assert.match("5678", captured);

    modal.write = original_write;
    vim.api.nvim_buf_delete(buf1, { force = true });
    vim.api.nvim_buf_delete(buf2, { force = true });
  end);
end);
