local history = require("nzi.dom.session");
local config = require("nzi.core.config");

describe("NZI: The Brutal E2E Drill", function()
  before_each(function()
    history.clear();
  end);

  it("should parse model output into turns", function()
    history.add("ask", "User text", "Assistant <summary>Done</summary>", { model = "test" });
    local turns = history.get_all();
    assert.are.equal(1, #turns);
    -- Check that summary was parsed/preserved
    assert.match("summary", turns[1].assistant);
  end);
end);
