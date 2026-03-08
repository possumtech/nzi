local rpc = require("nzi.dom.rpc");
local M = {};

-- Local read-only cache of the current XML session string
-- Updated by update_context and other state-changing methods
M.cache_xml = "";

--- Update the cache from an RPC response
local function update_cache(res)
  if res and res.xml then
    M.cache_xml = res.xml;
  end
  return res;
end

--- Synchronize buffer context to the Python DOM
function M.update_context(ctx_list, roadmap_content)
  local res = rpc.request_sync("update_context", {
    ctx_list = ctx_list,
    roadmap_content = roadmap_content
  });
  return update_cache(res);
end

--- Clear the session in the Python DOM
function M.clear()
  local res = rpc.request_sync("clear", {});
  M.cache_xml = ""; -- Clear local cache
  return update_cache(res);
end

--- Execute an XPath query against the Python DOM
function M.xpath(query)
  local res = rpc.request_sync("xpath", { query = query });
  return res.results or {};
end

--- Get the current XML session dump (from local cache if possible)
function M.format()
  if M.cache_xml ~= "" then return M.cache_xml end
  local res = rpc.request_sync("format", {});
  M.cache_xml = res.xml or "";
  return M.cache_xml;
end

--- Load an XML session into the Python DOM
function M.hydrate(xml_str)
  local res = rpc.request_sync("hydrate", { xml_str = xml_str });
  if res.success then M.cache_xml = xml_str end
  return res;
end

--- Delete a turn and all subsequent turns
function M.delete_after(turn_id)
  local res = rpc.request_sync("delete_after", { turn_id = turn_id });
  return update_cache(res);
end

-- Force a cache refresh from Python
function M.refresh_cache()
  M.cache_xml = "";
  return M.format();
end

return M;
