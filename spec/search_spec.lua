local search = require("search")
local stub = require("stub_model")
local fixtures = require("fixtures")

local function opts(extra)
  local o = { model = stub, value = stub.value, budgetMs = 1e9 }
  for k, v in pairs(extra or {}) do o[k] = v end
  return o
end

local function keys(plan)
  local out = {}
  for i, s in ipairs(plan.steps) do out[i] = s.key end
  return table.concat(out, ",")
end

describe("search.best", function()
  it("shared shock cooldown: prefers an expired Flame Shock although Earth Shock hits harder now", function()
    stub.setup({
      es = { dmg = 100, cd = 5, shared = "shock" },
      fs = { dmg = 40, dot = 12, cd = 5, shared = "shock" },
      filler = { dmg = 30, cd = 0 },
    })
    assert.is_true(stub.SPELLS.es.dmg > stub.SPELLS.fs.dmg)
    local plan = search.best(stub.state({ fs = 0 }), opts())
    assert.are.equal("fs", plan.steps[1].key)
    assert.is_false(plan.timedOut)
  end)

  it("waits for a button that becomes ready inside the horizon", function()
    stub.setup({ big = { dmg = 300, cd = 10 } })
    local plan = search.best(stub.state({ cd = { big = 1.0 } }), opts())
    assert.are.equal("big", plan.steps[1].key)
    assert.are.near(1.0, plan.steps[1].at, 1e-9)
  end)

  it("never plans before the global cooldown ends", function()
    stub.setup({ a = { dmg = 50, cd = 0 } })
    local plan = search.best(stub.state({ gcdRemains = 1.0 }), opts())
    assert.are.near(1.0, plan.steps[1].at, 1e-9)
  end)

  it("never plans a step at or after the horizon", function()
    stub.setup({ a = { dmg = 50, cd = 0 }, b = { dmg = 20, cd = 0 } })
    local plan = search.best(stub.state(), opts())
    assert.is_true(#plan.steps >= 1 and #plan.steps <= search.DEPTH)
    for _, s in ipairs(plan.steps) do assert.is_true(s.at < search.HORIZON) end
  end)

  it("a step after waitSwing is marked 'after swing - no clip'", function()
    stub.setup({ a = { dmg = 50, cd = 0 } })
    local S = stub.state({ swing = 0.3, mw = 3 })
    stub.value.step = function(_, S2, dmg) return dmg + ((S2.now >= 0.3 and S2.now < 0.35) and 1000 or 0) end
    local plan = search.best(S, opts())
    stub.value.step = function(_, _, dmg) return dmg end
    assert.are.equal("a", plan.steps[1].key)
    assert.are.near(0.31, plan.steps[1].at, 1e-9)
  end)

  it("returns the best plan found so far when the time budget runs out", function()
    stub.setup({ a = { dmg = 50, cd = 0 }, b = { dmg = 20, cd = 0 }, c = { dmg = 10, cd = 0 } })
    local t = 0
    local plan = search.best(stub.state(), opts({ budgetMs = 2, clock = function() t = t + 1; return t end }))
    assert.is_true(plan.timedOut)
    assert.is_true(#plan.steps >= 1)
  end)

  it("is deterministic", function()
    stub.setup({ a = { dmg = 50, cd = 3 }, b = { dmg = 50, cd = 3 }, c = { dmg = 20, cd = 0 } })
    local p1 = search.best(stub.state(), opts())
    local p2 = search.best(stub.state(), opts())
    assert.are.equal(keys(p1), keys(p2))
    assert.are.equal(p1.value, p2.value)
  end)

  it("returns an empty plan when nothing can be pressed", function()
    stub.setup({})
    local plan = search.best(stub.state(), opts())
    assert.are.equal(0, #plan.steps)
    assert.are.equal(0, plan.value)
  end)
end)

describe("search.best edge cases", function()
  it("only a swing to wait for: the plan stays empty", function()
    stub.setup({})
    local plan = search.best(stub.state({ swing = 0.3 }), opts())
    assert.are.equal(0, #plan.steps)
    assert.are.equal(0, plan.value)
  end)

  it("respects a shorter horizon from opts", function()
    stub.setup({ a = { dmg = 50, cd = 0 } })
    local plan = search.best(stub.state(), opts({ horizon = 3 }))
    for _, s in ipairs(plan.steps) do assert.is_true(s.at < 3) end
  end)
end)

describe("search.evaluate", function()
  it("replays planned steps and keeps a planned wait", function()
    stub.setup({ a = { dmg = 50, cd = 0 } })
    local v, steps = search.evaluate(stub.state(), { { key = "a", at = 0.5, reason = "r" } }, opts())
    assert.is_number(v)
    assert.are.near(0.5, steps[1].at, 1e-9)
    assert.are.equal("r", steps[1].reason)
  end)

  it("returns nil when a planned step is no longer possible", function()
    stub.setup({ a = { dmg = 50, cd = 0 } })
    assert.is_nil(search.evaluate(stub.state(), { { key = "gone", at = 0, reason = "" } }, opts()))
  end)
end)

describe("search.signature and reason", function()
  it("ignores irrelevant fields but not cooldowns", function()
    stub.setup({ a = { dmg = 1, cd = 0 } })
    local s1, s2, s3 = stub.state(), stub.state(), stub.state({ cd = { a = 2 } })
    s2.enemies.nearby = 5
    assert.are.equal(search.signature(s1), search.signature(s2))
    assert.are_not.equal(search.signature(s1), search.signature(s3))
  end)

  it("explains Lightning Bolt and Flame Shock", function()
    stub.setup({})
    assert.are.equal("5 Maelstrom stacks", search.reason(stub.state({ mw = 5 }), "lightningBolt", false))
    assert.are.equal("after swing - no clip", search.reason(stub.state({ mw = 3 }), "lightningBolt", true))
    assert.are.equal("3 Maelstrom stacks", search.reason(stub.state({ mw = 3 }), "lightningBolt", false))
    assert.are.equal("Flame Shock expired", search.reason(stub.state({ fs = 0 }), "flameShock", false))
    assert.are.equal("refresh Flame Shock", search.reason(stub.state({ fs = 4 }), "flameShock", false))
  end)
end)

-- Integration: the real model/damage/value (Task 10, step 6). Three wowsims rules:
-- 1) an expired Flame Shock beats Earth Shock; 2) 5 Maelstrom stacks -> Lightning Bolt;
-- 3) 3 stacks with the main hand due in 0.3 s -> wait for the swing, then weave without a clip.

local function merge(a, b)
  for k, v in pairs(b) do
    if type(v) == "table" and type(a[k]) == "table" then merge(a[k], v) else a[k] = v end
  end
  return a
end

-- level 80, every button except the ones a test frees is on cooldown, magma already down
local function busy(over)
  local base = {
    spells = {
      stormstrike = { cd = 9 }, lavaLash = { cd = 9 }, earthShock = { cd = 9 }, flameShock = { cd = 9 },
      frostShock = { cd = 9 }, fireNova = { cd = 9 }, chainLightning = { cd = 9 }, feralSpirit = { cd = 90 },
      fireElemental = { cd = 90 }, shamanisticRage = { cd = 50 }, callOfElements = { cd = 0 },
    },
    totems = { fire = { kind = "magma", remains = 20 }, water = { remains = 100 } },
    buffs = { ls = { charges = 3, remains = 600 }, mw = { stacks = 0, remains = 0 } },
    target = { fs = 10 },
    weapons = { mh = { enchant = "wf" }, oh = { enchant = "ft" } },
  }
  return fixtures.state(merge(base, over or {}))
end

describe("search on the real model (wowsims rules) #integration", function()
  it("an expired Flame Shock goes before Earth Shock", function()
    local plan = search.best(busy({ spells = { flameShock = { cd = 0 }, earthShock = { cd = 0 } }, target = { fs = 0 } }),
      { budgetMs = 1e9 })
    assert.are.equal("flameShock", plan.steps[1].key)
    assert.are.equal("Flame Shock expired", plan.steps[1].reason)
  end)

  it("5 Maelstrom stacks -> instant Lightning Bolt", function()
    local plan = search.best(busy({ buffs = { mw = { stacks = 5, remains = 20 } } }), { budgetMs = 1e9 })
    assert.are.equal("lightningBolt", plan.steps[1].key)
    assert.are.equal("5 Maelstrom stacks", plan.steps[1].reason)
  end)

  it("3 stacks: waits for the main-hand swing, then weaves Lightning Bolt without a clip", function()
    local S = busy({
      buffs = { mw = { stacks = 3, remains = 20 } },
      player = { meleeHaste = 1.25, spellHaste = 1.10 },
      swing = { attacking = true, mh = { next = 0.3, speed = 2.6 }, oh = { next = 1.5, speed = 2.6 } },
    })
    local plan = search.best(S, { budgetMs = 1e9 })
    assert.are.equal("lightningBolt", plan.steps[1].key)
    assert.is_true(plan.steps[1].at >= 0.29 and plan.steps[1].at < 0.45, "at=" .. plan.steps[1].at)
    assert.are.equal("after swing - no clip", plan.steps[1].reason)
  end)
end)
