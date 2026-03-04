local lsp = require("nzi.lsp");

local M = {};

--- Read a file's content safely
--- @param path string
--- @return string | nil
local function read_file(path)
  local expanded_path = vim.fn.expand(path);
  local f = io.open(expanded_path, "r");
  if not f then return nil; end
  local content = f:read("*all");
  f:close();
  return content;
end

--- Gather all relevant prompt components (Global, Project, Local)
--- @return table: Map of prompt parts
function M.gather()
  local prompts = {};

  -- 1. Global AGENTS.md (User's global directives)
  prompts.global = read_file("~/AGENTS.md");

  -- 2. Project-local .nzi.md (Project-specific rules/context)
  -- Search for .nzi.md in the current directory and its parents
  local project_nzi = vim.fs.find(".nzi.md", { upward = true, stop = vim.loop.os_homedir() })[1];
  if project_nzi then
    prompts.project = read_file(project_nzi);
  end

  -- 3. Project-local AGENTS.md (Project tasks)
  local project_agents = vim.fs.find("AGENTS.md", { upward = true, stop = vim.loop.os_homedir() })[1];
  if project_agents then
    prompts.tasks = read_file(project_agents);
  end

  return prompts;
end

--- Combine gathered prompts into a single system prompt string
--- @param prompts table: The result of M.gather()
--- @param model_name string: The name/alias of the model
--- @return string
function M.build_system_prompt(prompts, model_name)
  local parts = { string.format("You are %s, a Neovim-native agentic programming tool.", model_name) };
  
  if prompts.global then
    table.insert(parts, "\n### GLOBAL DIRECTIVES (from ~/AGENTS.md)\n" .. prompts.global);
  end
  
  if prompts.project then
    table.insert(parts, "\n### PROJECT RULES (from .nzi.md)\n" .. prompts.project);
  end
  
  if prompts.tasks then
    table.insert(parts, "\n### PROJECT TASKS (from AGENTS.md)\n" .. prompts.tasks);
  end

  return table.concat(parts, "\n");
end

--- Format gathered context into a readable string for the LLM
--- @param ctx_list table: List of buffer objects from context.gather()
--- @param include_lsp boolean | nil: Whether to include LSP symbol info
--- @return string
function M.format_context(ctx_list, include_lsp)
  local parts = { "### CONTEXT (Active/Read Buffers)" };
  for _, item in ipairs(ctx_list) do
    local short_name = vim.fn.fnamemodify(item.name, ":.")
    table.insert(parts, string.format("\nFILE: %s (State: %s)\n```\n%s\n```", short_name, item.state, item.content));
  end

  -- Add LSP symbol definition only if explicitly requested (e.g., for localized directives)
  if include_lsp then
    local lsp_info = lsp.get_symbol_definition();
    if lsp_info then
      table.insert(parts, "\n### LSP DEFINITION (Symbol at cursor)");
      table.insert(parts, string.format("Source: %s (Line: %d)\n```\n%s\n```", lsp_info.uri, lsp_info.line, lsp_info.content));
    end
  end

  return table.concat(parts, "\n");
end

--- Build the full prompt for a code modification directive (nzi:)
--- @param directive string: The user's instruction
--- @param target_file string: The name of the file being modified
--- @param prompts table: Global/Project prompts from gather()
--- @param context_str string: Formatted context from format_context()
--- @return string
function M.build_directive_prompt(directive, target_file, prompts, context_str)
  local parts = { M.build_system_prompt(prompts) };
  
  table.insert(parts, "\n" .. context_str);
  
  table.insert(parts, "\n### DIRECTIVE");
  table.insert(parts, "You are editing the file: " .. target_file);
  table.insert(parts, "Instruction: " .. directive);
  table.insert(parts, "\n### OUTPUT FORMAT");
  table.insert(parts, "Return the FULL, COMPLETE content of " .. target_file .. " with the changes applied.");
  table.insert(parts, "DO NOT use markdown code blocks. DO NOT provide explanations. Just the raw source code.");
  
  return table.concat(parts, "\n");
end

return M;
