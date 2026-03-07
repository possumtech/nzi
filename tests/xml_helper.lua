local M = {}

--- Validate XML string against the formal nzi.xsd schema and attempt healing
--- @param xml_str string
--- @return boolean success
--- @return string healed_xml
--- @return table errors
function M.validate_strict(xml_str)
  local script_path = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h") .. "/lua/nzi/protocol/validator.py"
  local xsd_path = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h") .. "/nzi.xsd"
  
  -- Use the project's python environment
  local python_cmd = vim.env.NZI_PYTHON_CMD or ".venv/bin/python"
  
  local result = vim.system({ python_cmd, script_path, xsd_path }, { stdin = xml_str }):wait()
  
  if result.code ~= 0 then
    return false, xml_str, { "Validator process failed: " .. (result.stderr or "Unknown error") }
  end
  
  local ok, decoded = pcall(vim.json.decode, result.stdout)
  if not ok then
    return false, xml_str, { "Failed to decode validator output: " .. tostring(decoded) }
  end
  
  return decoded.success, decoded.healed_xml, decoded.errors or {}
end

--- Simple wrapper for boolean assertion in tests
function M.assert_valid(xml_str)
  local success, _, errors = M.validate_strict(xml_str)
  if not success then
    error("XML Schema Violation:\n" .. table.concat(errors, "\n"))
  end
  return true
end

return M
