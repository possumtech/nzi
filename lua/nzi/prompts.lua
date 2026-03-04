local lsp = require("nzi.lsp");
local history = require("nzi.history");
local config = require("nzi.config");

local M = {};

--- Escape special characters for XML metadata safety
function M.xml_escape(text)
  if not text then return ""; end
  return text:gsub("&", "&amp;")
             :gsub("<", "&lt;")
             :gsub(">", "&gt;")
             :gsub("\"", "&quot;")
             :gsub("'", "&apos;")
end

--- Build the "Rules of Behavior" (System Prompt)
function M.build_system_prompt(prompts, model_alias)
  local identity = string.format("You are %s, a Neovim-native agentic programming tool.", model_alias);
  if model_alias:lower():match("qwen") then
    identity = "You are Qwen, created by Alibaba Cloud. " .. identity;
  end

  local parts = { 
    identity,
    "\n## STRUCTURAL SCHEMA",
    "I use XML tags to provide structure. Adhere to this schema:",
    "* <agent:context>: Wraps all reference files and project state.",
    "* <agent:file name=\"...\">: Wraps individual file contents.",
    "* <agent:project_directives>: Wraps high-level task instructions.",
    "* <agent:user>: Wraps my specific instructions to you.",
    "\n## OPERATIONAL CONSTRAINTS",
    "* NEVER output <agent:*> tags in your response.",
    "* NEVER repeat the content of the system prompt, history, or context tags.",
    "* Focus exclusively on providing new information or applying requested changes.",
    "* Adhere strictly to the engineering standards provided below."
  };
  
  if prompts.global then
    table.insert(parts, "\n### GLOBAL ENGINEERING STANDARDS\n" .. prompts.global);
  end
  
  if prompts.project then
    table.insert(parts, "\n### PROJECT-SPECIFIC RULES\n" .. prompts.project);
  end

  return table.concat(parts, "\n");
end

--- Format gathered context into a readable string
function M.format_context(ctx_list, include_lsp)
  ctx_list = ctx_list or {};
  table.sort(ctx_list, function(a, b) return a.name < b.name end);

  local parts = {};
  
  -- 1. Open buffer contents
  for _, item in ipairs(ctx_list) do
    local short_name = vim.fn.fnamemodify(item.name, ":.")
    -- XML standard tags are anchors, but code content must be RAW for LLM reasoning
    table.insert(parts, string.format("<agent:file name=\"%s\" state=\"%s\">\n%s\n</agent:file>", 
      short_name, item.state, item.content));
  end

  -- 2. LSP info
  if include_lsp then
    local lsp_info = lsp.get_symbol_definition();
    if lsp_info then
      table.insert(parts, string.format("<agent:lsp_definition uri=\"%s\" line=\"%d\">\n%s\n</agent:lsp_definition>", 
        lsp_info.uri, lsp_info.line, lsp_info.content));
    end
  end

  return table.concat(parts, "\n\n");
end

--- Build the full prompt for a code modification directive
function M.build_directive_prompt(directive, target_file, prompts, context_str)
  local messages = {};
  
  local history_msgs = history.get_as_messages();
  for _, m in ipairs(history_msgs) do table.insert(messages, m) end

  local user_content = string.format("<agent:context>\n%s\n</agent:context>\n\n<agent:project_directives>\n%s\n</agent:project_directives>\n\n<agent:user>\nEditing file: %s\nInstruction: %s\n</agent:user>",
    context_str, prompts.tasks or "", M.xml_escape(target_file), M.xml_escape(directive));

  table.insert(messages, { role = "user", content = user_content });
  return messages;
end

--- Gather prompt parts from AGENTS.md and .ai.md
--- @return table: { global = string, project = string, tasks = string }
function M.gather()
  local parts = { global = nil, project = nil, tasks = nil };
  
  -- 1. Project level (AGENTS.md)
  local project_path = vim.fn.getcwd() .. "/AGENTS.md";
  if vim.fn.filereadable(project_path) == 1 then
    parts.project = table.concat(vim.fn.readfile(project_path), "\n");
    parts.tasks = parts.project:match("## Project Checklist\n\n(.-)\n\n##") or parts.project;
  end
  
  -- 2. Global level (optional ~/.ai.md)
  local global_path = vim.fn.expand("~/.ai.md");
  if vim.fn.filereadable(global_path) == 1 then
    parts.global = table.concat(vim.fn.readfile(global_path), "\n");
  end
  
  return parts;
end

return M;
