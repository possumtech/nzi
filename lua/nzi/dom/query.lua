local protocol = require("nzi.dom.parser");
local session = require("nzi.dom.session");
local M = {};

--- Execute an XPath query on the current session DOM
--- @param xpath_expr string
--- @return table: List of results
function M.xpath(xpath_expr)
  local xml = session.format();
  return protocol.xpath(xml, xpath_expr);
end

--- Check if the engine is currently blocked by an unresolved interaction
--- @return boolean
function M.is_blocked()
  local xml = session.format();
  
  -- Find all blocking elements
  local blocking_query = "//model:edit | //model:create | //model:delete | //model:choice";
  local blockers = protocol.xpath(xml, blocking_query);
  if #blockers == 0 then return false; end

  -- Find all resolving elements
  local resolving_query = "//agent:ack | //agent:choice | //agent:status[@status='denied']";
  local resolvers = protocol.xpath(xml, resolving_query);

  -- If we have more blockers than resolvers, we are blocked.
  return #blockers > #resolvers;
end

--- Get all pending actions from the XML
--- @return table: { edits = table, creations = table, deletions = table }
function M.get_pending_actions()
  local xml = session.format();
  
  local edits = protocol.xpath(xml, "//model:edit | //model:replace_all");
  local creations = protocol.xpath(xml, "//model:create");
  local deletions = protocol.xpath(xml, "//model:delete");
  
  local acks = protocol.xpath(xml, "//agent:ack");
  local rejections = protocol.xpath(xml, "//agent:status[@status='denied']");
  
  local all_actions = {};
  for _, e in ipairs(edits) do table.insert(all_actions, { type = "edit", xml = e, file = protocol.get_attr(e, "file") }) end
  for _, c in ipairs(creations) do table.insert(all_actions, { type = "create", xml = c, file = protocol.get_attr(c, "file") }) end
  for _, d in ipairs(deletions) do table.insert(all_actions, { type = "delete", xml = d, file = protocol.get_attr(d, "file") }) end
  
  local all_resolutions = {};
  for _, a in ipairs(acks) do table.insert(all_resolutions, { type = "ack", xml = a, file = protocol.get_attr(a, "file") }) end
  for _, r in ipairs(rejections) do table.insert(all_resolutions, { type = "rej", xml = r, file = protocol.get_attr(r, "file") }) end
  
  local resolved_indices = {};
  for _, res in ipairs(all_resolutions) do
    for i, act in ipairs(all_actions) do
      if not resolved_indices[i] then
        local file_match = (not res.file or not act.file or res.file == act.file);
        if file_match then
          resolved_indices[i] = true;
          break;
        end
      end
    end
  end
  
  local pending = { edits = {}, creations = {}, deletions = {} };
  for i, act in ipairs(all_actions) do
    if not resolved_indices[i] then
      if act.type == "edit" then table.insert(pending.edits, act.xml)
      elseif act.type == "create" then table.insert(pending.creations, act.xml)
      elseif act.type == "delete" then table.insert(pending.deletions, act.xml)
      end
    end
  end
  
  return pending;
end

return M;
