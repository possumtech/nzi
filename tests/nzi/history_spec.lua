local assert = require("luassert");
local history = require("nzi.context.history");
local xml = require("tests.xml_helper");

describe("AI history module", function()
  before_each(function()
    history.clear();
  end);

  it("should add and format turns correctly (clean XML for model)", function()
    history.add("ask", "What is 1+1?", "<model:summary>It is 2.</model:summary>");
    local formatted = history.format();
    
    xml.assert_valid(formatted);
    assert.match("<agent:user>", formatted);
    assert.match("What is 1%+1%?", formatted);
    assert.match("<model:summary>", formatted);
    assert.match("It is 2%.", formatted);
    
    -- Ensure NO line numbers in the model-facing format
    assert.is_nil(formatted:find("1: "))
  end);

  it("should preserve line numbers in internal storage", function()
    history.add("ask", "Line 1\nLine 2", "Result");
    local turn = history.get_all()[1];
    assert.match("1: Line 1\n2: Line 2", turn.user);
  end);

end);
