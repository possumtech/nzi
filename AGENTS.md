# AGENTS.md: AI (nzi) Living Document

This is the canonical source of truth for **nzi** development, technical specifications, and project tracking.

## 1. Project Roadmap & Checklist

### Current Focus
- [x] Visual select not working
- [x] Interface Improvements (abort/cancel)
- [x] :AI-reset \aX, :AI-save name \as, :AI-load name \al
- [x] :AI-test \ak, :AI-ralph \aK (with file)
- [x] AI interpolation must be at beginning of line.
- [x] SEARCH/REPLACE + NeoVim Diff ergonomics (Auto-save/tab closure)
- [x] XML validation of prompt construction

### Pending Tasks
- [ ] Web Search tool
- [ ] <agent:skill> architecture
- [ ] Tool / Skill Plugin Architecture
- [ ] MCP (Model Context Protocol) Integration
- [ ] WebMCP Support

---

## 2. Technical Architecture

### Directory Structure
```text
lua/nzi/
├── init.lua               # Main entry point & API surface
├── core/                  # Fundamentals (config, commands, health)
├── ui/                    # Visuals (modal, visuals, buffers, diff, editor)
├── context/               # State (context, history, resolver, sitter)
├── engine/                # Orchestrator (engine, parser, prompts, job)
├── protocol/              # Communication (protocol, agent, bridge.py)
└── tools/                 # Capabilities (tools, shell, lsp, directive)
```

### Context Visibility Hierarchy
| File Type | Not Open (Passive) | Open in Buffer (Intent) |
| :--- | :--- | :--- |
| **Tracked/Staged** | **Visible** (Map/Skeleton) | **Visible** (Active/Read) |
| **Untracked** | **Hidden** | **Visible** (Active/Read) |
| **Git-Ignored** | **Hidden** | **Hidden** (Default `ignore`) |

---

## 3. Master Functional Checklist

### Interaction Modes
- [x] **AI: Directive**: CLI, In-Code, and Range triggers.
- [x] **AI? Question**: CLI, In-Code, and Range triggers.
- [x] **AI! Shell**: CLI and In-Code triggers.
- [x] **AI/ Internal**: Control commands.

### Core Commands (AI/ Subcommands)
- [x] `/model`, `/clear`, `/undo`, `/status`, `/toggle`, `/stop`, `/yank`.
- [x] `/next`, `/prev`: Review queue navigation.
- [x] `/accept`, `/reject`: Diff view lifecycle.
- [x] `/save`, `/load`: Session persistence (~/.local/share/nvim/nzi/sessions/).
- [x] `/active`, `/read`, `/ignore`: Explicit context control.
- [x] `/ralph`, `/test`: Verification loops.

### Agentic Capabilities
- [x] **Surgical Edits**: `<model:edit>` with SEARCH/REPLACE blocks.
- [x] **Context Gathering**: `smart_filter` escaping, LSP definitions, Treesitter skeletons.
- [x] **Ralph Mode**: Automatic test-failure feedback loop.
- [x] **Interpolation**: Auto-execution on buffer save (`BufWritePre`).

---

## 4. E2E & Behavior Validation

### Test Suites
1. **Unit Tests (`tests/nzi/`)**: Modular verification of individual components.
2. **E2E Tests (`tests/nzi/e2e/`)**: Full flow verification (01-07).
3. **Integration Tests (`tests/integration/`)**: Real LLM interaction (BEEF).
4. **XML Rigor**: Systematic validation via Python ET in `tests/xml_helper.lua`.

### Verification Targets
- [ ] **Character-Perfect Visual Selection**: Exact columns and mode (`v`, `V`, `^V`).
- [ ] **Stream Resiliency**: Handling chunked/cut-off XML tags.
- [ ] **Ralph Loop**: Verification that failures are correctly fed back.

---

## 5. Development Notes
- **Bridge Logic**: The `bridge.py` uses `litellm`. Background threads are disabled to ensure prompt termination.
- **Prompt Isolation**: System rules, project context, and the current turn are sent as separate messages to optimize provider caching.
- **Surgicality**: Prefers smallest possible edits over full file replacements.

---
*Sanitized. Structured. Agentic.*
