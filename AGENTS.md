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
- [ ] Refactor LLM Service (DOM <--> LLM) to use pure XML streaming and validation.
- [ ] Refactor Vim Service (Vim <--> DOM) to use effector/watcher pattern.
- [ ] Complete the "Purge" of legacy imperative state tables.

---

## 2. Technical Architecture (Service-Oriented)

### Core Modules
| Module | Location | Purpose |
| :--- | :--- | :--- |
| **DOM** | `lua/nzi/dom/` | **Single Source of Truth.** XML Document, Schema, and XPath Query engine. |
| **Vim Service** | `lua/nzi/service/vim/` | **Hardware Sync.** Translates between Vim events/UI and the XML DOM. |
| **LLM Service** | `lua/nzi/service/llm/` | **Cognitive Bridge.** Translates between XML DOM and LLM Chat APIs. |
| **UI** | `lua/nzi/ui/` | **Ergonomics.** Projections of the DOM (Modal, Statusline) for the Human. |
| **Tools** | `lua/nzi/tools/` | Stateless utilities used by effector and parser. |

---

## 3. Master Functional Checklist

### Declarative Architecture (SSOT)
- [x] **Root Document**: Entire session wrapped in `<session>` with global state attributes.
- [x] **XPath State Derivation**: `is_blocked()` and `get_pending_actions()` derived from XML.
- [x] **Formal Validation**: Real-time XSD/Schematron enforcement on the DOM.
- [ ] **Vim Watcher**: Synchronous update of `<context>` on buffer events.
- [ ] **Vim Effector**: Declarative opening of diffs/terminals based on DOM state.
- [ ] **LLM Bridge**: Pure-function translation of XML tree to OpenAI JSON.
- [ ] **XML Streaming**: Direct real-time injection of LLM chunks into the DOM.

| :--- | :--- | :--- |
| **`active`** | **Full Context** | Content sent; model can propose edits. |
| **`read`** | **Context Only** | Content sent; model treats as read-only doc. |
| **`map`** | **Skeleton Context** | Project structure (universe) sent; no content. |
| **`ignore`** | **Hidden** | Invisible to the model (e.g., .env). |

---

## 3. Master Functional Checklist

### Interaction Modes (Specialized Tags)
- [x] **Instruct** (`:`): Directive action via `<instruct>` (`\a:`).
- [x] **Ask** (`?`): Pure inquiry via `<ask>` (`\a?`).
- [x] **Shell** (`!`): Terminal output via `<shell command="...">` (`\a!`).
- [x] **Error** (Internal): System/Tool failure via `<error>`.
- [x] **Answer** (Choice): Response to a `<choice>` via `<answer>`.
- [x] **Internal** (`/`): Plugin control (CLI, `\a/`).

### Core Commands (Subcommands)
- [x] `/model`: Alias switching and selection.
- [x] `/clear`: Reset history/modal.
- [x] `/undo`: Remove last turn.
- [x] `/status`: State report.
- [x] `/toggle`: Modal UI control.
- [x] `/stop`: Process termination.
- [x] `/yank`: Clipboard integration.
- [x] `/next` / `/prev`: Diff queue navigation.
- [x] `/accept` / `/reject`: Diff resolution.
- [x] `/save` / `/load`: Session persistence.
- [x] `/active` / `/read` / `/ignore`: Context overrides.
- [x] `/ralph` / `/test`: Verification loops.

### Agentic Capabilities
- [x] **Surgical Edits**: `<edit>` with precise SEARCH/REPLACE.
- [x] **Context Gathering**: Treesitter skeletons, LSP definitions, smart_filter escaping.
- [x] **Ralph Mode**: Autonomous test-failure auto-retry.
- [x] **Interpolation**: "Ghost writing" execution on save.

### Loop Management
-   **Max Turns**: Default cap of 5 turns per instruction.
-   **Pruning**: The `X` key in the modal allows the user to **Rewind** the context. This deletes the turn at the cursor and everything following it, maintaining context linearity.


---

## 4. E2E & Behavior Validation

### Test Hierarchy
1. **Unit Tests** (`tests/nzi/`): Modular logic verification.
2. **E2E Tests** (`tests/nzi/e2e/`): Interaction round-trips (01-07).
3. **Integration Tests** (`tests/integration/`): Real LLM calls (BEEF).
4. **XML Rigor**: Python ElementTree validation in every prompt test.

### Verification Targets
- [x] **Character-Perfect Visual Selection**: Exact columns and mode (v, V, ^V).
- [x] **Structured Grep**: Using <match> attributes to avoid colon ambiguity.
- [x] **Terminating Logic**: Disabling background threads in bridge.py.
- [x] **Passive Context**: Run output added to history without triggering turns.

## 5. Poetic Interlude

```
There once was a limerick so bright,
That made all the agents feel light.
With rhyme and with reason,
They'd solve every question,
And dance in the code of the night.
```

---
*Sanitized. Structured. Agentic.*
