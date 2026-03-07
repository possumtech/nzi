local config = require("nzi.core.config");
local M = {};

-- Internal storage of turns
M.turns = {};
local next_id = 0;

--- Escape special characters for XML safety
function M.xml_escape(text)
  if not text then return ""; end
  return text:gsub("&", "&amp;")
             :gsub("<", "&lt;")
             :gsub(">", "&gt;")
             :gsub("\"", "&quot;")
             :gsub("'", "&apos;")
end

--- Format gathered context into a readable string
function M.format_context(ctx_list, is_instruct, roadmap_content, roadmap_file)
  local config = require("nzi.core.config");
  roadmap_file = roadmap_file or config.options.roadmap_file or "AGENTS.md";
  ctx_list = ctx_list or {};
  table.sort(ctx_list, function(a, b) return a.name < b.name end);

  local parts = {};
  if roadmap_content and roadmap_content ~= "" then
    table.insert(parts, string.format("<agent:project_roadmap file=\"%s\">\n%s\n</agent:project_roadmap>", 
      roadmap_file, M.xml_escape(roadmap_content)));
  end

  for _, item in ipairs(ctx_list) do
    local short_name = item.name;
    -- Simple skip logic: if the name contains the roadmap filename, skip it
    local escaped_roadmap = roadmap_file:gsub("%.", "%%.");
    if not short_name:match(escaped_roadmap .. "$") then
      local size_str = string.format("%d bytes", item.size or 0)
      if (item.state == "active" or item.state == "read") and item.content and item.content ~= "" then
        table.insert(parts, string.format("<agent:file name=\"%s\" state=\"%s\" size=\"%s\">\n%s\n</agent:file>", 
          short_name, item.state, size_str, M.xml_escape(item.content)));
      else
        table.insert(parts, string.format("<agent:file name=\"%s\" state=\"%s\" size=\"%s\" />", 
          short_name, item.state, size_str));
      end
    end
  end

  if is_instruct then
    local lsp = require("nzi.tools.lsp");
    local lsp_info = lsp.get_symbol_definition();
    if lsp_info then
      table.insert(parts, string.format("<agent:lsp_definition uri=\"%s\" line=\"%d\">\n%s\n</agent:lsp_definition>", 
        lsp_info.uri, lsp_info.line, M.xml_escape(lsp_info.content)));
    end
  end

  return table.concat(parts, "\n\n");
end

--- Get the current session header with live attributes
function M.get_header()
  local model = config.options.active_model or "unknown";
  local yolo = config.options.yolo and "true" or "false";
  local roadmap = config.options.roadmap_file or "AGENTS.md";
  
  return string.format("<session xmlns:nzi=\"nzi\" xmlns:agent=\"nzi\" xmlns:model=\"nzi\" model=\"%s\" yolo=\"%s\" roadmap=\"%s\">", 
    model, yolo, roadmap);
end

--- Format text with line numbers (skips if structured)
local function add_line_numbers(text)
  if not text then return nil; end
  -- Skip line numbering for ANY structured XML turn
  if text:match("^<agent:") or text:match("^<model:") or text:match("^%d+: ") then return text; end
  
  local lines = vim.split(text, "\n");
  local output = {};
  for i, line in ipairs(lines) do
    table.insert(output, string.format("%d: %s", i, line));
  end
  return table.concat(output, "\n");
end

--- Remove line numbers from text (only if it was numbered by us)
function M.strip_line_numbers(text)
  if not text or text == "" then return ""; end
  -- If it's structured XML, don't touch it
  if text:match("^<agent:") or text:match("^<model:") then return text; end
  
  local lines = vim.split(text, "\n");
  local output = {};
  for _, line in ipairs(lines) do
    local clean = line:gsub("^%d+: ", "", 1);
    table.insert(output, clean);
  end
  return table.concat(output, "\n");
end

--- Add a turn to the session
--- @param type string: 'ask', 'instruct', etc.
--- @param user_content string: User instruction/context
--- @param assistant_content string|nil: Model response (tags)
--- @param metadata table|nil: Turn metadata
function M.add_turn(type, user_content, assistant_content, metadata)
  local id = next_id;
  next_id = next_id + 1;
  
  table.insert(M.turns, {
    id = id,
    type = type,
    user = add_line_numbers(user_content),
    assistant = add_line_numbers(assistant_content),
    metadata = metadata or {}
  });
  
  -- Trigger UI refresh (Projection)
  require("nzi.ui.modal").render_history();
  return id;
end

M.add = M.add_turn;

--- Format the entire session as a single XML document
--- @return string
function M.format()
  local header = M.get_header();
  if #M.turns == 0 then 
    return header .. "\n</session>";
  end

  local parts = { header };
  for _, turn in ipairs(M.turns) do
    local user_clean = M.strip_line_numbers(turn.user);
    local assistant_clean = M.strip_line_numbers(turn.assistant);
    
    local meta = string.format(" id=\"%d\" model=\"%s\" duration=\"%.2f\" acts=\"%d\"", 
      turn.id, turn.metadata.model or "unknown", turn.metadata.duration or 0, turn.metadata.changes or 0);

    local turn_xml = string.format("<agent:turn%s>", meta);
    
    if user_clean ~= "" then
      local user_val = user_clean;
      -- Only escape if NOT already protocol tags
      if not (user_val:match("^%s*<agent:") or user_val:match("^%s*<model:")) then
        user_val = M.xml_escape(user_val);
      end
      turn_xml = turn_xml .. string.format("\n<agent:user>\n%s\n</agent:user>", user_val);
    end
    
    if assistant_clean ~= "" then
      local assistant_val = assistant_clean;
      -- If it doesn't start with a tag, escape it all
      if not assistant_val:match("^%s*<") then
        assistant_val = M.xml_escape(assistant_val);
      else
        -- This is a mix of tags and potentially unescaped text.
        -- Truly robust way would be to use the bridge to rebuild it,
        -- but for now let's at least ensure it's wrapped or handled.
        -- (Ideally LLM output parsing should have handled this)
      end
      turn_xml = turn_xml .. "\n" .. assistant_val;
    end
    
    turn_xml = turn_xml .. "\n</agent:turn>";
    table.insert(parts, turn_xml);
  end
  
  table.insert(parts, "</session>");
  return table.concat(parts, "\n\n");
end

--- Clear the session
function M.clear()
  M.turns = {};
  next_id = 0;
  require("nzi.ui.modal").render_history();
end

--- Delete turns after a specific ID (Rewind)
function M.delete_after(id)
  local found_idx = -1;
  for i, turn in ipairs(M.turns) do
    if turn.id == id then
      found_idx = i;
      break;
    end
  end
  
  if found_idx ~= -1 then
    local to_remove = #M.turns - found_idx + 1;
    for _ = 1, to_remove do
      table.remove(M.turns, found_idx);
    end
    next_id = (#M.turns > 0) and (M.turns[#M.turns].id + 1) or 0;
    require("nzi.ui.modal").render_history();
    return true;
  end
  return false;
end

function M.get_next_id() return next_id; end
function M.get_all() return M.turns; end

--- Hydrate the session state from an XML string
--- @param xml_str string
function M.hydrate(xml_str)
  local protocol = require("nzi.dom.parser");
  
  -- 1. Reset current state
  M.turns = {};
  next_id = 0;

  -- 2. Extract Global Attributes using XPath
  local model = protocol.xpath(xml_str, "/nzi:session/@model")[1];
  local yolo = protocol.xpath(xml_str, "/nzi:session/@yolo")[1];
  local roadmap = protocol.xpath(xml_str, "/nzi:session/@roadmap")[1];
  
  if model then config.options.active_model = model; end
  if yolo then config.options.yolo = (yolo == "true"); end
  if roadmap then config.options.roadmap_file = roadmap; end

  -- 3. Extract Turns
  local turn_xmls = protocol.xpath(xml_str, "//agent:turn");
  
  for _, tx in ipairs(turn_xmls) do
    local tid = tonumber(protocol.xpath(tx, "/agent:turn/@id")[1]) or next_id;
    local t_model = protocol.xpath(tx, "/agent:turn/@model")[1];
    local t_duration = tonumber(protocol.xpath(tx, "/agent:turn/@duration")[1]) or 0;
    local t_acts = tonumber(protocol.xpath(tx, "/agent:turn/@acts")[1]) or 0;

    local user_content = "";
    local user_nodes = protocol.xpath(tx, "/agent:turn/agent:user");
    if #user_nodes > 0 then
      -- Get text content from user node
      user_content = protocol.xpath(tx, "/agent:turn/agent:user/text()")[1] or "";
      -- Trim leading/trailing whitespace which lxml might preserve
      user_content = user_content:gsub("^%s*", ""):gsub("%s*$", "");
    end

    local assistant_content = "";
    -- Assistant content is everything AFTER the user node inside the turn
    local assistant_nodes = protocol.xpath(tx, "/agent:turn/agent:user/following-sibling::node()");
    local assistant_parts = {};
    for _, node in ipairs(assistant_nodes) do
      table.insert(assistant_parts, node);
    end
    assistant_content = table.concat(assistant_parts, "");
    -- Trim leading/trailing whitespace which might be artifacts of formatting
    assistant_content = assistant_content:gsub("^%s*", ""):gsub("%s*$", "");

    table.insert(M.turns, {
      id = tid,
      user = user_content,
      assistant = assistant_content,
      metadata = {
        model = t_model,
        duration = t_duration,
        changes = t_acts
      }
    });
    if tid >= next_id then next_id = tid + 1; end
  end

  require("nzi.ui.modal").render_history();
  return true;
end

return M;
