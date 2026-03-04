local assert = require("luassert");
local ai = require("nzi");
local job = require("nzi.job");

-- This test requires a local model to be running.
local run_local = os.getenv("NZI_TEST_LOCAL");

describe("AI local model integration", function()
  -- These tests use the active model alias configured in the environment
  local config = require("nzi.config");
  local model_alias = config.options.active_model;

  if model_alias ~= "local_coder" then
    pending("Skipping integration tests (NZI_MODEL not set to local_coder)");
    return;
  end

  local created_buffers = {};

  before_each(function()
    require("nzi.history").clear();
    created_buffers = {};
  end);

  after_each(function()
    for _, bufnr in ipairs(created_buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true });
      end
    end
  end);

  local function create_test_buf(name, lines)
    local bufnr = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines);
    vim.api.nvim_buf_set_name(bufnr, vim.fn.getcwd() .. "/" .. name);
    vim.api.nvim_set_option_value("buflisted", true, { buf = bufnr });
    table.insert(created_buffers, bufnr);
    return bufnr;
  end

  it("should handle an ai? question end-to-end", function()
    local engine = require("nzi.engine");
    local modal = require("nzi.modal");
    
    local model_output = "";
    local original_write = modal.write;
    
    modal.write = function(text, type, _)
      if type == "content" or type == "response" then
        model_output = model_output .. text;
      end
    end

    engine.handle_question("Say only the word 'INTEGRATED'", false);

    vim.wait(30000, function()
      return model_output:upper():match("INTEGRATED") ~= nil
    end);

    modal.write = original_write;
    assert.match("INTEGRATED", model_output:upper());
  end);

  it("should handle command-line directive end-to-end", function()
    local bufnr = create_test_buf("directive_test.lua", { "-- Empty file" });
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

    vim.wait(30000, function()
      return diff_called
    end);

    diff.open_diff = original_open_diff;
    assert.is_true(diff_called, "Diff view was not opened with model content.");
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
        if type == "content" or type == "response" then model_output = model_output .. text end
      end
    end

    -- Turn 1: Establish a fact
    setup_capture();
    engine.handle_question("My favorite color is Crimson. Remember that.", false);
    
    vim.wait(30000, function() 
      return #history.get_all() == 1 
    end);
    
    assert.are.equal(1, #history.get_all(), "Turn 1 was not added to history.");

    -- Turn 2: Query the fact
    setup_capture();
    engine.handle_question("What is my favorite color? Answer in one word.", false);
    
    vim.wait(30000, function() 
      return model_output:upper():match("CRIMSON") ~= nil 
    end);

    modal.write = original_write;
    assert.match("CRIMSON", model_output:upper(), 1, true);
  end);

  it("BATTLE TEST: should see and synthesize information from multiple buffers", function()
    create_test_buf("vault_a.txt", { "SECRET_CODE_A = 1234" });
    create_test_buf("vault_b.txt", { "SECRET_CODE_B = 5678" });

    local model_output = "";
    local modal = require("nzi.modal");
    local original_write = modal.write;
    modal.write = function(text, type, _)
      if type == "content" or type == "response" then 
        model_output = model_output .. text 
      end
    end

    require("nzi.engine").handle_question("What are the values of SECRET_CODE_A and SECRET_CODE_B? Answer with the codes.", false);

    local success = vim.wait(30000, function()
      return model_output:match("1234") and model_output:match("5678")
    end);

    modal.write = original_write;
    
    if not success then
      error("Synthesis test timed out. Model output: " .. model_output)
    end

    assert.match("1234", model_output);
    assert.match("5678", model_output);
  end);
end);
