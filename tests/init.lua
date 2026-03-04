-- Initialize test environment
local current_dir = vim.fn.fnamemodify(vim.fn.getcwd(), ":p");

-- Add nzi to runtimepath (absolute path)
vim.opt.runtimepath:prepend(current_dir);

-- Ensure plenary is available for tests
local plenary_path = "/tmp/plenary.nvim";
if vim.fn.isdirectory(plenary_path) == 0 then
  print("Cloning plenary.nvim for tests...");
  vim.fn.system({
    "git",
    "clone",
    "--depth",
    "1",
    "https://github.com/nvim-lua/plenary.nvim",
    plenary_path,
  });
end
vim.opt.runtimepath:append(plenary_path);

-- Load the plugin
require("nzi").setup();
