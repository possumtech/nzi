local lsp = require("nzi.tools.lsp");
local history = require("nzi.context.history");
local config = require("nzi.core.config");

local M = {};

--- Escape special characters only when they conflict with XML structure or namespaces
function M.smart_filter(text)
  if not text then return ""; end
  -- 1. Escape the escape character first
  local filtered = text:gsub("&", "&amp;");
  
  -- 2. Escape only our reserved namespaces (agent: and model:)
  -- This prevents file content from closing our tags or issuing fake commands
  -- Match both opening, closing, and self-closing tags: <agent:foo>, </agent:foo>, <agent:foo />
  filtered = filtered:gsub("<(/?%s*agent:[^>]*)>", "&lt;%1&gt;");
  filtered = filtered:gsub("<(/?%s*model:[^>]*)>", "&lt;%1&gt;");
  
  -- 3. Escape lone angle brackets that aren't part of a tag (e.g. "if a < b")
  -- Heuristic: if < is followed by a space or non-alphanumeric (except / or !), it's likely raw text
  filtered = filtered:gsub("<([^%a/!])", "&lt;%1");
  
  return filtered;
end

--- Build the "Rules of Behavior" (System Prompt)
function M.build_system_prompt(prompts, model_alias)
  local identity = string.format("You are %s, an agent.", model_alias);

  local parts = { 
    identity,
    "\n## SCHEMA",
    "XML tags provide structure. Use these tags for internal processing and actions:",
    "* <model:shell>run_destructive_shell_command</model:shell>",
    "* <model:env>run_read_only_shell_command</model:env>",
    "* <model:grep>findThisText</model:grep>: Search the project for a pattern.",
    "* <model:definition>symbolName</model:definition>: Find the LSP definition of a symbol.",
    "* <model:choice>Question text here? - [ ] Option 1 - [ ] Option 2</model:choice>: Present a multiple-choice question.",
    "* <model:tool name=\"toolName\">Message to tool</model:tool>: Invoke specialized plugin tools.",
    "* <model:read file=\"path/to/filename\" />: Pull a file into active context and open it as a buffer.",
    "* <model:drop file=\"path/to/filename\" />: Remove a file from active context.",
    "* <model:delete file=\"path/to/filename\" />: Delete a file from the project.",
    "* <model:reset />: Reset session history and context.",
    "* <model:create file=\"path/to/filename\">[full file content]</model:create>: Create a new file.",
    "* <model:edit file=\"path/to/filename\">SEARCH/REPLACE Blocks</model:edit>: Modify code.",
    "\n## SEARCH/REPLACE FORMAT",
    "To modify a file, wrap SEARCH/REPLACE blocks inside a <model:edit> tag:",
    "SEARCH blocks support Lua patterns (regex). Use them if exact content or whitespace is unknown.",
    "Multiple blocks are allowed in one <model:edit> tag. They are applied sequentially.",
    "<model:edit file=\"path/to/filename\">",
    "<<<<<<< SEARCH",
    "[lines from file]",
    "=======",
    "[new lines]",
    ">>>>>>> REPLACE",
    "</model:edit>",
    "\n## AGENT TAGS (Input Only)",
    "* <agent:shell>shell output</agent:shell>",
    "* <agent:env>shell output</agent:env>",
    "* <agent:grep>filename:line:text</agent:grep>",
    "* <agent:choice>selected option</agent:choice>",
    "* <agent:tool name=\"toolName\">tool output</agent:tool>",
    "* <agent:context>current project structure and files</agent:context>",
    "* <agent:file name=\"path/to/filename\">content of a specific file</agent:file>",
    "* <agent:project_state>AGENTS.md file contents</agent:project_state>",
    "* <agent:next_task_suggest>The first pending task in the plan</agent:next_task_suggest>",
    "* <agent:user>The user's specific instruction</agent:user>",
    "* <agent:selection file=\"path\" start=\"1:1\" end=\"1:5\" mode=\"ask\">text</agent:selection>",
    "* <agent:test>Output from a failing test or terminal execution</agent:test>",
    "\n## CONSTRAINTS",
    "* Interaction Modes: Instruct (:), Ask (?), Run (!), Internal (/)",
    "* ALWAYS <model:read /> a file before issuing a <model:edit /> to ensure you have the latest content.",
    "* Use the smallest possible edits. Sequential blocks are preferred over one giant block.",
    "* To provide an example of a tag without triggering an action, wrap it in markdown backticks (e.g. ` <model:read /> `).",
    "* Discovery: Use <model:env> (ls -R, git status, etc.), <model:grep />, and <model:read /> to gather facts before acting.",
    "* NEVER output <agent:*> tags.",
    "* NEVER repeat prompt, history, or context content.",
    "* ALWAYS use relative paths from the project root for all file operations."
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
      
      -- ONLY send content for active or read states. 
      -- 'map' state should be a collapsed tag (skeleton logic removed from context transmission)
      if (item.state == "active" or item.state == "read") and item.content and item.content ~= "" then
        table.insert(parts, string.format("<agent:file name=\"%s\" state=\"%s\" size=\"%s\">\n%s\n</agent:file>", 
          short_name, item.state, size_str, M.smart_filter(item.content)));
      else
        -- Collapsed (mapped file or ignored)
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
        lsp_info.uri, lsp_info.line, M.smart_filter(lsp_info.content)));
    end
  end

  return table.concat(parts, "\n\n");
end

--- Build the full array of messages for the API
--- @param content string: The new user question or directive
--- @param type string: 'question' or 'directive'
--- @param target_file string | nil: Only for directives
--- @param include_lsp boolean | nil
--- @param selection table | nil: Visual selection metadata
--- @return table: Array of { role = string, content = string }
function M.build_messages(content, type, target_file, include_lsp, selection)
  local config = require("nzi.core.config");
  local model_alias = config.options.active_model or "deepseek";
  local model_cfg = config.get_active_model();
  local role = model_cfg.role_preference or "system";
  
  local ctx_list = require("nzi.context.context").gather();
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
    state_block = string.format("<agent:project_state>\n%s\n</agent:project_state>", M.smart_filter(prompt_parts.project));
  end

  local next_task_block = "";
  if prompt_parts.next_task_suggest then
    next_task_block = string.format("\n\n<agent:next_task_suggest>\n%s\n</agent:next_task_suggest>", M.smart_filter(prompt_parts.next_task_suggest));
  end

  local selection_block = "";
  if selection then
    local mode = selection.mode;
    if type == "question" then mode = "ask"; end
    if type == "directive" then mode = "edit"; end

    selection_block = string.format("\n\n<agent:selection file=\"%s\" start=\"%d:%d\" end=\"%d:%d\" mode=\"%s\">\n%s\n</agent:selection>",
      selection.file, selection.start_line, selection.start_col, selection.end_line, selection.end_col, mode, M.smart_filter(selection.text));
  end

  local turn_block = "";
  if type == "directive" and target_file then
    turn_block = string.format("<agent:user>\nEditing file: %s\nInstruction: %s%s\n</agent:user>",
      M.smart_filter(target_file), M.smart_filter(content), selection_block);
  else
    turn_block = string.format("<agent:user>\n%s%s\n</agent:user>", 
      M.smart_filter(content), selection_block);
  end

  local final_user_content = string.format("%s%s\n\n%s", state_block, next_task_block, turn_block);
  
  table.insert(messages, { role = "user", content = final_user_content });
  
  return messages, system_prompt, context_str, ctx_list, turn_block;
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
    -- Anchor to start of line for reliability
    for line in content:gmatch("[^\r\n]+") do
      local task = line:match("^%s*%- %[ %]%s*(.*)$")
      if task and task ~= "" then
        parts.next_task_suggest = task
        break
      end
    end
  end
  
  -- 2. Global level (optional ~/AGENTS.md)
  local global_path = vim.fn.expand("~/AGENTS.md");
  if vim.fn.filereadable(global_path) == 1 then
    parts.global = table.concat(vim.fn.readfile(global_path), "\n");
  end
  
  return parts;
end

return M;
