-- demo_init.lua for AI plugin
local current_dir = vim.fn.getcwd();
vim.opt.runtimepath:append(current_dir);

-- Load AI with environment-aware config
require("nzi").setup({
  active_model = "coder",
  models = {
    -- Primary Model (Local)
    qwenzel = {
      model = "qwenzel:latest",
      api_base = os.getenv("NZI_TEST_LOCAL") or "http://192.168.1.17:11434/v1",
      api_key = "ollama",
    },
    
    -- OpenRouter Aliases (Standardized)
    min = { model = "minimax/minimax-01", api_base = "https://openrouter.ai/api/v1", api_key = vim.env.OPENROUTER_API_KEY },
    ccp = { model = "deepseek/deepseek-chat", api_base = "https://openrouter.ai/api/v1", api_key = vim.env.OPENROUTER_API_KEY },
    ds = { model = "deepseek/deepseek-chat", api_base = "https://openrouter.ai/api/v1", api_key = vim.env.OPENROUTER_API_KEY },
    r1 = { model = "deepseek/deepseek-r1", api_base = "https://openrouter.ai/api/v1", api_key = vim.env.OPENROUTER_API_KEY },
    opus = { model = "anthropic/claude-3-opus", api_base = "https://openrouter.ai/api/v1", api_key = vim.env.OPENROUTER_API_KEY },
    o1 = { model = "openai/o1-preview", api_base = "https://openrouter.ai/api/v1", api_key = vim.env.OPENROUTER_API_KEY },
    coder = { model = "qwen/qwen-2.5-coder-32b-instruct", api_base = "https://openrouter.ai/api/v1", api_key = vim.env.OPENROUTER_API_KEY },
    mistral = { model = "mistralai/mistral-large-2411", api_base = "https://openrouter.ai/api/v1", api_key = vim.env.OPENROUTER_API_KEY },
    nova = { model = "amazon/nova-pro-v1", api_base = "https://openrouter.ai/api/v1", api_key = vim.env.OPENROUTER_API_KEY },
    meta = { model = "meta-llama/llama-3.3-70b-instruct", api_base = "https://openrouter.ai/api/v1", api_key = vim.env.OPENROUTER_API_KEY },
    search = { model = "openai/gpt-4o-2024-11-20", api_base = "https://openrouter.ai/api/v1", api_key = vim.env.OPENROUTER_API_KEY },
  },
  modal = {
    show_context = true,
  }
});

-- Keybindings for demo
vim.keymap.set("n", "<leader>a", ":AI/toggle<CR>", { silent = true });
vim.keymap.set("n", "<leader>c", ":AI/clear<CR>", { silent = true });
vim.keymap.set("n", "<leader>s", ":AI/status<CR>", { silent = true });

print("AI (nzi) Loaded! Use <leader>a to toggle the Model Stream.");
print("Context filtered: Blank and unsaved buffers are now ignored.");
print("Providers standardized: Using Ollama and OpenRouter for all models.");
