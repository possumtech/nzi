local config = require("nzi.core.config");
local M = {};

--- Validate an XML string against our XSD and Schematron
--- @param xml_str string
--- @return table: { success = bool, errors = table }
function M.validate(xml_str)
  local python_cmd = config.options.python_cmd[1];
  local validator_script = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h") .. "/validator.py";
  
  local res = vim.fn.system({ python_cmd, validator_script }, xml_str);
  local ok, data = pcall(vim.fn.json_decode, res);
  
  if not ok then
    return { success = false, errors = { "Validator output was not valid JSON: " .. tostring(res) } };
  end
  
  return data;
end

return M;
