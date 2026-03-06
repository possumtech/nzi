# AGENTS.md: AI (nzi) Living Document

This is the canonical source of truth for **nzi** development, technical specifications, and project tracking.

## 1. Project Roadmap & Roadmap

### Recent Accomplishments
- [x] Consistently unified terminology (Instruct, Ask, Run, Internal).
- [x] Selection as Argument logic for Shell ranges.
- [x] Mode-aware interaction keybindings (\a:, \a?, \a!, \a/).
- [x] Session persistence (Save/Load).
- [x] Surgical Edit & Diff UX (Auto-save/tab cleanup).
- [x] Systematic XML validation.

### Pending Focus
- [ ] Web Search tool implementation.
- [ ] Plugin/Skill architecture (<agent:skill>).
- [ ] MCP (Model Context Protocol) support.
- [ ] Context size limit management.

---

## 2. Technical Architecture

### Core Modules
| Module | Location | Purpose |
| :--- | :--- | :--- |
| **Engine** | `lua/nzi/engine/` | Loop orchestration and prompt building. |
| **Protocol** | `lua/nzi/protocol/` | Tag parsing and LLM bridge (bridge.py). |
| **UI** | `lua/nzi/ui/` | Modal, Diff, and Visual management. |
| **Context** | `lua/nzi/context/` | Buffer states, history, and path resolution. |
| **Tools** | `lua/nzi/tools/` | Shell, LSP, and Instruct execution. |

### Context Visibility Hierarchy
| State | Documentation Term | Logic |
| :--- | :--- | :--- |
| **`Active`** | **Full Context** | Content sent; model can propose edits. |
| **`Read`** | **Context Only** | Content sent; model treats as read-only doc. |
| **`Map`** | **Skeleton Context** | Project structure (universe) sent; no content. |
| **`Ignore`** | **Hidden** | Invisible to the model (e.g., .env). |

---

## 3. Master Functional Checklist

### Interaction Modes
- [x] **Instruct** (`:`): Direct modification (CLI, In-Code, Visual, `\a:`).
- [x] **Ask** (`?`): Inquiry/Analysis (CLI, In-Code, Visual, `\a?`).
- [x] **Run** (`!`): Terminal execution (CLI, In-Code, Visual, `\a!`).
- [x] **Internal** (`/`): Plugin control (CLI, `\a/`).

### Core Commands (Subcommands)
- [x] `/model`: Alias switching and selection.
- [x] `/clear`: Reset history/modal.
- [x] `/undo`: Remove last turn.
- [x] `/status`: State report.
- [x] `/toggle`: Modal UI control.
- [x] `/stop`: Process termination.
- [x] `/yank`: Clipboard integration.
- [x] `/next` / `/prev`: Review queue navigation.
- [x] `/accept` / `/reject`: Diff resolution.
- [x] `/save` / `/load`: Session persistence.
- [x] `/active` / `/read` / `/ignore`: Context overrides.
- [x] `/ralph` / `/test`: Verification loops.

### Agentic Capabilities
- [x] **Surgical Edits**: `<model:edit>` with precise SEARCH/REPLACE.
- [x] **Context Gathering**: Treesitter skeletons, LSP definitions, smart_filter escaping.
- [x] **Ralph Mode**: Autonomous test-failure auto-retry.
- [x] **Interpolation**: "Ghost writing" execution on save.

---

## 4. E2E & Behavior Validation

### Test Hierarchy
1. **Unit Tests** (`tests/nzi/`): Modular logic verification.
2. **E2E Tests** (`tests/nzi/e2e/`): Interaction round-trips (01-07).
3. **Integration Tests** (`tests/integration/`): Real LLM calls (BEEF).
4. **XML Rigor**: Python ElementTree validation in every prompt test.

### Verification Targets
- [x] **Character-Perfect Visual Selection**: Exact columns and mode (v, V, ^V).
- [x] **Terminating Logic**: Disabling background threads in bridge.py.
- [x] **Passive Context**: Run output added to history without triggering turns.

---
*Sanitized. Structured. Agentic.*
