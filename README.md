# NZI: Agentic Zone Integration

**NZI** is about integrating your agent into the "zone" of your project. It is an optimization of the most finite resource in software engineering: **your attention.**

By baking the agent directly into Neovim and calibrating it toward spec-driven development, you regain the context, control, and focus that are traditionally lost in the noise of a chat window.

### Neovim is the Nervous System
In NZI, Neovim isn't just an editor; it's the living nervous system of your project. What you see is what the agent gets. Instead of treating your project as a static context dump, NZI leverages **Interpolated Intelligence**—source-native interaction modes (`AI:`, `AI?`, `AI!`) that center communication on your code and its evolving documentation.

### Spec-Driven, Not Stream-of-Consciousness
The core of NZI is the `AGENTS.md` file. This is the living brain of your project. The agent performs a factual sweep of your roadmap and technical specs at the start of every turn, ensuring it remains aligned with your goals without the need for constant natural-language hand-holding. You stop yapping with a chatbot and start directing a high-performance agent through a living spec.

### Immersion Over "The Easy Button"
We don't believe in the "easy button" that generates slop in the dark. In NZI, every change is a **vimdiff**. You review modifications using familiar keyboard shortcuts, remaining fully immersed in the syntax and logic of your codebase. 

There's a **"yolo" mode** to trust your agent (`\aY`), but we're confident that you'll agree that shuffling through and rapidly approving the changes will help you remain in control of your codebase without losing the power of modern LLM technology.

### Lean, Free, and Customizable
Unlike competing agents, NZI maintains an especially lean system prompt. We don't bake our own "clever theories" about engineering into the agent. Instead, we provide the structure and the tools, inviting you to bake your own philosophies into the global `AGENTS.md` document. No model lock-in. No chat-window clutter. Just surgical precision.

---

## Quick Start

1.  **Requirement**: A Python environment with `pip install litellm`.
2.  **Environment**: Set `OPENROUTER_API_KEY` (or your preferred provider's key) in your `.env` or shell.
3.  **The Trigger**: In any buffer, type `AI: Write a hello world function` and save the file.
4.  **The Review**: A **vimdiff** tab will open. Use `do` (diff obtain) or `dp` (diff put) to merge changes, then run `\aD` to accept and save.

## Requirements

*   **Neovim**: >= 0.10.0
*   **Python**: 3.9+ with `litellm` installed.
*   **Optional**: `Treesitter` (for project-wide code skeletons).

## Environment Variables

NZI supports the following environment variables for configuration:

| Variable | Description | Default |
| :--- | :--- | :--- |
| **`OPENROUTER_API_KEY`** | Your OpenRouter API key | - |
| **`NZI_MODEL`** | Default model alias to use | `deepseek` |
| **`NZI_PYTHON_CMD`** | Command to run Python (e.g. `python3` or path to venv) | `python3` |
| **`NZI_REFERER`** | HTTP-Referer header for OpenRouter alignment | `https://github.com/possumtech/nzi` |
| **`NZI_DEBUG`** | Set to `1` to enable verbose logging to `nzi_debug.log` | - |

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "possumtech/nzi",
  dependencies = { "nvim-lua/plenary.nvim" },
  opts = {
    -- Default configuration
    active_model = "deepseek",
    python_cmd = { "python3" }, -- Path to your python with litellm
  },
  config = function(_, opts)
    require("nzi").setup(opts)
  end,
}
```

---

## Interaction Matrix

| Mode | Symbol | CLI | Key | In-Code | Outcome |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Instruct** | `:` | `:AI: ...` | `\a:` | `AI: ...` | Surgical Edit / Diff |
| **Ask** | `?` | `:AI? ...` | `\a?` | `AI? ...` | Response in Modal |
| **Run** | `!` | `:AI! ...` | `\a!` | `AI! ...` | Buffer Injection |
| **Internal** | `/` | `:AI/ ...` | `\a/` | - | State/Context Control |

---

## Keybindings (Leader Commands)

NZI uses a `<leader>a` prefix for quick command access.

| Key | Action | Mode |
| :--- | :--- | :--- |
| **`\aa`** | **Toggle Modal** (AI Interaction window) | Normal |
| **`\a:`** | **Instruct**: Prompt for code modification | Normal/Visual |
| **`\a?`** | **Ask**: Prompt for analysis | Normal/Visual |
| **`\a!`** | **Run**: Prompt for command execution | Normal/Visual |
| **`\a/`** | **Internal**: Prompt for control command | Normal/Visual |
| **`\aA`** | Mark current buffer as **Active** (Full context) | Normal |
| **`\aR`** | Mark current buffer as **Read-only** (Context only) | Normal |
| **`\aI`** | Mark current buffer as **Ignored** (Completely hidden) | Normal |
| **`\aD`** | **Accept** current diff (Applies edit and saves) | Normal |
| **`\ad`** | **Reject** current diff (Discards suggestion) | Normal |
| **`\an`** | Jump to **Next** pending diff | Normal |
| **`\ap`** | Jump to **Previous** pending diff | Normal |
| **`\as`** | **Save** named session history | Normal |
| **`\al`** | **Load** named session history | Normal |
| **`\au`** | **Undo** last turn from history | Normal |
| **`\ay`** | **Yank** last response to clipboard | Normal |
| **`\ax`** | **Stop** active generation / **Skip** to next queued task | Normal |
| **`\aX`** | **Stop and Reset** session (Flush all queues) | Normal |
| **`\ak`** | Run project **Tests** | Normal |
| **`\aK`** | Run **Ralph** (Auto-retry tests) | Normal |
| **`\aY`** | Toggle **YOLO** mode (Autopilot) | Normal |

---

## Technical Specifications (XML Sublanguage)

### 1. Model Actions (Output Tags)
The model communicates intentions using `<model:*>` tags.

| Tag | Attributes | Purpose |
| :--- | :--- | :--- |
| `<model:summary>` | - | **Turn Terminator**: A one-sentence summary of actions |
| `<model:choice>` | - | **Turn Terminator**: A question requiring user input |
| `<model:edit>` | `file="path"` | Surgical SEARCH/REPLACE code modification |
| `<model:create>` | `file="path"` | Create a new file with full content |
| `<model:read>` | `file="path"` | Pull a file into active buffer context |
| `<model:grep>` | - | Search the project for a pattern |
| `<model:shell>` | - | Execute a destructive terminal command |
| `<model:env>` | - | Execute a read-only terminal command |
| `<model:choice>` | - | Present a multiple-choice menu to user |
| `<model:reset>` | - | Reset history and context |

### 2. Agent Metadata (Input Tags)
NZI provides structured environment data via `<agent:*>` tags.

| Tag | Attributes | Description |
| :--- | :--- | :--- |
| `<agent:selection>` | `file, start, end` | Character-perfect visual selection |
| `<agent:user>` | - | The user's specific instruction |
| `<agent:context>` | - | Current workspace/buffer facts |
| `<agent:project_state>` | - | Contents of `./AGENTS.md` |
| `<agent:next_task_suggest>` | - | First pending task from checklist |
| `<agent:grep>` | - | List of `<agent:match file="..." line="...">text</agent:match>` |
| `<agent:test>` | - | Output from a failing test or terminal |

---

## Precision Shell Logic (`AI!`)
When executing a shell command with a visual selection:
*   **No Command**: `:AI!` — Runs the selected text directly in the shell.
*   **With Command**: `:AI! command` — Runs `command selected_text`.
*   **Output**: Injected into the buffer below the selection.
*   **Context**: Prompts to add output to AI conversation history (Passive).

---

## Installation & Setup

```lua
{
  "possumtech/nzi",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    require("nzi").setup({
      python_cmd = { "python3" } -- Path to env with litellm
    })
  end,
}
```

*For deep technical documentation, roadmaps, and architecture, see [AGENTS.md](./AGENTS.md).*

---
*Sanitized. Structured. Agentic.*
