local config = require("nzi.core.config");
local M = {};

--- Build the "Rules of Behavior" (System Prompt)
function M.build_system_prompt(parts, model_alias)
  local prompt_file = config.options.prompt_file or "nzi.prompt";
  local project_path = vim.fn.getcwd() .. "/" .. prompt_file;
  
  local content = "";
  if vim.fn.filereadable(project_path) == 1 then
    content = table.concat(vim.fn.readfile(project_path), "\n");
  else
    content = [[You are an agent.
## TURN PROTOCOL
... (Default rules)
]];
  end

  if parts and parts.global then
    content = content .. "\n" .. parts.global;
  end
  return content;
end

--- Escape problematic XML characters in code blocks
function M.smart_filter(text)
  if not text then return "" end
  -- Aggressive escape for < to prevent XML confusion in prompts
  local escaped = text:gsub("<", "&lt;"):gsub(">", "&gt;");
  return escaped;
end

--- Gather raw prompt parts from roadmap file
function M.gather()
  local roadmap_file = config.options.roadmap_file or "AGENTS.md";
  local parts = { roadmap_content = nil, roadmap_hint = nil, next_task_suggest = nil };
  local project_path = vim.fn.getcwd() .. "/" .. roadmap_file;
  if vim.fn.filereadable(project_path) == 1 then
    local content = table.concat(vim.fn.readfile(project_path), "\n");
    parts.roadmap_content = content;
    for line in content:gmatch("[^\r\n]+") do
      local task = line:match("^%s*%- %[ %]%s*(.*)$")
      if task and task ~= "" then
        parts.roadmap_hint = task
        parts.next_task_suggest = task -- Compatibility
        break
      end
    end
  end
  return parts;
end

--- Build the full array of messages for the API from the DOM
function M.build_messages(instruction, mode, target_file, include_lsp, selection)
  local dom_session = require("nzi.dom.session");
  local watcher = require("nzi.service.vim.watcher");
  
  local system_prompt = M.build_system_prompt();
  local parts = M.gather();
  
  -- 1. Sync Workspace State to DOM
  local ctx_list = watcher.sync_list() or {}; 
  dom_session.update_context(ctx_list, parts.project or parts.roadmap_content);
  dom_session.set_system_prompt(system_prompt);
  
  -- 2. Build User Data object
  local user_data = nil;
  if instruction then
    user_data = {
      instruction = instruction,
      target_file = target_file,
      selection = selection,
      roadmap_hint = parts.next_task_suggest or parts.roadmap_hint
    };
  end

  -- 3. Engine builds the message array from the tree
  local messages = dom_session.build_messages();
  
  -- Return extra parts for legacy test compatibility
  local turn_block = "";
  if user_data then
    turn_block = M.build_user_block(instruction, target_file or include_lsp, selection);
  end

  return messages, system_prompt, nil, ctx_list, turn_block;
end

function M.build_user_block(instruction, target_file, selection)
  local parts = M.gather();
  local block = "";
  if type(target_file) == "string" and target_file ~= "" then 
    block = block .. "Target File: " .. target_file .. "\n"; 
  end
  
  if selection then
    block = block .. string.format("<agent:selection file=\"%s\" start=\"%d:%d\" end=\"%d:%d\">",
      selection.file or "unknown", selection.start_line or 0, selection.start_col or 0,
      selection.end_line or 0, selection.end_col or 0);
    block = block .. selection.text .. "</agent:selection>\n";
  end
  
  block = block .. "Instruction: " .. instruction;
  
  if parts.roadmap_hint then
    block = block .. "\n<agent:next_task_suggest file=\"AGENTS.md\">" .. parts.roadmap_hint .. "</agent:next_task_suggest>";
  end
  return block;
end

return M;
