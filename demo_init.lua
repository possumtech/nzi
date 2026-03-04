-- Simple init for local development
local current_dir = vim.fn.getcwd();
vim.opt.runtimepath:append(current_dir);

-- Ensure plenary is available
local plenary_path = "/tmp/plenary.nvim";
if vim.fn.isdirectory(plenary_path) == 0 then
  vim.fn.system({ "git", "clone", "--depth", "1", "https://github.com/nvim-lua/plenary.nvim", plenary_path });
end
vim.opt.runtimepath:append(plenary_path);

-- Load nzi with environment-aware config
require("nzi").setup({
  default_model = os.getenv("NZI_DEFAULT_MODEL") or "gpt-4-turbo",
  api_base = os.getenv("NZI_TEST_LOCAL"),
});

-- QoL Mapping
vim.keymap.set("n", "<leader>a", ":NziToggle<CR>", { silent = true });

print("nzi Loaded! Use <leader>a to toggle the Model Stream.");
