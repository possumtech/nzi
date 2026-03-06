# AI (nzi)
### Neovim-Native Agentic Interface

**AI (nzi)** is a lean, high-performance agentic interface for Neovim. It moves the assistant out of a separate chat window and directly into your source code and your workflow. 

Unlike assistants that treat your project as a static "context dump," **nzi** treats Neovim as the living nervous system of your project. What you see is what the model gets.

---

## The Four Horsemen (Interaction Modes)

NZI provides four distinct ways to interact with the model, triggered directly from the command line or as interpolated comments in your code.

### 1. `AI:` Directive (Modification)
Used for modifying code or performing project tasks.
*   **CLI**: `:AI: Refactor this function to be more recursive`
*   **In-Code**: `AI: Add a docstring here`
*   **Visual**: Select a block and press `:` — the model receives the exact range and coordinates.

### 2. `AI?` Question (Inquiry)
Used for analysis, explanation, or general knowledge.
*   **CLI**: `:AI? What is the architecture of this module?`
*   **In-Code**: `AI? Why is this variable being shadowed here?`
*   **Outcome**: Response appears in the Modal UI without touching your source code.

### 3. `AI!` Shell (Action)
Used for executing terminal commands and capturing output.
*   **CLI**: `:AI! git log -n 5`
*   **In-Code**: `AI! ls -la` — The output is injected directly into your buffer below the command.

### 4. `AI/` Internal (Control)
Used for managing the agent's state, model selection, and context.
*   `:AI/model deepseek` — Switch the active model alias.
*   `:AI/active`, `:AI/read`, `:AI/ignore` — Explicitly manage buffer context states.
*   `:AI/yolo` — Toggle Autopilot mode (skips tool execution confirmations).

---

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "possumtech/nzi",
  dependencies = {
    "nvim-lua/plenary.nvim",   -- Core utilities
  },
  config = function()
    require("nzi").setup({
      -- Path to python with litellm installed
      python_cmd = { "python3" } 
    })
  end,
}
```

### Dependency Setup
NZI uses a lightweight Python bridge with `litellm` to support 100+ providers.

```bash
cd ~/.local/share/nvim/lazy/nzi/  
python3 -m venv .venv
.venv/bin/python -m pip install litellm
```

---

## The Living Document Workflow

The project's primary guidance comes from your **`AGENTS.md`** files. This reorients your focus back to the code and the plan, rather than a separate chat log.

1.  **Global Directive (`~/AGENTS.md`):** Your personal "rules of the road." Injected into every System Prompt.
2.  **Project Nervous System (`./AGENTS.md`):** The living state of your project. Sent as `<agent:project_state>` in every turn.
3.  **Task Escalation:** NZI automatically identifies the **first unchecked checkbox** (`- [ ]`) in your project document and hoists it as `<agent:next_task_suggest>`. The agent always knows the current priority.

---

## Professional Features

### Interpolation on Save
Type your intention directly into your source:
`AI? Explain this regex`
When you **save the file**, the line vanishes, and the agent executes the request. It’s "Ghost Writing" for your codebase.

### Precision Visual Context
Select a method and ask `AI? What is this parameter for?`. The model receives a structured `<agent:selection>` tag:
`<agent:selection file="src/main.lua" start="10:5" end="12:20" mode="ask">...</agent:selection>`
*   **file**: The relative file path.
*   **start/end**: Exact `line:col` coordinates.
*   **mode**: Interaction intent (`ask` or `edit`).
*   **content**: The raw text of your selection.

### Context Orchestration
AI (nzi) follows a strict **"Neovim is Context"** policy.
*   **Discovery**: The model can use `<model:grep />` or `<model:definition />` (LSP) to find files.
*   **Expansion**: The model can use `<model:read />` to pull "mapped" files into active context.
*   **Contraction**: The model can `<model:drop />` files to reduce noise (safely ignores modified/visible buffers).

---

## The Agentic Contract (Technical Specs)

### Context Visibility Hierarchy

| File Type | Not Open (Passive) | Open in Buffer (Intent) |
| :--- | :--- | :--- |
| **Tracked/Staged** | **Visible** (Map/Skeleton) | **Visible** (Active/Read) |
| **Untracked** | **Hidden** | **Visible** (Active/Read) |
| **Git-Ignored** | **Hidden** | **Hidden** (Default `ignore`) |

*   **Git Authority**: Files in `.gitignore` are **invisible** by default, preventing secret leakage.
*   **User Overrides**: Commands like `:AI/active` always take absolute precedence over Git.

### Statusline Indicators
NZI provides high-signal color-coded status indicators:
*   **[AI:A]** Active (Focus for edits).
*   **[AI:R]** Read-only (Context only).
*   **[AI:I]** Ignored (Invisible).
*   **[AI:REV]** Pending Review (Surgical edit awaiting approval).

---
*Sanitized. Structured. Agentic.*
