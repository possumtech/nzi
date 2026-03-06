local M = {}

--- Validate XML string by wrapping in a root tag and using python's ET
--- @param xml_str string
--- @return boolean, string | nil
function M.validate_xml(xml_str)
  -- Wrap in a root tag to handle multiple top-level tags
  local wrapped = "<root xmlns:agent=\"agent\" xmlns:model=\"model\">\n" .. xml_str .. "\n</root>"
  
  -- Escape for shell (minimal)
  local script = string.format([[
import sys
import xml.etree.ElementTree as ET
try:
    ET.fromstring(sys.stdin.read())
    sys.exit(0)
except Exception as e:
    print(str(e))
    sys.exit(1)
]])

  local result = vim.system({ "python3", "-c", script }, { stdin = wrapped }):wait()
  
  if result.code == 0 then
    return true, nil
  else
    return false, result.stdout
  end
end

return M
