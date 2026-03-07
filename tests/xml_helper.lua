local M = {};

--- Call the Python validator to validate XML against XSD and Schematron
--- @param xml_str string
--- @return table: { success = bool, healed_xml = string, errors = table }
function M.validate(xml_str)
  local config = require("nzi.core.config");
  local xsd_path = vim.fn.getcwd() .. "/nzi.xsd";
  local sch_path = vim.fn.getcwd() .. "/nzi.sch";
  
  local python_cmd = config.options.python_cmd[1] or "python3";
  local validator_script = vim.fn.getcwd() .. "/lua/nzi/protocol/validator.py";
  
  local cmd = string.format("%s %s %s %s", python_cmd, validator_script, xsd_path, sch_path);
  local res = vim.fn.system(cmd, xml_str);
  
  local ok, data = pcall(vim.fn.json_decode, res);
  if not ok then
    return { success = false, errors = { "Validator JSON Parse Error: " .. tostring(res) }, healed_xml = xml_str };
  end
  return data;
end

--- Assert that XML is valid according to schema and rules
--- @param xml_str string
function M.assert_valid(xml_str)
  local res = M.validate(xml_str);
  if not res.success then
    error("XML Validation Failed:\n" .. table.concat(res.errors, "\n") .. "\n\nXML:\n" .. xml_str);
  end
end

--- Run an XPath query against an XML string and return results
--- (Uses a simplified python one-liner for now)
--- @param xml_str string
--- @param xpath string
--- @return table: List of results
function M.xpath(xml_str, xpath)
  local config = require("nzi.core.config");
  local python_cmd = config.options.python_cmd[1] or "python3";
  
  -- Wrap in dummy root if needed for simple fragments
  local wrapped = xml_str;
  if not xml_str:match("^<session") then
    wrapped = string.format("<session xmlns='nzi' xmlns:agent='nzi' xmlns:model='nzi'>%s</session>", xml_str);
  end

  local script = [[
import sys
from lxml import etree
xml_str = sys.stdin.read()
root = etree.fromstring(xml_str)
ns = {"nzi": "nzi", "agent": "nzi", "model": "nzi"}
results = root.xpath("]] .. xpath .. [[", namespaces=ns)
print("---XPATH_RESULTS_START---")
for r in results:
    if isinstance(r, etree._Element):
        print(etree.tostring(r, encoding='unicode').strip())
    else:
        print(str(r).strip())
]];

  local res = vim.fn.system(python_cmd .. " -", script .. "\n" .. wrapped);
  local lines = vim.split(res, "\n", { trimempty = true });
  local final_results = {};
  local in_results = false;
  for _, line in ipairs(lines) do
    if line == "---XPATH_RESULTS_START---" then
      in_results = true;
    elseif in_results then
      table.insert(final_results, line);
    end
  end
  return final_results;
end

return M;
