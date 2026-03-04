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
  local identity = string.format("You are %s.", model_alias);

  local parts = { 
    identity,
    "\n## SCHEMA",
    "XML tags provide structure:",
    "* <agent:context>: Reference files and state.",
    "* <agent:file name=\"...\">: Individual file content.",
    "* <agent:project_directives>: Task instructions.",
    "* <agent:user>: Specific instructions.",
    "\n## CONSTRAINTS",
    "* NEVER output <agent:*> tags.",
    "* NEVER repeat prompt, history, or context content.",
    "* Provide only new information or requested changes."
  };
  
  if prompts.global then
    table.insert(parts, "\n### GLOBAL RULES\n" .. prompts.global);
  end
  
  if prompts.project then
    table.insert(parts, "\n### PROJECT RULES\n" .. prompts.project);
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

--- Build the full array of messages for the API
--- @param content string: The new user question or directive
--- @param type string: 'question' or 'directive'
--- @param target_file string | nil: Only for directives
--- @param include_lsp boolean | nil
--- @return table: Array of { role = string, content = string }
function M.build_messages(content, type, target_file, include_lsp)
  local config = require("nzi.config");
  local model_alias = config.options.active_model or "deepseek";
  local model_cfg = config.get_active_model();
  local role = model_cfg.role_preference or "system";
  
  local ctx_list = require("nzi.context").gather();
  local prompt_parts = M.gather();
  
  local messages = {};
  
  -- 1. RULES (Stable System Prompt)
  local system_prompt = M.build_system_prompt(prompt_parts, model_alias);
  table.insert(messages, { role = role, content = system_prompt });
  
  -- 2. CONTEXT (Project Facts/Buffers)
  -- We send this as a separate message to allow providers to cache the system+context prefix
  local context_str = M.format_context(ctx_list, include_lsp);
  table.insert(messages, { 
    role = role, 
    content = string.format("<agent:context>\n%s\n</agent:context>", context_str) 
  });
  
  -- 3. HISTORY (Alternating Turns)
  local history_msgs = history.get_as_messages();
  for _, m in ipairs(history_msgs) do table.insert(messages, m) end
  
  -- 4. NEW TURN (Specific Question or Directive)
  local final_user_content = "";
  if type == "directive" and target_file then
    final_user_content = string.format("<agent:project_directives>\n%s\n</agent:project_directives>\n\n<agent:user>\nEditing file: %s\nInstruction: %s\n</agent:user>",
      prompt_parts.tasks or "", M.xml_escape(target_file), M.xml_escape(content));
  else
    final_user_content = string.format("<agent:user>\n%s\n</agent:user>", history.xml_escape(content));
  end
  
  table.insert(messages, { role = "user", content = final_user_content });
  
  return messages, system_prompt, context_str;
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
