-- demo_init.lua for AI plugin
local current_dir = vim.fn.fnamemodify(vim.fn.getcwd(), ":p");
vim.opt.runtimepath:prepend(current_dir);

-- Load AI with environment-aware config
require("nzi").setup({
  active_model = os.getenv("NZI_MODEL") or "deepseek",
  models = {
    -- Primary Model (Local)
    qwenzel = {
      provider = "ollama",
      model = "qwenzel:latest",
      api_base = os.getenv("NZI_TEST_LOCAL") or "http://192.168.1.17:11434/v1",
      api_key = "ollama",
      role_preference = "developer",
    },
    
    -- Standardized Aliases
    deepseek = {
      provider = "openrouter",
      model = "deepseek/deepseek-chat",
      api_base = "https://openrouter.ai/api/v1",
      api_key = vim.env.OPENROUTER_API_KEY,
      role_preference = "system",
    },

    -- Extra Demo Models
    min = { provider = "openrouter", model = "minimax/minimax-01", api_base = "https://openrouter.ai/api/v1", api_key = vim.env.OPENROUTER_API_KEY },
    ccp = { provider = "openrouter", model = "deepseek/deepseek-chat", api_base = "https://openrouter.ai/api/v1", api_key = vim.env.OPENROUTER_API_KEY },
    ds = { provider = "openrouter", model = "deepseek/deepseek-chat", api_base = "https://openrouter.ai/api/v1", api_key = vim.env.OPENROUTER_API_KEY },
    r1 = { provider = "openrouter", model = "deepseek/deepseek-r1", api_base = "https://openrouter.ai/api/v1", api_key = vim.env.OPENROUTER_API_KEY },
    opus = { provider = "openrouter", model = "anthropic/claude-3-opus", api_base = "https://openrouter.ai/api/v1", api_key = vim.env.OPENROUTER_API_KEY },
    o1 = { provider = "openrouter", model = "openai/o1-preview", api_base = "https://openrouter.ai/api/v1", api_key = vim.env.OPENROUTER_API_KEY },
    mistral = { provider = "openrouter", model = "mistralai/mistral-large-2411", api_base = "https://openrouter.ai/api/v1", api_key = vim.env.OPENROUTER_API_KEY },
    nova = { provider = "openrouter", model = "amazon/nova-pro-v1", api_base = "https://openrouter.ai/api/v1", api_key = vim.env.OPENROUTER_API_KEY },
    meta = { provider = "openrouter", model = "meta-llama/llama-3.3-70b-instruct", api_base = "https://openrouter.ai/api/v1", api_key = vim.env.OPENROUTER_API_KEY },
    search = { provider = "openrouter", model = "openai/gpt-4o-2024-11-20", api_base = "https://openrouter.ai/api/v1", api_key = vim.env.OPENROUTER_API_KEY },
  },
  modal = {
    show_context = true,
  },
  visuals = {
    enabled = true,
  }
});

-- SUGGESTED WORKFLOW MAPPINGS
-- Modal & Core
vim.keymap.set("n", "<leader>aa", ":AI/toggle<CR>", { desc = "AI: Toggle Modal" })
vim.keymap.set("n", "<leader>ax", ":AI/stop<CR>",   { desc = "AI: Abort Generation" })
vim.keymap.set("n", "<leader>ay", ":AI/yank<CR>",   { desc = "AI: Yank Last Response" })
vim.keymap.set("n", "<leader>ac", ":AI/clear<CR>",  { desc = "AI: Clear History" })
vim.keymap.set("n", "<leader>au", ":AI/undo<CR>",   { desc = "AI: Undo Last Turn" })

-- Interaction
vim.keymap.set("n", "<leader>a?", ":AI? ", { desc = "AI: Ask Question" })
vim.keymap.set("n", "<leader>a:", ":AI: ", { desc = "AI: Give Directive" })
vim.keymap.set("n", "<leader>a!", ":AI! ", { desc = "AI: Shell Command" })
vim.keymap.set("n", "<leader>a/", ":AI/",  { desc = "AI: Internal Command" })

-- Context Management
vim.keymap.set("n", "<leader>aA", ":AI/active<CR>", { desc = "AI: Set Buffer Active" })
vim.keymap.set("n", "<leader>aR", ":AI/read<CR>",   { desc = "AI: Set Buffer Read-only" })
vim.keymap.set("n", "<leader>aI", ":AI/ignore<CR>", { desc = "AI: Ignore Buffer" })
vim.keymap.set("n", "<leader>aS", ":AI/state<CR>",  { desc = "AI: View Buffer State" })
vim.keymap.set("n", "<leader>at", ":AI/tree<CR>",   { desc = "AI: Context Tree (Active/Read)" })
vim.keymap.set("n", "<leader>aT", ":AI/Tree<CR>",   { desc = "AI: Universe Tree (All Mapped)" })
vim.keymap.set("n", "<leader>ab", ":AI/buffers<CR>",{ desc = "AI: Buffer Context Manager" })

-- Navigation (Review Queue)
vim.keymap.set("n", "<leader>an", ":AI/next<CR>",   { desc = "AI: Next Pending Diff" })
vim.keymap.set("n", "<leader>ap", ":AI/prev<CR>",   { desc = "AI: Prev Pending Diff" })

-- Model Management
vim.keymap.set("n", "<leader>am", ":AI/model<CR>",  { desc = "AI: Model Menu" })
vim.keymap.set("n", "<leader>a1", ":AI/model deepseek<CR>", { desc = "AI: Switch to DeepSeek" })
vim.keymap.set("n", "<leader>a2", ":AI/model qwenzel<CR>",  { desc = "AI: Switch to Ollama" })

-- Statusline setup for demo
-- %{% ... %} is the magic syntax that tells Neovim to interpret 
-- the highlight tags returned by the Lua function.
vim.opt.statusline = "%f %m %r %= %{%v:lua.require('nzi.ui.visuals').get_statusline()%} %y %p%% %l:%c"

print("AI (nzi) Loaded! Use <leader>aa to toggle the AI Modal.");
print("Visual Context: Backgrounds reflect AI state (Green=Active, Orange=Read, Red=Ignore, Blue=Diff).");
print("Review Queue: Use <leader>an and <leader>ap to navigate pending changes.");
