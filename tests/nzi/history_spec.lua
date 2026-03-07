local assert = require("luassert");
local history = require("nzi.dom.session");
local xml = require("tests.xml_helper");

describe("AI history module", function()
  before_each(function()
    history.clear();
  end);

  it("should add and format turns correctly (clean XML for model)", function()
    -- 1. Add Preamble (ID 0)
    history.add("ask", "System Preamble", nil, { model = "system" });
    -- 2. Add real turn (ID 1)
    history.add("ask", "What is 1+1?", "<model:summary>It is 2.</model:summary>");
    
    local formatted = history.format();
    
    xml.assert_valid(formatted);
    
    -- Verify the structure via XPath
    local ids = xml.xpath(formatted, "//nzi:turn/@id");
    assert.equals("0", ids[1]);
    assert.equals("1", ids[2]);

    assert.truthy(formatted:find("<agent:user>"));
    assert.truthy(formatted:find("What is 1+1?"));
    assert.truthy(formatted:find("<model:summary>"));
    assert.truthy(formatted:find("It is 2."));
    
    -- Ensure NO line numbers in the model-facing format
    assert.is_nil(formatted:find("1: "))
  end);

  it("should preserve line numbers in internal storage", function()
    history.add("ask", "Line 1\nLine 2", "Result");
    local turn = history.get_all()[1];
    assert.match("1: Line 1\n2: Line 2", turn.user);
  end);

end);
