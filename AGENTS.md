# AGENTS.md: nzi Project Management

This is the living document for nzi development. We use this to track tasks, document design decisions, and log issues as they arise.

## Project Checklist

### Phase 0: Infrastructure & Core
- [x] **Scaffolding:** Initialize standard `lua/nzi/` structure with `setup()`.
- [x] **Test Framework:** Setup a headless Neovim test runner (using `plenary.test`).
- [x] **Async Execution:** Implement an Agnostic CLI job wrapper using `vim.system`.
- [ ] **80/80/80 Coverage:** Achieve 80% coverage on all core modules (config, job, context, parser).

### Phase 1: Context & Buffers
- [x] **The "Buffer-is-Context" Engine:** Logic to gather all open buffers.
- [x] **Context Management UI:** `:nziBuffers` command.
- [ ] **LSP Integration:** Deep symbol harvesting (Partial: initial logic in `lsp.lua`).
- [x] **Prompt Inheritance:** Merging layered markdown prompts.

### Phase 5: Integration & Real-World Validation
- [ ] **Local Model Integration:** Configure `nzi` to target `qwenzel` at `http://192.168.1.17:11434`.
- [ ] **Integration Suite:** Tests in `tests/integration/` that perform real LLM round-trips.
- [ ] **Performance Benchmarking:** Ensure context gathering and job submission are within 100ms.

### Phase 2: The Interpolation Engine
- [x] **Directive Parsing:** Efficiently scan for `nzi:`, `nzi?`, `nzi!`, and `nzi/` using optimized regex or Tree-sitter.
- [x] **`nzi!` (Shell):** Run shell commands and inject output directly into the buffer.
- [x] **`nzi:` (Directive):** Process code modification requests.
- [x] **`nzi?` (Question):** Process code-specific inquiries.

### Phase 3: The Fugitive-Diff Workflow
- [x] **Fugitive Integration:** Logic to pipe model output into a standard `vimdiff`/`fugitive` merge buffer.
- [x] **Diff Status:** Statusline indicators for outstanding diffs and pending approvals.
- [x] **Approval UX:** Ensure a seamless `dp` (put) and `do` (obtain) workflow for merging model changes.

### Phase 4: UI & Polish
- [x] **Read-only Modal:** High-performance floating window for model logs and "neurotic ramblings."
- [x] **Visual Mode Support:** Handling directives and questions on visual selections.
- [x] **Best Practices:** No global keybindings; all functionality exposed via commands.
- [x] **Health Checks:** Implemented `checkhealth nzi` in `lua/nzi/health.lua`.
- [ ] **Monitoring Hooks:** State IDs and events (`User NziStateChanged`) for external tool integration. (Internal logic implemented).

## Design Decisions

- **Buffer-is-Context:** All open buffers are sent to the model by default.
- **Fugitive-Diff Workflow:** The model provides diffs for user resolution via `fugitive` and `vimdiff` (`dp`/`do`).
- **Anti-Agent UI:** No chatbot interface; use code interpolation and a read-only modal for model status/logs.
- **Agnostic CLI Provider:** The plugin interacts with models via any OpenAI-compatible CLI (defaulting to `litellm`). This offloads Python/library management to the user and ensures the plugin remains lean.
- **Async Execution:** Use `vim.system` (Neovim 0.10+) for non-blocking model calls.

## Issue Log

- [ ] (Pending) Define how to handle model output parsing (e.g., standard unified diffs vs. hunk-based blocks).
