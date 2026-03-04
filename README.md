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



## Getting Started


## Contributing

## Project Checklist

As you work this checklist, add and modify tasks, document design decisions and issues in this document.

- [ ] Create generic, modern, standard, best practices neovim plugin
- [ ] Create test framework with headless neovim instance for testing
- [ ] Establish plugin integration with lsp, fugitive, plenary, and litellm
- [ ] Create toggled read-only modal with toggle commands that can be mapped to key bindings
- [ ] Create nzi:, nzi?, nzi!, and nzi/ normal mode command handling
- [ ] Create LLM interface
- [ ] Test ability to use modal and commands for basic chat experience
- [ ] Create buffer sync to context (with active / read / ignore flags in statusbar)
- [ ] Create lsp repo mapping
- [ ] Create interpolation commands
- [ ] Create visual mode commands
- [ ] Create system prompt
- [ ] Create fugitive / system prompt / edit framework
- [ ] Create status line showing outstanding diffs to approve/reject and current +/- lines in outstanding diffs
