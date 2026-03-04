# AGENTS.md: AI (nzi) Project Management

This is the living document for AI (nzi) development. We use this to track tasks, document design decisions, and log issues as they arise.

## Project Checklist

### Phase 0: Infrastructure & Core
- [x] **Scaffolding:** Initialize standard `lua/nzi/` structure with `setup()`.
- [x] **Test Framework:** Setup a headless Neovim test runner (using `plenary.test`).
- [x] **Pure Lua Engine:** Implement a `curl` based OpenAI-native job wrapper using `vim.system`. (Removed Python/LiteLLM dependency).
- [ ] **80/80/80 Coverage:** Achieve 80% coverage on all core modules (config, job, context, parser).

### Phase 1: Context & Buffers
- [x] **The "Buffer-is-Context" Engine:** Logic to gather all open buffers.
- [ ] **Context Management UI:** `:AI/buffers` command. (command and proposed bindings for ignore and read-only)
- [ ] **LSP Integration:** Deep symbol harvesting (Partial: initial logic in `lsp.lua`).
- [x] **Prompt Inheritance:** Merging layered markdown prompts (`~/AGENTS.md`, `.ai.md`).

### Phase 2: The Interpolation & Unified Command
- [x] **Directive Parsing:** Efficiently scan for `AI:`, `AI?`, `AI!`, and `AI/`.
- [x] **Unified `:AI` Command:** Single entry point for questions, directives, and shell.
- [x] **Magic `:AI!` Shortcut:** Automatic `cnoreabbrev` for shell injection.
- [x] **Model Aliasing:** Support for switching between multiple models via `:AI/model <alias>`.
- [ ] **Commands:** AI/reset, AI/clear, AI/save AI/load, other common or necessary commands?

### Phase 3: "Under the Hood" UI
- [ ] **Strict Tagged Modal:** Machine-friendly XML structure with `nzi:` namespace.
- [x] **Telemetry Injection:** Real-time config/model status lines (White on Black).
- [x] **Structural Integrity Validator:** Deterministic XML validation in test suite.
- [x] **Read-only Protection:** Ensured modal is `nomodifiable` and protects against insert mode.

### Phase 4: Integration & Validation
- [x] **Local Model Integration:** Test `qwen2.5-coder` at `http://192.168.1.17:11434`.
- [x] **Fast Model Testing:** Use `coder` alias for integration and e2e tests.
- [x] **Integration Suite:** Real LLM round-trips verified in `tests/integration/`.
- [ ] **Fugitive-Diff Workflow (Refinement):** Re-implement surgical edits once a stable strategy is devised. (Currently unified with question handler).

## Design Decisions

- **Buffer-is-Context:** All open buffers are sent to the model by default.
- **Pure Lua & Curl:** Zero external dependencies (no Python, no Node, no LiteLLM). Native `curl` ensures high performance and reliability.
- **OpenAI Standard Lexicon:** All internal logic and tags (`reasoning_content`, `content`, `user`) align exactly with the OpenAI API standard.
- **Machine-Friendly UI:** The modal is designed to be parsed by machines while remaining readable for humans through strict tagging and color-coding.
- **Telemetry Lines:** Interaction blocks are preceded by structured telemetry data (`model`, `temp`, `top_p`) for absolute transparency.

## Issue Log

- [ ] (Pending) Surgical Edits: Devise a strategy for applying partial file updates that avoids the fragility of line numbers (e.g. Search/Replace blocks).
