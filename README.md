# AI (nzi)
Neovim-Native Agentic Interface

## The Anti-Agent

AI (nzi) is built on the philosophy that stream-of-consciousness conversations are an anti-pattern in software development. They distract focus and bury important project information in rambling logs. With AI, your interaction is structured, surgical, and fully integrated into your Neovim environment.

### 1. Code Interpolation

Interact with the model directly inside your source files using prefixed comments:

*   `ai: refactor this` — Treated as a code directive (currently routed to question handler).
*   `ai? explain this` — Ask a specific question about the surrounding code.
*   `ai! git log` — Execute a shell command and inject the output below the directive.
*   `ai/model deepseek` — Send an internal command (e.g., switch models).

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
