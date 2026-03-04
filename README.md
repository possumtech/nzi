# AI (nzi)
Neovim-Native Agentic Interface

## The Anti-Agent

AI (nzi) is built on the philosophy that stream-of-consciousness conversations are an anti-pattern in software development. They distract focus and bury important project information in rambling logs. With AI, your interaction is structured, surgical, and fully integrated into your Neovim environment.

### 1. Code Interpolation

Interact with the model directly inside your source files using prefixed comments:

*   `AI: refactor this` — Treated as a code directive (currently routed to question handler).
*   `AI? explain this` — Ask a specific question about the surrounding code.
*   `AI! git log` — Execute a shell command and inject the output below the directive.
*   `AI/model deepseek` — Send an internal command (e.g., switch models).

### 2. Status Line Commands

The `:AI` command is your primary interface. It mirrors interpolated commands but is used from the command line for general inquiries or whole-file operations.

*   `:AI? what is this project doing?`
*   `:AI! ls -la` (Automatically expands to `:AI !` for shell injection)
*   `:AI/model gpro` (Switch to a specific model alias)

### 3. Context Visibility Policy

AI (nzi) follows a strict, predictable hierarchy for determine what information is sent to the model. It prioritizes project security and explicit user intent.

| File Type | Not Open (Passive) | Open in Buffer (Intent) |
| :--- | :--- | :--- |
| **Tracked/Staged** | **Visible** (Map/Skeleton) | **Visible** (Active/Read) |
| **Untracked** (e.g. `.swp`) | **Hidden** | **Visible** (Active/Read) |
| **Git-Ignored** (e.g. `.env`) | **Hidden** | **Hidden** (Default `ignore`) |

*   **Git Authority**: If a file is in `.gitignore`, the model **cannot see it** by default, even if the buffer is open. This prevents accidental leakage of secrets.
*   **Passive Privacy**: Files not yet known to Git (untracked) are never included in the project map. They only enter the context if you explicitly open them.
*   **User Overrides**: User commands (`:AI/active`, `:AI/read`, `:AI/ignore`) **always** take absolute precedence over Git. You have the ultimate power to "light up" or "darken" any file.
*   **Empty Files**: Named empty files are included (as targets for new code), while unnamed startup/scratch buffers are aggressively ignored.

### 4. Suggested Mappings

Add these to your `init.lua` for a high-speed keyboard-driven workflow:

```lua
-- Modal & Core
vim.keymap.set("n", "<leader>aa", ":AI/toggle<CR>", { desc = "AI: Toggle Modal" })
vim.keymap.set("n", "<leader>ax", ":AI/stop<CR>",   { desc = "AI: Abort Generation" })
vim.keymap.set("n", "<leader>ay", ":AI/yank<CR>",   { desc = "AI: Yank Last Response" })
vim.keymap.set("n", "<leader>ac", ":AI/clear<CR>",  { desc = "AI: Clear History" })
vim.keymap.set("n", "<leader>au", ":AI/undo<CR>",   { desc = "AI: Undo Last Turn" })

-- Context Management
vim.keymap.set("n", "<leader>aA", ":AI/active<CR>", { desc = "AI: Set Buffer Active" })
vim.keymap.set("n", "<leader>aR", ":AI/read<CR>",   { desc = "AI: Set Buffer Read-only" })
vim.keymap.set("n", "<leader>aI", ":AI/ignore<CR>", { desc = "AI: Ignore Buffer" })
vim.keymap.set("n", "<leader>aS", ":AI/state<CR>",  { desc = "AI: View Buffer State" })
vim.keymap.set("n", "<leader>at", ":AI/tree<CR>",   { desc = "AI: Context Tree (Active/Read)" })
vim.keymap.set("n", "<leader>aT", ":AI/Tree<CR>",   { desc = "AI: Universe Tree (All Mapped)" })
vim.keymap.set("n", "<leader>ab", ":AI/buffers<CR>",{ desc = "AI: Buffer List UI" })

-- Model Management
vim.keymap.set("n", "<leader>am", ":AI/model<CR>",  { desc = "AI: Model Menu" })

-- Rapid Model Switching (Examples)
-- Map <leader>a + Number to your preferred aliases
vim.keymap.set("n", "<leader>a1", ":AI/model deepseek<CR>", { desc = "AI: Switch to DeepSeek" })
vim.keymap.set("n", "<leader>a2", ":AI/model qwenzel<CR>",  { desc = "AI: Switch to Ollama" })
```

### 4. AGENTS.md & .ai.md

Your project state lives in `AGENTS.md`. This is a collaborative, living document that provides a persistent and structured project management experience. AI (nzi) also inherits rules from `~/AGENTS.md` (global) and `.ai.md` (project-specific).

## "Under the Hood" Transparency

AI (nzi) provides a sanitized but raw view of every interaction. The read-only modal window (`:AI/toggle`) uses a machine-friendly XML structure with real-time telemetry:

```xml
[ USER | model: deepseek | temp: 0.7 | top_p: 1.0 ]
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

## Lightweight Python/LiteLLM Bridge

AI (nzi) is a lean plugin that leverages a high-performance Python bridge with `litellm`. This allows it to communicate with 100+ LLM providers (OpenAI, Anthropic, Ollama, OpenRouter, etc.) while keeping the Lua side focused on Neovim integration.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "possumtech/nzi",
  dependencies = {
    "nvim-lua/plenary.nvim",   -- Core async/test utilities
    "tpope/vim-fugitive",      -- Recommended for diff workflows
  },
  config = function()
    require("nzi").setup({
      -- Path to python with litellm installed
      -- python_cmd = { "python3" } 
    })
  end,
}
```

### Python Setup

It is highly recommended to use a dedicated virtual environment:

```bash
cd ~/.local/share/nvim/lazy/nzi/  # Or your plugin path
python3 -m venv .venv
.venv/bin/python -m pip install litellm
```

Then configure `nzi` in your init.lua:

```lua
require("nzi").setup({
  python_cmd = { vim.fn.expand("~/.local/share/nvim/lazy/nzi/.venv/bin/python") }
})
```

## Prerequisites

- **Neovim 0.10+** (Required for `vim.system`)
- **curl**: Required for basic communication.
- **Python 3.10+** and **LiteLLM**: Required for the advanced bridge.

---
*Sanitized. Structured. Agentic.*
