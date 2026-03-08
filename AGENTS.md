# AGENTS.md: AI (nzi) Living Document

This is the canonical source of truth for **nzi** development, technical specifications, and project tracking.

## 1. Project Roadmap

### Recent Accomplishments
- [x] Secured "Brutal Foundation" with 22 live model unit tests.
- [x] Implemented "Unified Directive" model: All turns are Missions (<ask>/<act>).
- [x] Achieved "Zero-Unwrap" fidelity: Assistant turns are direct projections of LiteLLM data.
- [x] Established technical <lookup> tag to replace ambiguous search/grep.
- [x] Implemented heuristic healing for malformed SEARCH/REPLACE blocks.
- [x] Cleaned repository: Unified ./test/ architecture and robust .gitignore.

### Pending Focus
- [ ] TODO: UNVERIFIED - Align Vim Service (Vim <--> DOM) with the new flat protocol.
- [ ] TODO: UNVERIFIED - Verify modal UI handles the new <reasoning_content> and <content> nesting.
- [ ] TODO: UNVERIFIED - Ensure Ralph Mode (auto-retry) respects the Unified Directive mission flow.

---

## 2. Technical Architecture (Unified Directive)

### Core Protocol
Every user interaction MUST be a mission. Technical feedback is carried via the `selection` tag.

| Tag | Attributes | Mission Type |
| :--- | :--- | :--- |
| **`<ask>`** | - | Pure inquiry; only read-only tools allowed. |
| **`<act>`** | - | Directive for state-changing action. |

### Feedback Signals (Inside <selection>)
| Type | Status | Boilerplate Directive |
| :--- | :--- | :--- |
| `shell` | `pass`/`fail` | Command completed / Command error. |
| `test` | `pass`/`fail` | Test passed / Test failed. |
| `env` | `pass`/`fail` | Discovery results / Discovery failed. |
| `answer` | `pass` | Your answer to a previous prompt_user. |

---

## 3. Master Functional Checklist

### Declarative Architecture (SSOT)
- [x] **Root Document**: Entire session wrapped in `<session>`.
- [x] **Formal Validation**: Real-time XSD/Schematron enforcement on the DOM.
- [x] **Context First**: Projector prepends history and roadmap before instructions.
- [ ] TODO: UNVERIFIED - **Vim Watcher**: Synchronous update of `<history>` on buffer events.
- [ ] TODO: IMPLEMENTATION GAP - **Vim Effector**: Opening diffs based on healed SEARCH/REPLACE blocks.

### Interaction Modes
- [x] **Act** (`:`): Directive action via `<act>`.
- [x] **Ask** (`?`): Pure inquiry via `<ask>`.
- [ ] TODO: UNVERIFIED - **Run** (`!`): Terminal output projected as `<selection type="shell">` inside a mission.

### Core Commands (Subcommands)
- [x] `/model`: Alias switching and selection.
- [x] `/clear`: Reset history/modal.
- [ ] TODO: UNVERIFIED - `/undo`: Remove last turn.
- [x] `/status`: State report.
- [ ] TODO: UNVERIFIED - `/toggle`: Modal UI control.
- [ ] TODO: UNVERIFIED - `/save` / `/load`: Session persistence.
- [ ] TODO: UNVERIFIED - `/ralph` / `/test`: Verification loops using new directive model.

### Loop Management
-   **Max Turns**: Default cap of 5 turns per instruction.
-   **Pruning**: TODO: UNVERIFIED - The `X` key in the modal allows the user to **Rewind** the context.

---

## 4. Testing & Behavior Validation

### New Test Hierarchy
1. **Unit Tests** (`test/units/`): Multi-turn live model drills verifying protocol fidelity.
2. **Filesystem Tests** (`test/fs/`): Integrity and "Universe" mapping verification.
3. **E2E Tests** (`test/e2e/`): Headless Neovim interaction round-trips.
4. **Contract Guard**: Every test enforces `nzi.xsd` and `nzi.sch`.

---
*Sanitized. Structured. Direct.*
