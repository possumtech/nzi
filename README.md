# AI (nzi)
### Neovim-Native Agentic Interface

**AI (nzi)** is a lean, high-performance agentic interface for Neovim. It moves the assistant out of a separate chat window and directly into your source code and your workflow. 

Unlike assistants that treat your project as a static "context dump," **nzi** treats Neovim as the living nervous system of your project. What you see is what the model gets.

---

## Interaction Modes (The Four Horsemen)

| Mode | Trigger | Purpose | Outcome |
| :--- | :--- | :--- | :--- |
| **`AI:` Directive** | `:AI: instruction` | Code modification / tasks | Buffer edit / Diff view |
| **`AI?` Question** | `:AI? question` | Analysis / general knowledge | Response in Modal |
| **`AI!` Shell** | `:AI! command` | Terminal execution | Output injected in buffer |
| **`AI/` Internal** | `:AI/ command` | State / Context management | UI update / Configuration |

---

## Keybindings (Leader Commands)

NZI uses a `<leader>a` prefix for quick command access.

| Key | Action | Mode |
| :--- | :--- | :--- |
| **`\aa`** | **Toggle Modal** (AI Interaction window) | Normal |
| **`\aa`** | **Execute Selection** (Send visual range to AI) | Visual |
| **`\aA`** | Mark current buffer as **Active** (Full context) | Normal |
| **`\aR`** | Mark current buffer as **Read-only** (Context only) | Normal |
| **`\aI`** | Mark current buffer as **Ignored** (Completely hidden) | Normal |
| **`\aD`** | **Accept** current review (Applies edit and saves) | Normal |
| **`\ad`** | **Reject** current review (Discards suggestion) | Normal |
| **`\an`** / **`\ap`** | Jump to **Next** / **Previous** pending review | Normal |
| **`\as`** / **`\al`** | **Save** / **Load** named session history | Normal |
| **`\au`** | **Undo** last turn from conversation history | Normal |
| **`\ax`** / **`\aX`** | **Stop** generation / Stop and **Reset** session | Normal |
| **`\ak`** / **`\aK`** | Run project **Tests** / Run **Ralph** (Auto-retry) | Normal |
| **`\ay`** | **Yank** last response to clipboard | Normal |
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
| `<agent:selection>` | `file, start, end, mode` | Character-perfect user selection |
| `<agent:user>` | - | The user's specific instruction |
| `<agent:context>` | - | Current workspace/buffer facts |
| `<agent:project_state>` | - | Contents of `./AGENTS.md` |
| `<agent:next_task_suggest>` | - | First pending task from checklist |
| `<agent:test>` | - | Output from a failing test (Ralph mode) |

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
