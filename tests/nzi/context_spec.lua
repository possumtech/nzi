local assert = require("luassert");
local context = require("nzi.context");

describe("nzi context engine", function()
  it("should have default buffer state as active", function()
    assert.are.equal("active", context.get_state(1));
  end);

  it("should allow setting and getting buffer state", function()
    context.set_state(10, "read");
    assert.are.equal("read", context.get_state(10));
    
    context.set_state(10, "ignore");
    assert.are.equal("ignore", context.get_state(10));
  end);

  it("should ignore buffers based on config filetypes", function()
    assert.is_true(context.should_ignore("anyname", "NvimTree"));
    assert.is_false(context.should_ignore("anyname", "lua"));
  end);

  it("should ignore buffers based on config names", function()
    assert.is_true(context.should_ignore(".git/config", "gitconfig"));
    assert.is_true(context.should_ignore("node_modules/pkg/index.js", "javascript"));
    assert.is_false(context.should_ignore("src/main.lua", "lua"));
  end);

  it("should not gather content from unlisted or invalid buffers", function()
    local bufnr = vim.api.nvim_create_buf(false, true); -- unlisted
    vim.api.nvim_buf_set_name(bufnr, "unlisted.txt");
    
    local results = context.gather();
    local found = false;
    for _, item in ipairs(results) do
      if item.bufnr == bufnr then found = true; end
    end
    assert.is_false(found);
    vim.api.nvim_buf_delete(bufnr, { force = true });
  end);

  it("should gather content from loaded and non-ignored buffers", function()
    -- Create temporary buffers for testing
    local bufnr1 = vim.api.nvim_create_buf(true, false);
    vim.api.nvim_buf_set_lines(bufnr1, 0, -1, false, { "Hello World" });
    vim.api.nvim_buf_set_name(bufnr1, "test1.txt");
    
    local bufnr2 = vim.api.nvim_create_buf(true, false);
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
