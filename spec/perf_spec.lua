local search = require("search")
local fixtures = require("fixtures")

describe("performance #integration", function()
  it("a full search on a level-80 state fits into 3x the in-game budget", function()
    local S = fixtures.state({})
    local runs = 20
    local t0 = os.clock()
    for _ = 1, runs do
      local plan = search.best(S)
      assert.is_true(plan.nodes <= search.NODE_CAP)
    end
    local avgMs = (os.clock() - t0) * 1000 / runs
    assert.is_true(avgMs < search.BUDGET_MS * 3, ("average %.2f ms"):format(avgMs))
  end)
end)
