local assert = require("luassert");
local ai = require("nzi");
local job = require("nzi.job");

-- This test requires a local model to be running.
local run_local = os.getenv("NZI_TEST_LOCAL");

describe("AI local model integration", function()
  if not run_local then
    pending("Skipping local LLM integration tests (NZI_TEST_LOCAL not set)");
    return;
  end

  before_each(function()
    require("nzi").setup({
      active_model = "local_model",
      models = {
        local_model = {
          api_base = os.getenv("NZI_TEST_LOCAL"),
          model = os.getenv("NZI_DEFAULT_MODEL") or "qwenzel:latest",
        }
      }
    });
    require("nzi.history").clear();
  end);

  it("should handle an ai? question end-to-end", function()
    local engine = require("nzi.engine");
    local modal = require("nzi.modal");
    
    local model_output = "";
    local original_write = modal.write;
    
    modal.write = function(text, type, _)
      if type == "model" then
        model_output = model_output .. text;
      end
    end

    engine.handle_question("Say only the word 'INTEGRATED'", false);

    -- 60s timeout for local models
    vim.wait(60000, function()
      return model_output:upper():match("INTEGRATED") ~= nil
    end);

    assert.match("INTEGRATED", model_output:upper());
    
    modal.write = original_write;
  end);

  it("should handle command-line directive end-to-end", function()
    local bufnr = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_set_current_buf(bufnr);
    
    local diff = require("nzi.diff");
    local diff_called = false;
    local original_open_diff = diff.open_diff;
    diff.open_diff = function(b, content)
      if content and content:upper():match("MODIFIED") then
        diff_called = true;
      end
    end

    require("nzi.directive").run("Say only the word 'MODIFIED'", bufnr, false);

    vim.wait(60000, function()
      return diff_called
    end);

    assert.is_true(diff_called, "Diff view was not opened with model content.");

    diff.open_diff = original_open_diff;
    vim.api.nvim_buf_delete(bufnr, { force = true });
  end);

  it("BATTLE TEST: should maintain state across a multi-turn conversation", function()
    local engine = require("nzi.engine");
    local history = require("nzi.history");
    local modal = require("nzi.modal");
    
    local model_output = "";
    local original_write = modal.write;
    
    local function setup_capture()
      model_output = "";
      modal.write = function(text, type, _)
        if type == "model" then model_output = model_output .. text end
      end
    end

    -- Turn 1: Establish a fact
    setup_capture();
    engine.handle_question("My favorite color is Crimson. Remember that.", false);
    
    -- Wait for history to show the turn is COMPLETE (Ollama can be slow)
    vim.wait(300000, function() 
      return #history.get_all() == 1 
    end);
    
    assert.are.equal(1, #history.get_all(), "Turn 1 was not added to history.");

    -- Turn 2: Query the fact
    setup_capture();
    engine.handle_question("What is my favorite color? Answer in one word.", false);
    
    vim.wait(300000, function() 
      return model_output:upper():match("CRIMSON") ~= nil 
    end);

    assert.match("CRIMSON", model_output:upper(), 1, true);
    
    modal.write = original_write;
  end);

  it("BATTLE TEST: should see and synthesize information from multiple buffers", function()
    local buf1 = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_buf_set_lines(buf1, 0, -1, false, { "SECRET_CODE_A = 1234" });
    vim.api.nvim_buf_set_name(buf1, "vault_a.txt");

    local buf2 = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_buf_set_lines(buf2, 0, -1, false, { "SECRET_CODE_B = 5678" });
    vim.api.nvim_buf_set_name(buf2, "vault_b.txt");

    local model_output = "";
    local modal = require("nzi.modal");
    local original_write = modal.write;
    modal.write = function(text, type, _)
      if type == "model" then model_output = model_output .. text end
    end

    require("nzi.engine").handle_question("What are the values of SECRET_CODE_A and SECRET_CODE_B?", false);

    vim.wait(120000, function()
      return model_output:match("1234") and model_output:match("5678")
    end);

    assert.match("1234", model_output);
    assert.match("5678", model_output);

    modal.write = original_write;
    vim.api.nvim_buf_delete(buf1, { force = true });
    vim.api.nvim_buf_delete(buf2, { force = true });
  end);
end);
