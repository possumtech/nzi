local rpc = require("nzi.dom.rpc");
local config = require("nzi.core.config");
local M = {};

--- Add a turn to the session (Delegated to Python)
function M.add_turn(type, user_data, assistant_content, metadata)
  local next_id = M.get_next_id();
  local res = rpc.request_sync("add_turn", {
    id = next_id,
    mode = type,
    user_data = user_data,
    assistant = assistant_content,
    metadata = metadata
  });
  
  -- Trigger UI refresh
  require("nzi.ui.modal").render_history();
  return next_id;
end

M.add = M.add_turn;

--- Set the system prompt in the DOM
function M.set_system_prompt(content)
  rpc.request_sync("set_system_prompt", { content = content });
end

--- Update the workspace context in the DOM
function M.update_context(ctx_list, roadmap_content)
  rpc.request_sync("update_context", {
    ctx_list = ctx_list,
    roadmap_content = roadmap_content
  });
end

--- Helper for tests and legacy code to format context as XML
function M.format_context(ctx_list, skip_roadmap, roadmap_content, roadmap_file)
  -- This is a bit of a hack to satisfy legacy tests while keeping DOM as SSOT.
  -- It temporarily updates context and returns the XML of Turn 0.
  M.update_context(ctx_list, roadmap_content);
  local xml = M.xpath("//agent:turn[@id='0']/*");
  -- Strip namespaces for legacy test compatibility
  for i, line in ipairs(xml) do
    xml[i] = line:gsub(' xmlns:[%a]+="[^"]+"', ''):gsub(' xmlns="[^"]+"', '');
  end
  return table.concat(xml, "\n");
end

--- Generate the LLM message array from the DOM
function M.build_messages(system_prompt)
  local res = rpc.request_sync("build_messages", { system_prompt = system_prompt });
  return res.messages;
end

--- Format the entire session as a single XML document
function M.format()
  local res = rpc.request_sync("format", {});
  return res.xml;
end

--- Clear the session
function M.clear()
  rpc.request_sync("clear", {});
  require("nzi.ui.modal").render_history();
end

--- Execute an XPath query
function M.xpath(query)
  local res = rpc.request_sync("xpath", { query = query });
  return res.results or {};
end

--- Strip line numbers from text (e.g. "1: line" -> "line")
function M.strip_line_numbers(text)
  if not text then return "" end
  local lines = vim.split(text, "\n");
  for i, line in ipairs(lines) do
    lines[i] = line:gsub("^%s*%d+: ", "");
  end
  return table.concat(lines, "\n");
end

function M.get_next_id()
  local ids = M.xpath("//agent:turn/@id");
  local max = -1;
  for _, id in ipairs(ids) do
    local n = tonumber(id);
    if n and n > max then max = n; end
  end
  return max + 1;
end
--- Get all turns from the session (For UI/Summary)
function M.get_turn_count()
  local ids = M.xpath("count(//agent:turn)");
  return tonumber(ids[1]) or 0;
end

function M.get_all()
  local turns = {};
  local turn_xmls = M.xpath("//agent:turn");
  local parser = require("nzi.dom.parser");
  for _, tx in ipairs(turn_xmls) do
    local id = tonumber(parser.xpath(tx, "//agent:turn/@id")[1]);

    local user_nodes = parser.xpath(tx, "//agent:user/node()");
    local user = table.concat(user_nodes, "");

    local asst_nodes = parser.xpath(tx, "//model:* | //agent:content/node()");
    local assistant = table.concat(asst_nodes, "\n");

    table.insert(turns, {
      id = id,
      user = user,
      assistant = assistant, 
      metadata = {}
    });
  end
  return turns;
end


return M;
