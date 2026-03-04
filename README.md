# AI (nzi)
Neovim-Native Agentic Interface

## The Anti-Agent

AI (nzi) is built on the philosophy that stream-of-consciousness conversations are an anti-pattern in software development. They distract focus and bury important project information in rambling logs. With AI, your interaction is structured, surgical, and fully integrated into your Neovim environment.

### 1. Code Interpolation

Interact with the model directly inside your source files using prefixed comments:

*   `ai: refactor this` — Treated as a code directive (currently routed to question handler).
*   `ai? explain this` — Ask a specific question about the surrounding code.
*   `ai! git log` — Execute a shell command and inject the output below the directive.
*   `ai/model coder` — Send an internal command (e.g., switch models).

### 2. Status Line Commands

The `:AI` command is your primary interface. It mirrors interpolated commands but is used from the command line for general inquiries or whole-file operations.

*   `:AI? what is this project doing?`
*   `:AI! ls -la` (Automatically expands to `:AI !` for shell injection)
*   `:AI/model gpro` (Switch to a specific model alias)

### 3. AGENTS.md & .ai.md

Your project state lives in `AGENTS.md`. This is a collaborative, living document that provides a persistent and structured project management experience. AI (nzi) also inherits rules from `~/AGENTS.md` (global) and `.ai.md` (project-specific).

## "Under the Hood" Transparency

AI (nzi) provides a sanitized but raw view of every interaction. The read-only modal window (`:AI/toggle`) uses a machine-friendly XML structure with real-time telemetry:

```xml
[ USER | model: coder | temp: 0.7 | top_p: 1.0 ]
<nzi:user>
What is the purpose of this module?
</nzi:user>

[ ASSISTANT | reasoning_content | stream: active ]
<nzi:reasoning_content>
The user is asking about the module's intent...
</nzi:reasoning_content>

[ ASSISTANT | content | stream: active ]
<nzi:content>
This module handles the core UI and structural integrity...
</nzi:content>
```

## Pure Lua Architecture

AI (nzi) is a lean, dependency-free plugin. It uses native `curl` and `vim.system` to communicate with any OpenAI-compatible API (Ollama, OpenRouter, etc.). No Python or LiteLLM required.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "your-username/nzi",
  dependencies = {
    "nvim-lua/plenary.nvim",   -- Core async/test utilities
    "tpope/vim-fugitive",     -- Highly recommended for diff workflows
  },
  config = function()
    require("nzi").setup({
      active_model = "coder",
      models = {
        coder = {
          model = "qwen/qwen-2.5-coder-32b-instruct",
          api_base = "https://openrouter.ai/api/v1",
          api_key = vim.env.OPENROUTER_API_KEY,
        },
        qwenzel = {
          model = "qwenzel:latest",
          api_base = "http://localhost:11434/v1",
          api_key = "ollama",
        }
      }
    })
  end,
}
```

## Recommended Keymaps

```lua
-- Normal Mode
vim.keymap.set("n", "<leader>ai", ":AI<CR>", { desc = "AI: Execute" })
vim.keymap.set("n", "<leader>at", ":AI/toggle<CR>", { desc = "AI: Toggle Modal" })
vim.keymap.set("n", "<leader>ab", ":AI/buffers<CR>", { desc = "AI: Manage Context" })
vim.keymap.set("n", "<leader>ac", ":AI/clear<CR>", { desc = "AI: Clear History" })

-- Visual Mode
vim.keymap.set("v", "<leader>ai", ":AI<CR>", { desc = "AI: Run on Selection" })
```

## Prerequisites

- **Neovim 0.10+** (Required for `vim.system`)
- **curl**: Required for API communication.

---
*Sanitized. Structured. Agentic.*
