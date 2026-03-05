# AI (nzi)
Neovim-Native Agentic Interface

## The Living Document Workflow

Unlike traditional AI assistants that rely on ephemeral "stream-of-consciousness" chats, **AI (nzi)** is designed around a **Living Document** approach. 

The project's primary guidance comes from your **`AGENTS.md`** files. This system reorients your focus back to the code and the plan, rather than a separate chat log.

1.  **Global Directive (`~/AGENTS.md`):** This file contains your high-level personal preferences, architectural mandates, and global "rules of the road." It is injected into the **System Prompt** for every interaction.
2.  **Project Nervous System (`./AGENTS.md`):** This is the living state of your current project. It contains your plan, checklists, and architectural decisions. It is sent as `<agent:project_state>` in every user message.
3.  **Task Escalation (`next_task_suggest`):** The tool automatically identifies the **first unchecked checkbox** (`- [ ]`) in your project document and hoists it as `<agent:next_task_suggest>`. This provides the model with a clear "next step" suggestion without it being a strict command.

## Context Orchestration

AI (nzi) follows a strict **"Neovim is Context"** policy. The model's understanding of your project is derived directly from your open buffers and the Git-tracked universe.

*   **Discovery (`<model:grep />`, `<model:definition />`)**: The model can search the project universe or look up LSP definitions to find relevant files.
*   **Expansion (`<model:read />`)**: The model can pull a file from the "map" into active context. This creates a background buffer in Neovim, making it visible to the model.
*   **Contraction (`<model:drop />`)**: The model can "drop" a file back to the project map to reduce context noise.
    *   **Safety**: NZI will only "quietly close" a dropped buffer if it is **hidden** and **unmodified**. If you are currently viewing the file or have unsaved changes, the request is safely ignored.
*   **Persistence**: Manual changes you make to buffers (saving, closing, or switching states via `AI/read`) are immediately reflected in the model's next turn.

## Professional Features

### 1. Interpolation on Save
AI (nzi) automatically scans for directives when you save a buffer. If a line starts with `AI:`, `AI?`, `AI!`, or `AI/`, the tool will:
1. Extract the directive and its content.
2. Remove the line from your file.
3. Execute the action (Query, Shell, or Command) and report back.

This allows you to "type" your intentions directly into your code and have the agent clean them up as it works.

### 2. Visual Mode Selection
Select a block of code and press `:` or `:` to trigger an interaction.
*   **Precision Context**: Selection is automatically sent with coordinates, e.g., `### FOCUS SELECTION (file.lua:10-20)`. This gives the model exact anchors for surgical edits.
*   **Idiomatic**: Supports standard Neovim range commands. If no content is provided after `AI:`, the model defaults to "Analyze this."
*   **Contextual Queries**: Highlight a method and ask `AI? What is this parameter for?`—the model receives the code and the exact location.

### Workflow in Action

*   **Plan in Markdown:** You edit `AGENTS.md` to define tasks and project state.
*   **Execute in Code:** When you run an `AI:` directive, the model is automatically fed your global rules and the current state of your project.
*   **Collaborative Update:** The model is aware of your progress and can suggest updates to your checklists as it completes tasks.

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

-- Rapid Model Switching (Examples)
vim.keymap.set("n", "<leader>a1", ":AI/model deepseek<CR>", { desc = "AI: Switch to DeepSeek" })
vim.keymap.set("n", "<leader>a2", ":AI/model qwenzel<CR>",  { desc = "AI: Switch to Ollama" })
```

### 5. Visual Context (Statusline)

AI (nzi) provides high-signal indicators for your statusline to reflect the AI state of the current buffer. This provides immediate peripheral feedback about what the model can see.

Standard indicator colors:
*   **Deep Green**: [AI:A] Active (Target for edits).
*   **Deep Orange**: [AI:R] Read-only (Reference context).
*   **Crimson Red**: [AI:I] Ignored (Invisible to model).
*   **Royal Blue**: [AI:DIFF] Unresolved Agent Diff (Pending review).

#### Statusline Integration

You can add the colored AI state to your statusline using the native Lua API. This is the recommended "Spartan" way to see your context state:

```lua
-- Modern idiomatic integration (v:lua)
-- This syntax ensures colored blocks are correctly expanded
vim.opt.statusline:append("%{%v:lua.require('nzi.visuals').get_statusline()%}")

-- For plugin users (e.g. lualine.nvim)
-- We provide a data helper for structured integration
sections = {
  lualine_x = { 
    { 
      function() return require("nzi.visuals").get_status_data().text end,
      color = function() return { fg = require("nzi.visuals").get_status_data().color } end
    } 
  }
}
```

### 6. AGENTS.md

Your project state lives in `./AGENTS.md`. This is a collaborative, living document that provides a persistent and structured project management experience. Global rules are inherited from `~/AGENTS.md`.

## "Under the Hood" Transparency

AI (nzi) provides a sanitized but raw view of every interaction. The read-only modal window (`:AI/toggle`) uses a machine-friendly XML structure with real-time telemetry:

```xml
[ USER | model: deepseek | temp: 0.7 | top_p: 1.0 ]
<nzi:project_state>
## Project Checklist
- [x] Task 1
- [ ] Task 2
</nzi:project_state>

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
