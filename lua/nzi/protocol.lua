local M = {};

--- Simple state-machine parser for <model:*> tags
--- This handles tags being split across chunks in the stream.
function M.create_parser()
  return {
    buffer = "",
    actions = {},
    
    --- Feed a new chunk of text into the parser
    --- @param chunk string
    feed = function(self, chunk)
      self.buffer = self.buffer .. chunk
      
      -- Look for tags: <model:tag>content</model:tag>
      -- We'll also handle empty tags like <model:read file="..." />
      
      -- 1. Check for block tags: <model:tag ...>content</model:tag>
      while true do
        -- find returns: start, end, cap1, cap2, cap3
        local s_start, s_end, tag_name, attr, content = self.buffer:find("<model:([%a_]+)([^>]*)>(.-)</model:%1>")
        if s_start then
          table.insert(self.actions, { 
            name = tag_name, 
            attr = attr, 
            content = content 
          })
          self.buffer = self.buffer:sub(s_end + 1)
        else
          break
        end
      end
      
      -- 2. Check for self-closing tags: <model:tag file="..." />
      while true do
        local s_start, e_end, tag_name, attr = self.buffer:find("<model:([%a_]+)([^>]-)%s*/>")
        if s_start then
          table.insert(self.actions, { 
            name = tag_name, 
            attr = attr, 
            content = nil 
          })
          self.buffer = self.buffer:sub(e_end + 1)
        else
          break
        end
      end
    end,

    --- Get all collected actions and clear the list
    get_actions = function(self)
      local acts = self.actions
      self.actions = {}
      return acts
    end
  }
end

--- Extract attribute values from a tag's attribute string
--- @param attr_str string
--- @param key string
--- @return string | nil
function M.get_attr(attr_str, key)
  if not attr_str then return nil end
  return attr_str:match(key .. "=\"([^\"]+)\"") or attr_str:match(key .. "='([^']+)'")
end

return M;
