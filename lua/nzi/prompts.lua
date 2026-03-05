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
    "* <agent:context>: Reference files and project structure.",
    "* <agent:file name=\"...\">: Individual file content.",
    "* <agent:project_state>: Persistent plan, checklists, and requirements.",
    "* <agent:next_task_suggest>: The first pending task identified in the project plan. Use this as a suggestion for future work, but do not let it override the user instruction.",
    "* <agent:user>: The specific instruction for this turn. ALWAYS prioritize this over the plan.",
    "\n## CONSTRAINTS",
    "* NEVER output <agent:*> tags.",
    "* NEVER repeat prompt, history, or context content.",
    "* Provide only new information or requested changes."
  };
  
  if prompts.global then
    table.insert(parts, "\n### GLOBAL RULES\n" .. prompts.global);
  end

  return table.concat(parts, "\n");
end

--- Format gathered context into a readable string
function M.format_context(ctx_list, include_lsp)
  ctx_list = ctx_list or {};
  table.sort(ctx_list, function(a, b) return a.name < b.name end);

  local parts = {};
  
  -- 1. Universe Files (Open buffers and mapped project files)
  for _, item in ipairs(ctx_list) do
    local short_name = vim.fn.fnamemodify(item.name, ":.")
    
    -- Skip AGENTS.md as it is sent as project_state
    if short_name ~= "AGENTS.md" then
      local size_str = string.format("%d bytes", item.size or 0)
      
      if item.content and item.content ~= "" then
        -- Full content (active/read) or Skeleton (map)
        table.insert(parts, string.format("<agent:file name=\"%s\" state=\"%s\" size=\"%s\">\n%s\n</agent:file>", 
          short_name, item.state, size_str, item.content));
      else
        -- Collapsed (mapped file with no metadata)
        table.insert(parts, string.format("<agent:file name=\"%s\" state=\"%s\" size=\"%s\" />", 
          short_name, item.state, size_str));
      end
    end
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
  local state_block = "";
  if prompt_parts.project then
    state_block = string.format("<agent:project_state>\n%s\n</agent:project_state>", prompt_parts.project);
  end

  local next_task_block = "";
  if prompt_parts.next_task_suggest then
    next_task_block = string.format("\n\n<agent:next_task_suggest>\n%s\n</agent:next_task_suggest>", prompt_parts.next_task_suggest);
  end

  local final_user_content = "";
  if type == "directive" and target_file then
    final_user_content = string.format("%s%s\n\n<agent:user>\nEditing file: %s\nInstruction: %s\n</agent:user>",
      state_block, next_task_block, M.xml_escape(target_file), M.xml_escape(content));
  else
    final_user_content = string.format("%s%s\n\n<agent:user>\n%s\n</agent:user>", 
      state_block, next_task_block, history.xml_escape(content));
  end
  
  table.insert(messages, { role = "user", content = final_user_content });
  
  return messages, system_prompt, context_str, ctx_list;
end

--- Gather prompt parts from AGENTS.md
--- @return table: { global = string, project = string, next_task_suggest = string }
function M.gather()
  local parts = { global = nil, project = nil, next_task_suggest = nil };
  
  -- 1. Project level (./AGENTS.md)
  -- This is the "Living Document" that guides the agent.
  local project_path = vim.fn.getcwd() .. "/AGENTS.md";
  if vim.fn.filereadable(project_path) == 1 then
    local content = table.concat(vim.fn.readfile(project_path), "\n");
    parts.project = content;
    
    -- Extract first unchecked task: - [ ] Task Name
    parts.next_task_suggest = content:match("%- %[ %]%s*(.-)\r?\n") or content:match("%- %[ %]%s*(.*)$");
  end
  
  -- 2. Global level (optional ~/AGENTS.md)
  local global_path = vim.fn.expand("~/AGENTS.md");
  if vim.fn.filereadable(global_path) == 1 then
    parts.global = table.concat(vim.fn.readfile(global_path), "\n");
  end
  
  return parts;
end

return M;
