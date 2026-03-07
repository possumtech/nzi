local lsp = require("nzi.tools.lsp");
local config = require("nzi.core.config");

local M = {};

--- Escape special characters only when they conflict with XML structure or namespaces
function M.smart_filter(text)
  if not text then return ""; end
  local filtered = text:gsub("&", "&amp;");
  filtered = filtered:gsub("<(/?%s*agent:[^>]*)>", "&lt;%1&gt;");
  filtered = filtered:gsub("<(/?%s*model:[^>]*)>", "&lt;%1&gt;");
  filtered = filtered:gsub("<([^%a/!])", "&lt;%1");
  return filtered;
end

--- Build the "Rules of Behavior" (System Prompt)
function M.build_system_prompt(prompts, model_alias)
  local prompt_file = config.options.prompt_file or "nzi.prompt";
  local project_path = vim.fn.getcwd() .. "/" .. prompt_file;
  
  local system_content = "";
  if vim.fn.filereadable(project_path) == 1 then
    system_content = table.concat(vim.fn.readfile(project_path), "\n");
  else
    system_content = [[You are an agent.

## INTERACTION MODES
* ask (AI?): READ-ONLY. You may use discovery tools (grep, read, env, definition) but MUST NOT use action tools (shell, edit, create, delete, choice). Use this for inquiry and analysis.
* instruct (AI:): ACTION-ORIENTED. You have full access to all tools to modify the codebase.

## TURN PROTOCOL
Finalize every turn with exactly one of the following tags:
* <model:summary>STRICTLY ONE LINE, UNDER 80 CHARS. The direct answer OR a summary of actions.</model:summary>
* <model:choice>Text? - [ ] Option 1 - [ ] Option 2</model:choice>

## MODEL ACTIONS
Perform actions using these tags before the turn terminator:
* <model:shell>Run destructive shell command</model:shell>
* <model:env>Run read-only environment command</model:env>
* <model:grep>Pattern</model:grep>
* <model:definition>Symbol</model:definition>
* <model:read file="path" />: Pull file into context
* <model:create file="path">Full file content</model:create>
* <model:edit file="path">SEARCH/REPLACE blocks (MUST match full lines)</model:edit>
* <model:reset />: Clear history

## SEARCH/REPLACE FORMAT
Modify files by wrapping SEARCH/REPLACE blocks inside <model:edit>.
The tag MUST contain ONLY these blocks. Blocks MUST match the buffer exactly, including indentation:
<model:edit>
<<<<<<< SEARCH
[exact lines from file]
=======
[new lines]
>>>>>>> REPLACE
</model:edit>

* Multiple blocks are allowed in one <model:edit> tag.

## AGENT NAMESPACE (Input Only)
* <agent:ack status="success" tool="...">Confirmation</agent:ack>
* <agent:status level="error">Error details</agent:status>
* <agent:context>Project skeleton or file content</agent:context>
* <agent:next_task_suggest file="...">Roadmap hint</agent:next_task_suggest>
* <agent:match file="path" line="10">grep result</agent:match>
* <agent:user>The human's instruction</agent:user>
* <agent:selection file="path" start="1:1" end="1:5">Visual selection text</agent:selection>

* ALWAYS use relative paths from the project root for all file operations.
]];
  end

  local parts = { system_content };
  if prompts.global then
    table.insert(parts, "\n### GLOBAL RULES\n" .. prompts.global);
  end
  return table.concat(parts, "\n");
end

--- Format gathered context into a readable string
function M.format_context(ctx_list, is_instruct, roadmap_content, roadmap_file)
  local dom_session = require("nzi.dom.session");
  return dom_session.format_context(ctx_list, is_instruct, roadmap_content, roadmap_file);
end

--- Gather prompt parts from roadmap file
function M.gather()
  local roadmap_file = config.options.roadmap_file or "AGENTS.md";
  local parts = { global = nil, roadmap_content = nil, next_task_suggest = nil };
  local project_path = vim.fn.getcwd() .. "/" .. roadmap_file;
  if vim.fn.filereadable(project_path) == 1 then
    local content = table.concat(vim.fn.readfile(project_path), "\n");
    parts.roadmap_content = content;
    for line in content:gmatch("[^\r\n]+") do
      local task = line:match("^%s*%- %[ %]%s*(.*)$")
      if task and task ~= "" then
        parts.next_task_suggest = task
        break
      end
    end
  end
  local global_path = vim.fn.expand("~/AGENTS.md");
  if vim.fn.filereadable(global_path) == 1 then
    parts.global = table.concat(vim.fn.readfile(global_path), "\n");
  end
  return parts;
end

--- Build the user block for a single turn
function M.build_user_block(content, target_file, selection)
  local roadmap_file = config.options.roadmap_file or "AGENTS.md";
  local prompt_parts = M.gather();
  
  local next_task_block = "";
  if prompt_parts.next_task_suggest then
    next_task_block = string.format("\n\n<agent:next_task_suggest file=\"%s\">\n%s\n</agent:next_task_suggest>", 
      roadmap_file, M.smart_filter(prompt_parts.next_task_suggest));
  end

  local user_block = content;
  if selection and selection.text and selection.text ~= "" then
     local s_line = selection.start_line or 0;
     local s_col = selection.start_col or 0;
     local e_line = selection.end_line or 0;
     local e_col = selection.end_col or 0;
     local s_file = selection.file or "unknown";

     local sel_xml = string.format("<agent:selection file=\"%s\" start=\"%d:%d\" end=\"%d:%d\">\n%s\n</agent:selection>",
       s_file, s_line, s_col, e_line, e_col, selection.text);
     user_block = sel_xml .. "\nInstruction: " .. content;
  end
  if target_file then
    user_block = "Target File: " .. target_file .. "\n" .. user_block;
  end

  return user_block .. next_task_block;
end

--- Build the full array of messages for the API from the DOM
function M.build_messages(content, mode, include_lsp, target_file, selection)
  local dom_session = require("nzi.dom.session");
  local watcher = require("nzi.service.vim.watcher");
  local model_alias = config.options.active_model or "deepseek";
  local roadmap_file = config.options.roadmap_file or "AGENTS.md";
  
  local prompt_parts = M.gather();
  local system_prompt = M.build_system_prompt(prompt_parts, model_alias);
  
  local ctx_list = watcher.sync_list() or {}; 
  local context_str = dom_session.format_context(ctx_list, true, prompt_parts.roadmap_content, roadmap_file);
  
  local messages = {
    { role = "system", content = system_prompt },
    { role = "system", content = string.format("<agent:context>\n%s\n</agent:context>", context_str) }
  };
  
  local turns = dom_session.get_all();
  for _, turn in ipairs(turns) do
    if turn.user and turn.user ~= "" then
      table.insert(messages, { role = "user", content = turn.user });
    end
    if turn.assistant and turn.assistant ~= "" then
      table.insert(messages, { role = "assistant", content = turn.assistant });
    end
  end

  if content and content ~= "" then
    local user_block = M.build_user_block(content, target_file, selection);
    table.insert(messages, { role = "user", content = user_block });
    return messages, system_prompt, context_str, ctx_list, user_block;
  end
  
  return messages, system_prompt, context_str, ctx_list;
end

return M;
