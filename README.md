# nzi
Neovim-Native Agentic Zone Integration

## The Anti-Agent

Stream of consciousness conversations are an anti-pattern in software development, distracting one's focus from one's code and gathering all of the important project information into an ephemeral and rambling conversational chat log. With nzi, your communication with your agent occurs in three ways:

1. Code Interpolation

You can create a new line and type nzi: ..., nzi? ..., nzi! ..., or nzi/...

### The Directive:

Interpolated directives enable you to remain fully integrated into the zone of your code, where you belong.

nzi: Reduce the cyclomatic complexity of this function.

### The Question:

Don't waste tokens hoping your model can figure out what you're talking about. Ask it about the code in the right spot.

nzi? Please explain this function to me.

### The Shell:

This runs a shell command and injects it into your code.

nzi! git log

### The Command

This sends a command to nzi. See: `nzi Commands`

nzi/model qwenlocal

2. Status Bar Commands

Status bar commands are identical to interpolated commands, but in the normal mode status bar. This is the place to directly interact with your model when the interaction doesn't directly pertain to a particular chunk of code.

3. AGENTS.md

Your AGENTS.md file can and should be a shared, collaborative, living document that provides a persistent and structured project management experience. Instead of talking to a chatbot in a different window like he's your drinking buddy about your project, create a markdown checklist of tasks to perform and then send a directive to perform the next task.

## Neovim Integration

Neovim with the fugitive plugin is almost everything you need to replace your bloated and glitchy agent. With nzi, your open buffers are your context, your lsp is your "repo map," and nzi offers "diffs" when it edits your code that you deal with using the same plugins and key mappings you're already using for git merges. This workflow, where you see and approve every change, keeps you grounded in your code and what the model is doing to your code. It allows you to identify mistakes by the model in an elegant and early manner, rather than needing to discard everything and start over when something's not quite right.

## Modal Interface

The model and its neurotic ramblings are hidden from you unless you toggle open the read-only modal window. The model can force the modal open if it requires your attention, and you can respond to what's in the modal with your commands. In other words, you can still "chat" with your model in the usual way if you insist, but the tooling and workflow are designed to encourage and support being a more agentic programmer.

## Model Access

With LiteLLM integration, nzi supports nearly all of the models, including your own local models. With this technology stack and these design decisions, we can achieve more concise system prompts, resulting in fewer tokens being spent on tooling and more context being invested in what you're trying to build than how you're trying to build it.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "your-username/nzi",
  dependencies = {
    "nvim-lua/plenary.nvim",   -- Core async and job management
    "tpope/vim-fugitive",     -- Required for the diff/merge workflow
    "nvim-treesitter/nvim-treesitter", -- Highly recommended for directive parsing
  },
  config = function()
    require("nzi").setup({
      -- your configuration here
    })
  end,
  keys = {
    { "<leader>an", ":Nzi<CR>", mode = { "n", "v" }, desc = "nzi: Execute Directive" },
    { "<leader>at", ":NziToggle<CR>", desc = "nzi: Toggle Modal" },
    { "<leader>ab", ":NziBuffers<CR>", desc = "nzi: Manage Buffers" },
    { "<leader>aq", ":NziQuestion ", desc = "nzi: Ask Question" },
  },
}
```

## Recommended Keymaps

nzi does not set any global keybindings by default. We recommend the following:

```lua
-- Normal Mode
vim.keymap.set("n", "<leader>an", ":Nzi<CR>", { desc = "nzi: Run Directive" })
vim.keymap.set("n", "<leader>at", ":NziToggle<CR>", { desc = "nzi: Toggle Modal" })
vim.keymap.set("n", "<leader>ab", ":NziBuffers<CR>", { desc = "nzi: Manage Context" })

-- Visual Mode
vim.keymap.set("v", "<leader>an", ":Nzi<CR>", { desc = "nzi: Run on Selection" })
```

## Prerequisites

- **Neovim 0.10+** (Recommended for `vim.system`)
- **LiteLLM**: Ensure `litellm` is installed and available in your shell.
  ```bash
  pip install litellm
  ```


## Contributing

## Project Checklist

As you work this checklist, add and modify tasks, document design decisions and issues in this document.

### Phase 0: Infrastructure & Core
- [ ] **Scaffolding:** Initialize standard `lua/nzi/` structure with `setup()` and configuration handling.
- [ ] **Test Framework:** Setup a headless Neovim test runner (using `plenary.test` or similar).
- [ ] **Async Execution:** Implement a non-blocking job wrapper using `vim.system` (or `plenary.job`) for LiteLLM communication.

### Phase 1: Context & Buffers
- [ ] **The "Buffer-is-Context" Engine:** Logic to gather all open buffers by default as model context.
- [ ] **Context Management UI:** `:nziBuffers` command to list buffers and toggle states (`active`, `read`, `ignore`).
- [ ] **LSP Integration:** Harvesting symbol definitions and references for better model grounding.
- [ ] **Prompt Inheritance:** Merging `~/AGENTS.md`, local `.nzi.md`, and buffer-local directives.

### Phase 2: The Interpolation Engine
- [ ] **Directive Parsing:** Efficiently scan for `nzi:`, `nzi?`, `nzi!`, and `nzi/` using optimized regex or Tree-sitter.
- [ ] **`nzi!` (Shell):** Run shell commands and inject output directly into the buffer.
- [ ] **`nzi:` (Directive):** Process code modification requests.
- [ ] **`nzi?` (Question):** Process code-specific inquiries.

### Phase 3: The Fugitive-Diff Workflow
- [ ] **Fugitive Integration:** Logic to pipe model output into a standard `vimdiff`/`fugitive` merge buffer.
- [ ] **Diff Status:** Statusline indicators for outstanding diffs (+/- lines) and pending approvals.
- [ ] **Approval UX:** Ensure a seamless `dp` (put) and `do` (obtain) workflow for merging model changes.

### Phase 4: UI & Polish
- [ ] **Read-only Modal:** High-performance floating window for model logs and "neurotic ramblings."
- [ ] **Visual Mode Support:** Handling directives and questions on visual selections.
- [ ] **Monitoring Hooks:** State IDs and events (`User NziStateChanged`) for external tool integration.

> **Design Note:** Prioritize the relationship between the user, the model, and `fugitive`. The model should output diffs that mimic git merges, allowing the user to approve/reject changes using the same keybindings they use for version control. This avoids heavy, custom agent workflows.
