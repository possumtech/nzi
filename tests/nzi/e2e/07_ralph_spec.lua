local assert = require("luassert")
local agent = require("nzi.protocol.agent")
local config = require("nzi.core.config")

describe("7. Ralph & Verification", function()
  it("should execute tests and feed failures back to AI if ralph is active", function()
    local orig_ralph = config.options.ralph
    config.options.ralph = true
    
    local returned_response
    -- Pass a command that will definitely fail
    agent.verify_state(function(resp)
      returned_response = resp
    end, "echo 'Error: test failed on line 42' && false")
    
    assert.truthy(returned_response)
    assert.match("<agent:test>", returned_response)
    assert.match("Error: test failed on line 42", returned_response)
    assert.match("</agent:test>", returned_response)
    
    -- restore
    config.options.ralph = orig_ralph
  end)

  it("should not return a failure response if tests pass", function()
    local returned_response = "default"
    
    -- Pass a command that will definitely succeed
    agent.verify_state(function(resp)
      returned_response = resp
    end, "echo 'All tests passed.' && true")
    
    assert.falsy(returned_response, "Response should be nil on success")
  end)
end)
