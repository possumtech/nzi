local assert = require("luassert");
local history = require("nzi.context.history");

describe("AI history module", function()
  before_each(function()
    history.clear();
  end);

  it("should add and format turns correctly (clean XML for model)", function()
    history.add("question", "What is 1+1?", "It is 2.");
    local formatted = history.format();
    
    assert.match("<agent:user>", formatted);
    assert.match("What is 1%+1%?", formatted);
    assert.match("<agent:assistant>", formatted);
    assert.match("It is 2%.", formatted);
    
    -- Ensure NO line numbers in the model-facing format
    assert.is_nil(formatted:find("1: "))
  end);

  it("should preserve line numbers in internal storage", function()
    history.add("question", "Line 1\nLine 2", "Result");
    local turn = history.get_all()[1];
    assert.match("1: Line 1\n2: Line 2", turn.user);
  end);

  it("should handle multiple turns", function()
    history.add("question", "Turn 1", "Reply 1");
    history.add("directive", "Turn 2", "Reply 2");
    local formatted = history.format();
    
    assert.match("Turn 1", formatted);
    assert.match("Reply 1", formatted);
    assert.match("Turn 2", formatted);
    assert.match("Reply 2", formatted);
  end);

  it("should escape XML in history turns", function()
    history.add("question", "</tag>", "<tag>");
    local formatted = history.format();
    
    assert.match("&lt;/tag&gt;", formatted, 1, true);
    assert.match("&lt;tag&gt;", formatted, 1, true);
  end);
end);
