local lsp = require("nzi.lsp");
local history = require("nzi.history");
local config = require("nzi.config");

local M = {};

--- Escape special characters for XML safety
local function xml_escape(text)
  if not text then return ""; end
  return text:gsub("&", "&amp;")
             :gsub("<", "&lt;")
             :gsub(">", "&gt;")
             :gsub("\"", "&quot;")
             :gsub("'", "&apos;")
end

--- Read a file's content safely
local function read_file(path)
  local expanded_path = vim.fn.expand(path);
  local f = io.open(expanded_path, "r");
  if not f then return nil; end
  local content = f:read("*all");
  f:close();
  return content;
end

--- Gather all relevant prompt components
function M.gather()
  local prompts = {};
  prompts.global = read_file("~/AGENTS.md");
  local project_ai = vim.fs.find(".ai.md", { upward = true, stop = vim.loop.os_homedir() })[1];
  if project_ai then prompts.project = read_file(project_ai); end
  local project_agents = vim.fs.find("AGENTS.md", { upward = true, stop = vim.loop.os_homedir() })[1];
  if project_agents then prompts.tasks = read_file(project_agents); end
  return prompts;
end

--- Build the "Rules of Behavior" (System Prompt)
function M.build_system_prompt(prompts, model_alias)
  local parts = { 
    string.format("You are %s, a Neovim-native agentic programming tool.", model_alias),
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
function M.format_context(ctx_list, include_lsp, task_prompt)
  table.sort(ctx_list, function(a, b) return a.name < b.name end);

  local parts = {};
  
  -- 1. Project Directives (AGENTS.md)
  if task_prompt then
    table.insert(parts, "<agent:project_directives>\n" .. xml_escape(task_prompt) .. "\n</agent:project_directives>");
  end

  -- 2. Open buffer contents
  for _, item in ipairs(ctx_list) do
    local short_name = vim.fn.fnamemodify(item.name, ":.")
    table.insert(parts, string.format("<agent:file name=\"%s\" state=\"%s\">\n%s\n</agent:file>", 
      short_name, item.state, xml_escape(item.content)));
  end

  -- 3. LSP info
  if include_lsp then
    local lsp_info = lsp.get_symbol_definition();
    if lsp_info then
      table.insert(parts, string.format("<agent:lsp_definition uri=\"%s\" line=\"%d\">\n%s\n</agent:lsp_definition>", 
        lsp_info.uri, lsp_info.line, xml_escape(lsp_info.content)));
    end
  end

  return table.concat(parts, "\n\n");
end

--- Build the full prompt for a code modification directive
function M.build_directive_prompt(directive, target_file, prompts, context_str)
  local model_alias = config.options.active_model or "AI";
  local system_str = M.build_system_prompt(prompts, model_alias);
  
  local messages = {
    { role = "system", content = system_str },
  };

  local history_msgs = history.get_as_messages();
  for _, m in ipairs(history_msgs) do table.insert(messages, m) end

  local user_content = string.format("<agent:context>\n%s\n</agent:context>\n\n<agent:user>\nEditing file: %s\nInstruction: %s\n</agent:user>",
    context_str, xml_escape(target_file), xml_escape(directive));

  table.insert(messages, { role = "user", content = user_content });
  return messages;
end

return M;
