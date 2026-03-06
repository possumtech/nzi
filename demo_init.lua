-- demo_init.lua
-- Minimal Neovim configuration for demonstrating/testing nzi

-- Add current directory to runtimepath to find the nzi plugin
local current_dir = vim.fn.fnamemodify(vim.fn.getcwd(), ":p")
vim.opt.runtimepath:prepend(current_dir)

-- Setup NZI with extensive model aliases for experimentation
require("nzi").setup({
  -- Default model
  active_model = os.getenv("NZI_MODEL") or "deepseek",

  -- Pre-configured experimentation lab
  models = {
    -- The core 'deepseek' model is already in the plugin defaults.
    
    -- Local Qwen (Ollama)
    qwenzel = { 
      provider = "ollama", 
      model = "qwen2.5-coder:14b", 
      api_base = os.getenv("NZI_TEST_LOCAL") or "http://localhost:11434/v1",
      role_preference = "developer"
    },
    
    -- OpenRouter Convenience Aliases
    min = { provider = "openrouter", model = "minimax/minimax-01", api_base = "https://openrouter.ai/api/v1", api_key = vim.env.OPENROUTER_API_KEY },
    r1 = { provider = "openrouter", model = "deepseek/deepseek-r1", api_base = "https://openrouter.ai/api/v1", api_key = vim.env.OPENROUTER_API_KEY },
    opus = { provider = "openrouter", model = "anthropic/claude-3-opus", api_base = "https://openrouter.ai/api/v1", api_key = vim.env.OPENROUTER_API_KEY },
    o1 = { provider = "openrouter", model = "openai/o1-preview", api_base = "https://openrouter.ai/api/v1", api_key = vim.env.OPENROUTER_API_KEY },
  },

  modal = {
    show_context = true,
  },
  visuals = {
    enabled = true,
    bold = true
  }
})

-- SUGGESTED WORKFLOW MAPPINGS
-- Modal & Core
vim.keymap.set("n", "<leader>aa", ":AI/toggle<CR>", { desc = "AI: Toggle Modal" })
vim.keymap.set("n", "<leader>ax", ":AI/stop<CR>",   { desc = "AI: Stop Generation" })
vim.keymap.set("n", "<leader>ay", ":AI/yank<CR>",   { desc = "AI: Yank Last Response" })
vim.keymap.set("n", "<leader>ac", ":AI/clear<CR>",  { desc = "AI: Clear History" })
vim.keymap.set("n", "<leader>au", ":AI/undo<CR>",   { desc = "AI: Undo Last Turn" })

-- Interaction
vim.keymap.set("n", "<leader>a?", ":AI? ", { desc = "AI: Ask Question" })
vim.keymap.set("n", "<leader>a:", ":AI: ", { desc = "AI: Instruct" })
vim.keymap.set("n", "<leader>a!", ":AI! ", { desc = "AI: Run Shell" })
vim.keymap.set("n", "<leader>a/", ":AI/",  { desc = "AI: Internal" })

-- Context Management
vim.keymap.set("n", "<leader>aA", ":AI/active<CR>", { desc = "AI: Set Buffer Active" })
vim.keymap.set("n", "<leader>aR", ":AI/read<CR>",   { desc = "AI: Set Buffer Read-only" })
vim.keymap.set("n", "<leader>aI", ":AI/ignore<CR>", { desc = "AI: Ignore Buffer" })
vim.keymap.set("n", "<leader>aS", ":AI/state<CR>",  { desc = "AI: View Buffer State" })
vim.keymap.set("n", "<leader>at", ":AI/tree<CR>",   { desc = "AI: Context Tree (Active/Read)" })
vim.keymap.set("n", "<leader>aT", ":AI/Tree<CR>",   { desc = "AI: Universe Tree (All Mapped)" })
vim.keymap.set("n", "<leader>ab", ":AI/buffers<CR>",{ desc = "AI: Buffer Context Manager" })

-- Navigation (Diff Queue)
vim.keymap.set("n", "<leader>an", ":AI/next<CR>",   { desc = "AI: Next Pending Diff" })
vim.keymap.set("n", "<leader>ap", ":AI/prev<CR>",   { desc = "AI: Prev Pending Diff" })

-- Model Management
vim.keymap.set("n", "<leader>am", ":AI/model<CR>",  { desc = "AI: Model Menu" })
vim.keymap.set("n", "<leader>a1", ":AI/model deepseek<CR>", { desc = "AI: Switch to DeepSeek" })
vim.keymap.set("n", "<leader>a2", ":AI/model qwenzel<CR>",  { desc = "AI: Switch to Ollama" })

-- Statusline setup for demo
vim.opt.statusline = "%f %m %r %= %{%v:lua.require('nzi.ui.visuals').get_statusline()%} %y %p%% %l:%c"

print("AI (nzi) Loaded! Use <leader>aa to toggle the AI Modal.");
print("Visual Context: Backgrounds reflect AI state (Green=Active, Orange=Read, Red=Ignore, Blue=Diff).");
print("Diff Queue: Use <leader>an and <leader>ap to navigate pending changes.");
