# AI (nzi)
### Neovim-Native Agentic Interface

**AI (nzi)** is a lean, high-performance agentic interface for Neovim. It moves the assistant out of a separate chat window and directly into your source code and your workflow. 

Unlike assistants that treat your project as a static "context dump," **nzi** treats Neovim as the living nervous system of your project. What you see is what the model gets.

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
| **`\ax`** | **Stop** active generation | Normal |
| **`\aX`** | **Stop and Reset** session | Normal |
| **`\ak`** | Run project **Tests** | Normal |
| **`\aK`** | Run **Ralph** (Auto-retry tests) | Normal |
| **`\aY`** | Toggle **YOLO** mode (Autopilot) | Normal |

---

## Technical Specifications (XML Sublanguage)

### 1. Model Actions (Output Tags)
The model communicates intentions using `<model:*>` tags.

| Tag | Attributes | Purpose |
| :--- | :--- | :--- |
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
