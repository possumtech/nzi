local assert = require("luassert");
local xml = require("tests.xml_helper");

describe("NZI Protocol Contracts", function()
  
  it("must enforce the Preamble requirement (Turn ID 0)", function()
    local session = [[
<agent:turn id="1">
  <agent:user>Hello</agent:user>
</agent:turn>
]]
    local res = xml.validate(session);
    assert.is_false(res.success);
    local found = false;
    for _, err in ipairs(res.errors) do
      if err:match("must contain exactly one Preamble turn") then found = true; end
    end
    assert.truthy(found, "Failed to enforce NZI Preamble contract");
  end);

  it("must enforce the Unified Diff contract for edit blocks", function()
    local session = [[
<agent:turn id="0" model="system"><agent:user>pre</agent:user></agent:turn>
<agent:turn id="1">
  <model:edit file="test.lua">
    Invalid format without search/replace markers.
  </model:edit>
</agent:turn>
]]
    local res = xml.validate(session);
    assert.is_false(res.success);
    local found = false;
    for _, err in ipairs(res.errors) do
      if err:match("unified diff format") then found = true; end
    end
    assert.truthy(found, "Failed to enforce NZI Unified Diff contract");
  end);

  it("must ensure turn IDs are non-negative", function()
    local session = [[
<agent:turn id="0" model="system"><agent:user>pre</agent:user></agent:turn>
<agent:turn id="-1">
  <agent:user>invalid</agent:user>
</agent:turn>
]]
    local res = xml.validate(session);
    assert.is_false(res.success);
    local found = false;
    for _, err in ipairs(res.errors) do
      if err:match("Turn IDs must be non%-negative") then found = true; end
    end
    assert.truthy(found, "Failed to enforce non-negative ID contract");
  end);

end);
