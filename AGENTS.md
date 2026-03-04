# AGENTS.md: AI (nzi) Project Management

This is the living document for AI (nzi) development. We use this to track tasks, document design decisions, and log issues as they arise.

## Project Checklist

### Phase 0: Infrastructure & Core
- [x] **Scaffolding:** Initialize standard `lua/nzi/` structure with `setup()`.
- [x] **Test Framework:** Setup a headless Neovim test runner (using `plenary.test`).
- [x] **LiteLLM Bridge:** Implement a Python-based LiteLLM bridge for multi-provider support.
- [ ] **80/80/80 Coverage:** Achieve 80% coverage on all core modules (config, job, context, parser).

### Phase 1: Context & Buffers
- [x] **The "Buffer-is-Context" Engine:** Logic to gather all open buffers.
- [ ] **Context Management UI:** `:AI/buffers` command. (command and proposed bindings for ignore and read-only)
- [ ] **LSP Integration:** Deep symbol harvesting (Partial: initial logic in `lsp.lua`).
- [x] **Prompt Inheritance:** Merging layered markdown prompts (`~/AGENTS.md`, `.ai.md`).

### Phase 1.5: Universe Mapping
- [x] **Git-Native Universe Discovery:** Use `git ls-tree` to define the model's project boundaries.
- [x] **State Hierarchy:** Implement `active` (edit), `read` (ref), `map` (skeleton), and `ignore` (hidden).
- [x] **Tree-sitter Skeletonization:** Generate metadata-only "maps" for non-open project files.
- [x] **Universe UI (`:AI/tree`):** Scrollable dropdown tree showing the project's relationship with the model.
- [x] **Universe E2E Repo:** Robust test infrastructure with real git states.

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
- [x] **Local Model Integration:** Test `qwenzel` at `http://192.168.1.17:11434`.
- [x] **Fast Model Testing:** Use `deepseek` alias for integration and e2e tests.
- [x] **Integration Suite:** Real LLM round-trips verified in `tests/integration/`.
- [ ] **Interpolation:** When AI?, AI:, AI!, or AI/ appears on a new line of a filed that's saved, catch and handle it.
- [ ] **Visual Interpolation:** Visual mode where you select lines/region and then <>AI?:!/
- [ ] **Git or LSP project integration:** 
- [ ] **Surgical Edit Workflow:** Implement Search/Replace markers for agnostic file updates.

### Phase 5: Agentic Tools & Plugins
- [ ] **Tool/Function Calling Infrastructure:** Core logic to register and dispatch Lua functions as LLM tools.
- [ ] **Plugin Architecture:** Systematic way to add/remove "Skills" (Tool collections).
- [ ] **MCP (Model Context Protocol):** Support for the standard MCP interface for cross-tool compatibility.
- [ ] **WebMCP:** Integration for remote or web-based tool execution.

### Phase 6: Stability & Search
- [ ] **Structured Output Enforcement:** Integrate `response_format: { type: "json_object" }` for all tool-heavy interactions to avoid filter-driven stream breaks.
- [ ] **Native Web Search Tool:** Implement a `web_search` tool using Ollama's native API or a web-based provider (Tavily/Serper).
- [ ] **Model Fallback Logic:** Automatically retry a failed "Power" model call with a "Stability" model (e.g., switching to Gemini if DeepSeek hits a provider limit).

## Design Decisions

- **LiteLLM Bridge:** We use a lightweight Python bridge with `litellm` to provide effortless compatibility with hundreds of LLM providers while keeping the Lua side lean and focused on Neovim integration.
- **Buffer-is-Context:** All open buffers are sent to the model by default.
- **OpenAI Standard Lexicon:** All internal logic and tags (`reasoning_content`, `content`, `user`) align exactly with the OpenAI API standard.
- **Machine-Friendly UI:** The modal is designed to be parsed by machines while remaining readable for humans through strict tagging and color-coding.
- **Telemetry Lines:** Interaction blocks are preceded by structured telemetry data (`model`, `temp`, `top_p`) for absolute transparency.

## Issue Log

- [ ] (Pending) Surgical Edits: Devise a strategy for applying partial file updates. 
    - *Idea:* Use Search/Replace markers (`<<<<<<< SEARCH`, `=======`, `>>>>>>> REPLACE`) as the edit format. Models are heavily trained on this syntax, making it more robust than line-number-based unified diffs. These can be applied and resolved via Neovim's native diffing.

## Future Architectural Enhancements

These Neovim-native features should be leveraged to increase agent precision:

### 1. Semantic Intelligence (LSP)
- **Symbol Resolution:** Use LSP to provide the model with exact definitions and references instead of fuzzy string searches.
- **Real-time Correctness:** Feed diagnostics (lint errors) back to the model during the editing loop so it can self-correct.

### 2. Structural Awareness (Tree-sitter)
- **Node-based Context:** Allow the model to request "the whole class" or "this specific function" by name using Tree-sitter queries.
- **Syntax-Safe Edits:** Perform replacements on CST nodes to ensure the resulting code is always syntactically valid.

### 3. Non-Destructive UI (Extmarks & Virtual Text)
- **Inline Thoughts:** Display the model's reasoning or warnings as virtual text alongside code without modifying the buffer.
- **Ghost Edits:** Show proposed changes as overlays that the user can accept/reject with a single key.

### 4. Agentic Scratchpads (Hidden Buffers)
- **Mental Simulation:** Let the model spawn hidden buffers to run temporary scripts or "think" through complex logic before presenting a final answer.
- **Ephemeral State:** Use win-local or buf-local variables to track telemetry and interaction state without global pollution.
