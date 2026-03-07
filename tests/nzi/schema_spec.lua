local assert = require("luassert")
local xml = require("tests.xml_helper")

describe("NZI Protocol Schema (XSD)", function()
  
  it("should validate a perfectly formed turn with agent and model namespaces", function()
    local turn = [[
      <agent:ack tool="shell" status="success">Done.</agent:ack>
      <model:summary>Updated the license file.</model:summary>
      <model:edit file="LICENSE">
<<<<<<< SEARCH
2025
=======
2026
>>>>>>> REPLACE
      </model:edit>
    ]]
    local success, _, errors = xml.validate_strict(turn)
    assert.True(success, "Perfectly formed turn should pass. Errors: " .. table.concat(errors or {}, "\n"))
  end)

  it("should HEAL unclosed tags and recover the XML", function()
    local broken = "<agent:status level='info'>In progress... " -- Missing </agent:status>
    local success, healed, errors = xml.validate_strict(broken)
    
    -- It should probably still fail validation (because it was broken)
    -- but it should provide a 'healed' version.
    assert.match("</agent:status>", healed)
  end)

  it("should REJECT tags not in the schema (Meta-Linting)", function()
    local illegal = "<unknown:tag>Should fail</unknown:tag>"
    local success, _, errors = xml.validate_strict(illegal)
    assert.is_false(success)
    assert.True(#errors > 0)
  end)

  it("should REJECT missing required attributes", function()
    -- <model:edit> requires 'file'
    local missing_attr = "<model:edit>Missing file attribute</model:edit>"
    local success, _, errors = xml.validate_strict(missing_attr)
    assert.is_false(success)
    assert.match("file", table.concat(errors, " "))
  end)

  it("should REJECT model summaries that are too long (Constraint Test)", function()
    local long_summary = string.rep("A", 200)
    local turn = string.format("<model:summary>%s</model:summary>", long_summary)
    local success, _, errors = xml.validate_strict(turn)
    assert.is_false(success)
    assert.match("maxLength", table.concat(errors, " "))
  end)

  it("should validate agent context and user blocks", function()
    local turn = [[
      <agent:context file="src/main.lua">
        local x = 1
      </agent:context>
      <agent:user type="instruct">Fix the bug</agent:user>
    ]]
    local success, _, errors = xml.validate_strict(turn)
    assert.True(success, "Agent context and user blocks should pass.")
  end)

end)
