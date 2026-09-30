local planner = require("planner")
local fixtures = require("fixtures")

local function stubSearch(script)
  local s = { seen = {} }
  function s.best(S)
    s.seen[#s.seen + 1] = S
    return { value = script.best, steps = script.steps or { { key = script.bestKey or "fresh", at = 0, reason = "" } } }
  end
  function s.evaluate(_, steps)
    s.lastEval = steps
    if script.evaluate == false then return nil end
    return script.evaluate, steps
  end
  return s
end

local function at(now, over)
  local o = { now = now }
  for k, v in pairs(over or {}) do o[k] = v end
  return fixtures.state(o)
end

describe("planner", function()
  it("takes the first plan as is", function()
    local p = planner.new({ search = stubSearch({ best = 100, bestKey = "a" }) })
    assert.are.equal("a", p:update(at(100)).steps[1].key)
  end)

  it("holds the current plan when the new one is less than 3% better", function()
    local script = { best = 100, bestKey = "a" }
    local p = planner.new({ search = stubSearch(script) })
    p:update(at(100))
    script.best, script.bestKey, script.evaluate = 102, "b", 100
    local plan = p:update(at(100.1))
    assert.are.equal("a", plan.steps[1].key)
    assert.is_true(plan.held)
  end)

  it("switches when the new plan is more than 3% better", function()
    local script = { best = 100, bestKey = "a" }
    local p = planner.new({ search = stubSearch(script) })
    p:update(at(100))
    script.best, script.bestKey, script.evaluate = 104, "b", 100
    assert.are.equal("b", p:update(at(100.1)).steps[1].key)
  end)

  it("hysteresis works with negative values", function()
    local script = { best = -100, bestKey = "a" }
    local p = planner.new({ search = stubSearch(script) })
    p:update(at(100))
    script.best, script.bestKey, script.evaluate = -99, "b", -100
    assert.are.equal("a", p:update(at(100.1)).steps[1].key)
  end)

  it("switches when the held plan can no longer be played", function()
    local script = { best = 100, bestKey = "a" }
    local p = planner.new({ search = stubSearch(script) })
    p:update(at(100))
    script.best, script.bestKey, script.evaluate = 50, "b", false
    assert.are.equal("b", p:update(at(100.1)).steps[1].key)
  end)

  it("switches when the player cast something else", function()
    local script = { best = 100, bestKey = "a" }
    local p = planner.new({ search = stubSearch(script) })
    p:update(at(100))
    script.best, script.bestKey, script.evaluate = 101, "b", 100
    assert.are.equal("b", p:update(at(100.1), { kind = "cast", key = "earthShock" }).steps[1].key)
  end)

  it("switches on target change", function()
    local script = { best = 100, bestKey = "a" }
    local p = planner.new({ search = stubSearch(script) })
    p:update(at(100))
    script.best, script.bestKey, script.evaluate = 100, "b", 100
    assert.are.equal("b", p:update(at(100.1), { kind = "target" }).steps[1].key)
  end)

  it("casting the planned first step drops it and replays the rest", function()
    local script = { best = 100, steps = { { key = "stormstrike", at = 0, reason = "" }, { key = "lavaLash", at = 1.5, reason = "" } } }
    local s = stubSearch(script)
    local p = planner.new({ search = s })
    p:update(at(100))
    script.evaluate = 100
    p:update(at(100.2), { kind = "cast", key = "stormstrike" })
    assert.are.equal(1, #s.lastEval)
    assert.are.equal("lavaLash", s.lastEval[1].key)
    assert.are.near(1.3, s.lastEval[1].at, 1e-9)
  end)

  it("the end of a cast already taken at its start neither forces a replan nor drops a step", function()
    local script = { best = 100, steps = { { key = "lightningBolt", at = 0, reason = "" }, { key = "lavaLash", at = 1.7, reason = "" } } }
    local s = stubSearch(script)
    local p = planner.new({ search = s })
    p:update(at(100))
    script.evaluate = 100
    p:update(at(100.1), { kind = "cast", key = "lightningBolt" }) -- START
    script.steps, script.best = { { key = "stormstrike", at = 0, reason = "" } }, 102
    local plan = p:update(at(101.8), { kind = "cast", key = "lightningBolt", done = true }) -- SUCCEEDED
    assert.are.equal("lavaLash", plan.steps[1].key)
    assert.is_true(plan.held)
  end)

  it("shifts held steps by the elapsed time", function()
    local script = { best = 100, steps = { { key = "a", at = 1.0, reason = "" } } }
    local s = stubSearch(script)
    local p = planner.new({ search = s })
    p:update(at(100))
    script.evaluate = 100
    p:update(at(100.4))
    assert.are.near(0.6, s.lastEval[1].at, 1e-9)
  end)

  it("treats a just-cast Flame Shock as applied for up to 1 second", function()
    local s = stubSearch({ best = 100 })
    local p = planner.new({ search = s })
    p:update(at(100, { target = { fs = 0 } }), { kind = "cast", key = "flameShock" })
    assert.is_true(s.seen[1].target.fs >= 12)
    assert.is_true(s.seen[1].inflight.flameShock > 0)
    p:update(at(100.5, { target = { fs = 0 } }))
    assert.is_true(s.seen[2].target.fs >= 12)
    p:update(at(101.2, { target = { fs = 0 } }))
    assert.are.equal(0, s.seen[3].target.fs)
    assert.is_nil(p.inflight.flameShock)
  end)

  it("does not mutate the snapshot it was given", function()
    local p = planner.new({ search = stubSearch({ best = 100 }) })
    local S = at(100, { target = { fs = 0 } })
    p:update(S, { kind = "cast", key = "flameShock" })
    assert.are.equal(0, S.target.fs)
  end)

  it("survives empty plans", function()
    local script = { best = 0, steps = {} }
    local p = planner.new({ search = stubSearch(script) })
    assert.are.equal(0, #p:update(at(100)).steps)
    assert.are.equal(0, #p:update(at(100.25)).steps)
  end)
  it("a negative plan is replaced when the new one clears |old| * 3%", function()
    local script = { best = -100, bestKey = "a" }
    local p = planner.new({ search = stubSearch(script) })
    p:update(at(100))
    script.best, script.bestKey, script.evaluate = -96, "b", -100
    assert.are.equal("b", p:update(at(100.1)).steps[1].key)
  end)

  it("Flame Shock just cast is assumed to last its full 18 seconds", function()
    local s = stubSearch({ best = 100 })
    local p = planner.new({ search = s })
    p:update(at(100, { target = { fs = 0 } }), { kind = "cast", key = "flameShock" })
    assert.are.near(18, s.seen[1].target.fs, 1e-9)
  end)

  it("keeps in-flight entries that came with the snapshot", function()
    local s = stubSearch({ best = 100 })
    local p = planner.new({ search = s })
    p:update(at(100, { inflight = { stormstrike = 0.4 } }), { kind = "cast", key = "flameShock" })
    assert.are.near(0.4, s.seen[1].inflight.stormstrike, 1e-9)
    assert.are.near(1.0, s.seen[1].inflight.flameShock, 1e-9)
  end)

  -- a search that needs `slices` run() calls; the plan it finds is script.bestKey at that time
  local function slowSearch(script, slices)
    local s = stubSearch(script)
    s.started = 0
    function s.start()
      s.started = s.started + 1
      local left, key, value = slices, script.bestKey, script.best
      return { run = function(job)
        left = left - 1
        if left > 0 then return false end
        job.result = { value = value, steps = { { key = key, at = 0, reason = "" } } }
        return true
      end }
    end
    return s
  end

  it("with a per-frame budget the plan changes only once the search has finished", function()
    local script = { best = 100, bestKey = "a" }
    local s = slowSearch(script, 3)
    local p = planner.new({ search = s, budgetMs = 2 })
    assert.are.equal(0, #p:update(at(100)).steps) -- no plan yet
    assert.is_false(p:work())
    assert.is_true(p:work())
    assert.are.equal("a", p:view(100.05).steps[1].key)
    script.best, script.bestKey, script.evaluate = 200, "b", 100
    assert.are.equal("a", p:update(at(100.1), { kind = "aura" }).steps[1].key)
    assert.is_false(p:work())
    assert.are.equal("a", p:view(100.12).steps[1].key)
    assert.is_true(p:work())
    assert.are.equal("b", p:view(100.15).steps[1].key)
  end)

  it("events during a running search are searched after it, not instead of it", function()
    local script = { best = 100, bestKey = "a" }
    local s = slowSearch(script, 4) -- every update() runs one slice
    local p = planner.new({ search = s, budgetMs = 2 })
    p:update(at(100))
    p:update(at(100.02), { kind = "aura" })
    p:update(at(100.04), { kind = "power" })
    assert.are.equal(1, s.started)
    assert.is_true(p:work())
    assert.are.equal(2, s.started) -- one search for the newest state
    assert.is_true(p:busy())
  end)

  it("pressing the planned button shows the rest of the plan at once", function()
    local script = { best = 100, steps = { { key = "stormstrike", at = 0, reason = "" }, { key = "lavaLash", at = 1.5, reason = "" } } }
    local s = stubSearch(script)
    local p = planner.new({ search = s })
    p:update(at(100))
    local slow = slowSearch({ best = 100, bestKey = "x" }, 5)
    p.search = setmetatable({ start = slow.start }, { __index = s })
    p.budgetMs = 2
    local plan = p:update(at(100.2), { kind = "cast", key = "stormstrike" })
    assert.are.equal("lavaLash", plan.steps[1].key)
    assert.are.near(1.3, plan.steps[1].at, 1e-9)
  end)

  it("a cast event before any plan exists does not fail", function()
    local p = planner.new({ search = stubSearch({ best = 10, bestKey = "a" }) })
    assert.are.equal("a", p:update(at(100), { kind = "cast", key = "stormstrike" }).steps[1].key)
  end)
end)
