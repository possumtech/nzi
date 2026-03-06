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
    "## TURN PROTOCOL",
    "Finalize every turn with exactly one of the following tags:",
    "* <model:summary>One sentence summary of actions taken</model:summary>",
    "* <model:choice>Text? - [ ] Option 1 - [ ] Option 2</model:choice>",
    "\n## MODEL ACTIONS",
    "Perform actions using these tags before the turn terminator:",
    "* <model:shell>Run destructive shell command</model:shell>",
    "* <model:env>Run read-only environment command</model:env>",
    "* <model:grep>Pattern</model:grep>",
    "* <model:definition>Symbol</model:definition>",
    "* <model:read file=\"path\" />: Pull file into context",
    "* <model:create file=\"path\">Full file content</model:create>",
    "* <model:edit file=\"path\">SEARCH/REPLACE blocks (MUST match full lines)</model:edit>",
    "* <model:reset />: Clear history",
    "\n## SEARCH/REPLACE FORMAT",
    "Modify files by wrapping SEARCH/REPLACE blocks inside <model:edit>.",
    "The tag MUST contain ONLY these blocks. Blocks MUST match the buffer exactly, including indentation:",
    "<<<<<<< SEARCH",
    "[exact lines from file]",
    "=======",
    "[new lines]",
    ">>>>>>> REPLACE",
    "\n* Multiple blocks are allowed in one <model:edit> tag.",
    "\n## AGENT METADATA (Input Only)",
    "* <agent:shell>shell output</agent:shell>",
    "* <agent:env>shell output</agent:env>",
    "* <agent:choice>selected option</agent:choice>",
    "* <agent:tool name=\"toolName\">tool output</agent:tool>",
    "* <agent:context>current project structure and files</agent:context>",
    "* <agent:file name=\"path/to/filename\">content of a specific file</agent:file>",
    "* <agent:project_state>AGENTS.md file contents</agent:project_state>",
    "* <agent:next_task_suggest>The first pending task in the plan</agent:next_task_suggest>",
    "* <agent:user>The user's specific instruction</agent:user>",
    "* <agent:selection file=\"path\" start=\"1:1\" end=\"1:5\">text</agent:selection>",
    "* <agent:grep><agent:match file=\"path\" line=\"10\">text</agent:match></agent:grep>",
    "* <agent:test>Output from a failing test or terminal execution</agent:test>",
    "\n* ALWAYS use relative paths from the project root for all file operations."
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
--- @param content string: The new user ask or instruct
--- @param type string: 'ask' or 'instruct'
--- @param target_file string | nil: Only for instruct
--- @param include_lsp boolean | nil
--- @param selection table | nil: Visual selection metadata
--- @return table, string, string, table, string
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
  local context_str = M.format_context(ctx_list, (type == "instruct"));
  table.insert(messages, { 
    role = role, 
    content = string.format("<agent:context>\n%s\n</agent:context>", context_str) 
  });
  
  -- 3. HISTORY (Alternating Turns)
  local history_msgs = history.get_as_messages();
  for _, m in ipairs(history_msgs) do table.insert(messages, m) end
  
  -- 4. NEW TURN (Specific Ask or Instruct)
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
    selection_block = string.format("<agent:selection file=\"%s\" start=\"%d:%d\" end=\"%d:%d\">\n%s\n</agent:selection>",
      selection.file, selection.start_line, selection.start_col, selection.end_line, selection.end_col, M.smart_filter(selection.text));
  end

  local turn_block = "";
  if type == "instruct" and target_file then
    if selection_block ~= "" then
      turn_block = string.format("<agent:user>\n%s Instruction: %s\nEditing file: %s\n</agent:user>",
        selection_block, M.smart_filter(content), M.smart_filter(target_file));
    else
      turn_block = string.format("<agent:user>\nEditing file: %s\nInstruction: %s\n</agent:user>",
        M.smart_filter(target_file), M.smart_filter(content));
    end
  else
    if selection_block ~= "" then
      turn_block = string.format("<agent:user>\n%s Instruction: %s\n</agent:user>", 
        selection_block, M.smart_filter(content));
    else
      turn_block = string.format("<agent:user>\n%s\n</agent:user>", 
        M.smart_filter(content));
    end
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
