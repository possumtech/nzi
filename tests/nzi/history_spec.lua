local assert = require("luassert");
local history = require("nzi.history");

describe("nzi history module", function()
  before_each(function()
    history.clear();
  end);

  it("should add and format turns correctly", function()
    history.add("question", "What is 1+1?", "It is 2.");
    local formatted = history.format();
    
    assert.match("<history>", formatted);
    assert.match("<turn id=\"1\" type=\"question\">", formatted, 1, true);
    assert.match("1: What is 1%+1%?", formatted);
    assert.match("1: It is 2%.", formatted);
    assert.match("</turn>", formatted);
  end);

  it("should handle multiple turns with unique IDs", function()
    history.add("question", "Turn 1", "Reply 1");
    history.add("directive", "Turn 2", "Reply 2");
    local formatted = history.format();
    
    assert.match("id=\"1\"", formatted);
    assert.match("id=\"2\"", formatted);
    assert.match("type=\"question\"", formatted);
    assert.match("type=\"directive\"", formatted);
  end);

  it("should escape XML in history turns", function()
    history.add("question", "</turn>", "<history>");
    local formatted = history.format();
    
    -- Should be escaped to &lt;/turn&gt; etc.
    assert.match("&lt;/turn&gt;", formatted, 1, true);
    assert.match("&lt;history&gt;", formatted, 1, true);
  end);
end);
