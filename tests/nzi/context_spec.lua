local assert = require("luassert");
local context = require("nzi.context.context");

describe("AI context engine", function()
  it("should have default buffer state as active for named buffers", function()
    local bufnr = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_buf_set_name(bufnr, "named_file.lua");
    assert.are.equal("active", context.get_state(bufnr));
    vim.api.nvim_buf_delete(bufnr, { force = true });
  end);

  it("should allow setting and getting buffer state", function()
    context.set_state(10, "read");
    assert.are.equal("read", context.get_state(10));
    
    context.set_state(10, "ignore");
    assert.are.equal("ignore", context.get_state(10));
  end);

  it("should ignore buffers based on config filetypes", function()
    local bufnr = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_set_option_value("filetype", "NvimTree", { buf = bufnr });
    assert.is_false(context.is_real_buffer(bufnr));
    
    vim.api.nvim_set_option_value("filetype", "lua", { buf = bufnr });
    vim.api.nvim_buf_set_name(bufnr, "test.lua");
    assert.is_true(context.is_real_buffer(bufnr));
    vim.api.nvim_buf_delete(bufnr, { force = true });
  end);

  it("should ignore blank unnamed buffers but include empty named ones", function()
    local bufnr = vim.api.nvim_create_buf(true, false);
    -- No name: ignore
    assert.is_false(context.is_real_buffer(bufnr));
    
    -- Has name but empty content: INCLUDE (user created it for a reason)
    vim.api.nvim_buf_set_name(bufnr, "empty_file.lua");
    assert.is_true(context.is_real_buffer(bufnr));
    
    vim.api.nvim_buf_delete(bufnr, { force = true });
  end);

  it("should ignore buffers with special buftypes (UI elements)", function()
    local bufnr = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_buf_set_name(bufnr, "test.txt");
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = bufnr });
    assert.is_false(context.is_real_buffer(bufnr));
    vim.api.nvim_buf_delete(bufnr, { force = true });
  end);

  it("should not gather content from unlisted or invalid buffers", function()
    local bufnr = vim.api.nvim_create_buf(false, true); -- unlisted
    vim.api.nvim_set_option_value("swapfile", false, { buf = bufnr });
    vim.api.nvim_buf_set_name(bufnr, "unlisted.txt");
    
    local results = context.gather();
    local found = false;
    for _, item in ipairs(results) do
      if item.bufnr == bufnr then found = true; end
    end
    assert.is_false(found);
    vim.api.nvim_buf_delete(bufnr, { force = true });
  end);

  it("should ignore files based on git authority", function()
    local helper = require("tests.universe_helper");
    local root = helper.setup_test_repo();
    local old_cwd = vim.fn.getcwd();
    vim.cmd("cd " .. root);

    -- .env is in .gitignore in the test repo
    assert.is_true(context.is_git_ignored(".env"));
    assert.is_false(context.is_git_ignored("main.lua"));

    vim.cmd("cd " .. old_cwd);
    helper.teardown_test_repo(root);
  end);

  it("should gather content from loaded and non-ignored buffers", function()
    -- Create temporary buffers for testing
    local bufnr1 = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_set_option_value("swapfile", false, { buf = bufnr1 });
    vim.api.nvim_buf_set_lines(bufnr1, 0, -1, false, { "Hello World" });
    vim.api.nvim_buf_set_name(bufnr1, "test1.txt");
    
    local bufnr2 = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_set_option_value("swapfile", false, { buf = bufnr2 });
    vim.api.nvim_buf_set_lines(bufnr2, 0, -1, false, { "Ignored Content" });
    vim.api.nvim_buf_set_name(bufnr2, "test2.txt");
    context.set_state(bufnr2, "ignore");

    local results = context.gather();
    
    local found1 = false;
    local found2 = false;
    for _, item in ipairs(results) do
      if item.bufnr == bufnr1 then found1 = true; end
      if item.bufnr == bufnr2 then found2 = true; end
    end

    assert.is_true(found1);
    assert.is_false(found2);

    -- Cleanup
    vim.api.nvim_buf_delete(bufnr1, { force = true });
    vim.api.nvim_buf_delete(bufnr2, { force = true });
  end);
end);
