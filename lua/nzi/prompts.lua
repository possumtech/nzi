local lsp = require("nzi.lsp");
local history = require("nzi.history");
local config = require("nzi.config");

local M = {};

--- Escape special characters for XML safety
--- @param text string
--- @return string
local function xml_escape(text)
  if not text then return ""; end
  return text:gsub("&", "&amp;")
             :gsub("<", "&lt;")
             :gsub(">", "&gt;")
             :gsub("\"", "&quot;")
             :gsub("'", "&apos;")
end

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

  -- 1. Global AGENTS.md (User's global directives/standards)
  prompts.global = read_file("~/AGENTS.md");

  -- 2. Project-local .ai.md (Project-specific rules)
  local project_ai = vim.fs.find(".ai.md", { upward = true, stop = vim.loop.os_homedir() })[1];
  if project_ai then
    prompts.project = read_file(project_ai);
  end

  -- 3. Project-local AGENTS.md (Active project tasks)
  local project_agents = vim.fs.find("AGENTS.md", { upward = true, stop = vim.loop.os_homedir() })[1];
  if project_agents then
    prompts.tasks = read_file(project_agents);
  end

  return prompts;
end

--- Combine gathered prompts into a single system prompt string
--- @param prompts table: The result of M.gather()
--- @param model_alias string: The name/alias of the model
--- @return string
function M.build_system_prompt(prompts, model_alias)
  local parts = { string.format("You are %s, a Neovim-native agentic programming tool.", model_alias) };
  
  if prompts.global then
    table.insert(parts, "\n### GLOBAL ENGINEERING STANDARDS\n" .. prompts.global);
  end
  
  if prompts.project then
    table.insert(parts, "\n### PROJECT RULES\n" .. prompts.project);
  end

  return table.concat(parts, "\n");
end

--- Format gathered context into a readable string for the LLM
--- @param ctx_list table: List of buffer objects from context.gather()
--- @param include_lsp boolean | nil: Whether to include LSP symbol info
--- @param task_prompt string | nil: Local AGENTS.md tasks
--- @return string
function M.format_context(ctx_list, include_lsp, task_prompt)
  -- 1. Sort by name to ensure stable prefix for Context Caching
  table.sort(ctx_list, function(a, b) return a.name < b.name end);

  local parts = { "<nzi:context>" };
  
  -- 2. Include active project tasks if present
  if task_prompt then
    table.insert(parts, "  <nzi:project_directives>\n" .. xml_escape(task_prompt) .. "\n  </nzi:project_directives>");
  end

  -- 3. Add open buffer contents
  for _, item in ipairs(ctx_list) do
    local short_name = vim.fn.fnamemodify(item.name, ":.")
    table.insert(parts, string.format("  <nzi:file name=\"%s\" state=\"%s\">\n%s\n  </nzi:file>", 
      short_name, item.state, xml_escape(item.content)));
  end

  -- 4. Add LSP symbol definition if requested
  if include_lsp then
    local lsp_info = lsp.get_symbol_definition();
    if lsp_info then
      table.insert(parts, string.format("  <nzi:lsp_definition uri=\"%s\" line=\"%d\">\n%s\n  </nzi:lsp_definition>", 
        lsp_info.uri, lsp_info.line, xml_escape(lsp_info.content)));
    end
  end

  table.insert(parts, "</nzi:context>");
  return table.concat(parts, "\n");
end

--- Build the full prompt for a code modification directive
--- @param directive string: The user's instruction
--- @param target_file string: The name of the file being modified
--- @param prompts table: Global/Project prompts from gather()
--- @param context_str string: Formatted context from format_context()
--- @return string
function M.build_directive_prompt(directive, target_file, prompts, context_str)
  local model_alias = config.options.active_model or "AI";
  local parts = { M.build_system_prompt(prompts, model_alias) };
  
  -- 1. Conversational History
  local hist_str = history.format();
  if hist_str ~= "" then
    table.insert(parts, "\n" .. hist_str);
  end

  -- 2. Project Context
  table.insert(parts, "\n" .. context_str);
  
  table.insert(parts, "\n<nzi:user>");
  table.insert(parts, "Editing file: " .. target_file);
  table.insert(parts, "Instruction: " .. directive);
  table.insert(parts, "</nzi:user>");
  
  return table.concat(parts, "\n");
end

return M;
