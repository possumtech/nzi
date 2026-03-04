-- Simple init for local development
local current_dir = vim.fn.getcwd();
vim.opt.runtimepath:append(current_dir);

-- Ensure plenary is available (reusing the test path)
local plenary_path = "/tmp/plenary.nvim";
if vim.fn.isdirectory(plenary_path) == 0 then
  print("Cloning plenary.nvim for demo...");
  vim.fn.system({ "git", "clone", "--depth", "1", "https://github.com/nvim-lua/plenary.nvim", plenary_path });
end
vim.opt.runtimepath:append(plenary_path);

-- Optional: Add fugitive if you have it installed locally
-- vim.opt.runtimepath:append("path/to/vim-fugitive")

-- Load nzi
require("nzi").setup({
  default_model = "gpt-4-turbo", -- Change to your preferred model
});

print("nzi Loaded! Try typing 'nzi! ls' and running :Nzi");
