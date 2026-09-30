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

  -- waiting for a swing is only for weaving a cast (search.WEAVE): "swing, then Bolt" is one step
  it("a Bolt after waitSwing is marked as fitting before the next swing", function()
    -- (a cast: an instant clips nothing, so it is never planned after a swing)
    stub.setup({ lightningBolt = { dmg = 50, cd = 0, cast = 1.0 }, a = { dmg = 60, cd = 0 } })
    local S = stub.state({ swing = 0.3, mw = 3 })
    stub.value.step = function(_, S2, dmg) return dmg + ((S2.now >= 0.3 and S2.now < 0.35) and 1000 or 0) end
    local plan = search.best(S, opts())
    stub.value.step = function(_, _, dmg) return dmg end
    assert.are.equal("lightningBolt", plan.steps[1].key)
    assert.are.near(0.31, plan.steps[1].at, 1e-9)
    assert.are.equal("3 stacks, fits before swing", plan.steps[1].reason)
  end)

  -- the old wall-clock cut made the plan depend on the computer's speed (and flicker)
  it("is never cut by the clock: a slow clock gives the same plan", function()
    stub.setup({ a = { dmg = 50, cd = 0 }, b = { dmg = 20, cd = 0 }, c = { dmg = 10, cd = 0 } })
    local t = 0
    local slow = search.best(stub.state(), opts({ budgetMs = 2, clock = function() t = t + 1; return t end }))
    local plain = search.best(stub.state(), opts())
    assert.is_false(slow.capped)
    assert.are.equal(keys(plain), keys(slow))
    assert.are.equal(plain.value, slow.value)
  end)

  it("returns the best plan found so far when the node cap is reached", function()
    stub.setup({ a = { dmg = 50, cd = 0 }, b = { dmg = 20, cd = 0 }, c = { dmg = 10, cd = 0 } })
    local plan = search.best(stub.state(), opts({ nodeCap = 4 }))
    assert.is_true(plan.capped)
    assert.is_true(#plan.steps >= 1)
    assert.are.equal(4, plan.nodes)
  end)

  it("a search run in slices (start/run) gives the same plan as a whole one", function()
    stub.setup({ a = { dmg = 50, cd = 3 }, b = { dmg = 45, cd = 2 }, c = { dmg = 20, cd = 0 } })
    local t = 0
    local job = search.start(stub.state(), opts({ clock = function() t = t + 0.7; return t end }))
    local slices = 0
    while not job:run(1) do slices = slices + 1 end
    assert.is_true(slices >= 2, "slices " .. slices)
    local whole = search.best(stub.state(), opts())
    assert.are.equal(keys(whole), keys(job.result))
    assert.are.equal(whole.value, job.result.value)
    assert.is_true(job:run(1))
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
    assert.are.equal("5 stacks: instant", search.reason(stub.state({ mw = 5 }), "lightningBolt", false))
    assert.are.equal("3 stacks, fits before swing", search.reason(stub.state({ mw = 3 }), "lightningBolt", true))
    assert.are.equal("3 stacks: hard-cast", search.reason(stub.state({ mw = 3 }), "lightningBolt", false))
    assert.are.equal("Flame Shock not ticking", search.reason(stub.state({ fs = 0 }), "flameShock", false))
    assert.are.equal("refresh Flame Shock", search.reason(stub.state({ fs = 4 }), "flameShock", false))
  end)

  -- a new player reads these under the icon: why this button, not "0 Maelstrom stacks" at 30 yd
  it("a pull Bolt says the target is out of melee; 5 stacks is still 'instant'", function()
    stub.setup({})
    for _, range in ipairs({ "20", "30", "far" }) do
      local S = stub.state({ mw = 0 })
      S.target.range = range
      assert.are.equal("pull: target out of melee", search.reason(S, "lightningBolt", false))
      assert.are.equal("pull: target out of melee", search.reason(S, "chainLightning", true))
    end
    local S = stub.state({ mw = 5 })
    S.target.range = "30"
    assert.are.equal("5 stacks: instant", search.reason(S, "lightningBolt", false))
    S = stub.state({ mw = 2 })
    S.target.range = "melee"
    assert.are.equal("2 stacks: hard-cast", search.reason(S, "lightningBolt", false))
  end)

  it("Earth Shock says whether Flame Shock is ticking", function()
    stub.setup({})
    assert.are.equal("Flame Shock up: Earth Shock", search.reason(stub.state({ fs = 9 }), "earthShock", false))
    assert.are.equal("Earth Shock: instant damage", search.reason(stub.state({ fs = 0 }), "earthShock", false))
  end)

  it("fire totems and Fire Nova count their targets", function()
    stub.setup({})
    local S = stub.state()
    S.target.exists, S.target.enemy, S.target.range = true, true, "melee"
    assert.are.equal("1 target: Searing Totem", search.reason(S, "searingTotem", false))
    assert.are.equal("fire totem: Magma Totem", search.reason(S, "magmaTotem", false))
    assert.are.equal("Fire Nova ready", search.reason(S, "fireNova", false))
    S.enemies.nearby = 3
    assert.are.equal("3 targets: Magma Totem", search.reason(S, "magmaTotem", false))
    assert.are.equal("3 targets: Fire Nova", search.reason(S, "fireNova", false))
    assert.are.equal("fire totem: Searing Totem", search.reason(S, "searingTotem", false))
  end)

  it("Shamanistic Rage is about mana, never a damage cooldown", function()
    stub.setup({})
    local S = stub.state()
    S.player.mana = 200
    assert.are.equal("mana: Shamanistic Rage", search.reason(S, "shamanisticRage", false))
    S.player.mana = 900
    assert.are.equal("Rage: mana, -30% damage", search.reason(S, "shamanisticRage", false))
  end)

  it("Lightning Shield: missing or low", function()
    stub.setup({})
    local S = stub.state()
    S.buffs.ls = { charges = 0 }
    assert.are.equal("Lightning Shield missing", search.reason(S, "lightningShield", false))
    S.buffs.ls = { charges = 1 }
    assert.are.equal("Lightning Shield low", search.reason(S, "lightningShield", false))
  end)

  it("every reason fits under an icon (28 characters at most)", function()
    stub.setup({})
    local keys = { "lightningBolt", "chainLightning", "flameShock", "earthShock", "frostShock", "searingTotem",
                   "magmaTotem", "fireNova", "shamanisticRage", "lightningShield", "stormstrike", "lavaLash",
                   "fireElemental", "feralSpirit", "callOfElements" }
    for _, mw in ipairs({ 0, 4, 5 }) do
      for _, fs in ipairs({ 0, 5 }) do
        for _, range in ipairs({ "melee", "30" }) do
          for _, nearby in ipairs({ 1, 12 }) do
            for _, mana in ipairs({ 100, 1000 }) do
              for _, after in ipairs({ false, true }) do
                local S = stub.state({ mw = mw, fs = fs })
                S.target.exists, S.target.enemy, S.target.range = true, true, range
                S.enemies.nearby, S.player.mana = nearby, mana
                for _, k in ipairs(keys) do
                  local r = search.reason(S, k, after)
                  assert.is_true(#r <= 28, k .. ": " .. r)
                  assert.are_not.equal(k, r)
                end
              end
            end
          end
        end
      end
    end
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
    assert.are.equal("Flame Shock not ticking", plan.steps[1].reason)
  end)

  -- Fire Nova goes off around the fire totem (10 yd), and the totem stands at the shaman's feet
  it("no Fire Nova with the target at 30 yd and nothing in melee, standing or running", function()
    for _, moving in ipairs({ false, true }) do
      local plan = search.best(busy({ spells = { fireNova = { cd = 0 } }, target = { range = "30" },
                                      enemies = { melee = 0, nearby = 1 }, player = { moving = moving } }), { budgetMs = 1e9 })
      for _, st in ipairs(plan.steps) do assert.are_not.equal("fireNova", st.key) end
    end
    local plan = search.best(busy({ spells = { fireNova = { cd = 0 } } }), { budgetMs = 1e9 })
    assert.are.equal("fireNova", plan.steps[1].key)
  end)

  it("5 Maelstrom stacks -> instant Lightning Bolt", function()
    local plan = search.best(busy({ buffs = { mw = { stacks = 5, remains = 20 } } }), { budgetMs = 1e9 })
    assert.are.equal("lightningBolt", plan.steps[1].key)
    assert.are.equal("5 stacks: instant", plan.steps[1].reason)
  end)

  -- a cast that ends after the horizon would get its damage while its cost (the delayed swings)
  -- falls outside the horizon: it is not planned at all
  it("a button pressed just before the horizon moves the state only up to it", function()
    local real = require("model")
    local limits = {}
    local spy = setmetatable({
      apply = function(S, key, limit) limits[#limits + 1] = limit; return real.apply(S, key, limit) end,
      peekApply = function(S, key, limit) limits[#limits + 1] = limit; return real.peekApply(S, key, limit) end,
    }, { __index = real })
    local S = busy({ spells = { earthShock = { cd = 0 } } })
    search.evaluate(S, { { key = "earthShock", at = 5.9, reason = "" } }, { budgetMs = 1e9, model = spy })
    assert.are.near(0.1, limits[1], 1e-9)
    limits = {}
    search.best(S, { budgetMs = 1e9, model = spy })
    for _, l in ipairs(limits) do assert.is_true(l > 0 and l <= search.HORIZON + 1e-9) end
  end)

  it("mana that Shamanistic Rage returns while waiting counts too", function()
    local S = busy({ mode = "solo", spells = { lavaLash = { cd = 0 }, shamanisticRage = { cd = 0 } },
                     swing = { mh = { next = 3.2 }, oh = { next = 3.4 } } })
    local o = { budgetMs = 1e9 }
    local without = search.evaluate(S, { { key = "lavaLash", at = 0, reason = "" } }, o)
    local with = search.evaluate(S, { { key = "lavaLash", at = 0, reason = "" }, { key = "shamanisticRage", at = 1.5, reason = "" } }, o)
    assert.is_true(with > without + 100, ("with %.0f, without %.0f"):format(with, without))
  end)

  it("never plans a cast that would end after the horizon", function()
    local S = busy({ talents = { maelstromWeapon = 0 }, spells = { lightningBolt = { cd = 0 } } })
    local ct = require("model").castTime(S, "lightningBolt")
    for _, st in ipairs(search.best(S, { budgetMs = 1e9 }).steps) do
      if st.key == "lightningBolt" then assert.is_true(st.at + ct <= search.HORIZON + 1e-9, "at=" .. st.at) end
    end
  end)

  -- beam search compares chains by the number of buttons, so "small button now, big ones later"
  -- can lose the cut to "big ones later" although it is the better plan; best() tries such a
  -- button in front of a plan that starts with a wait
  it("uses the idle time before the first button for a useful one (Lightning Shield)", function()
    local S = busy({
      buffs = { ls = { charges = 0, remains = 0 } },
      spells = { stormstrike = { cd = 4 }, earthShock = { cd = 3 }, flameShock = { cd = 3 }, lavaLash = { cd = 3 }, fireNova = { cd = 4 } },
    })
    local plan = search.best(S, { budgetMs = 1e9 })
    assert.are.equal("lightningShield", plan.steps[1].key)
    assert.are.near(0, plan.steps[1].at, 1e-9)
    local v = search.evaluate(S, plan.steps, { budgetMs = 1e9 })
    assert.are.near(plan.value, v, 1e-6)
  end)

  it("level 80: a search run in 2 ms slices of a slow clock equals the whole search", function()
    local Sc = require("scenario")
    for i, S in ipairs({ Sc.state(80), busy({ buffs = { mw = { stacks = 3, remains = 20 } } }),
                         busy({ spells = { flameShock = { cd = 0 }, earthShock = { cd = 0 } }, target = { fs = 0 } }) }) do
      local whole = search.best(S)
      local t = 0
      local job = search.start(S, { clock = function() t = t + 0.3; return t end })
      local n = 1
      while not job:run(2) do n = n + 1 end
      assert.is_true(n > 1, "state " .. i .. " ran in one slice")
      assert.are.equal(keys(whole), keys(job.result), "state " .. i)
      assert.are.equal(whole.value, job.result.value, "state " .. i)
    end
  end)

  -- the best plan whose first press is `key` (only that button at the root)
  local function forcedFirst(S, key)
    local real, rootNow = require("model"), S.now
    local m = setmetatable({ actions = function(X)
      local acts = real.actions(X)
      if X.now ~= rootNow then return acts end
      local out = {}
      for _, a in ipairs(acts) do if a.key == key then out[#out + 1] = a end end
      return out
    end }, { __index = real })
    return search.best(S, { model = m })
  end

  -- review example: the beam used to keep only Chain Lightning lines, a Bolt line scored 17439
  -- against the chosen 16951
  it("nothing ready, 1 Maelstrom stack, swing in 2.0 s: no other first button leads to a better plan", function()
    local Sc = require("scenario")
    local S = Sc.state(80)
    S.totems.fire = { kind = "magma", remains = 15 }
    S.target.fs = 9
    Sc.cd(S, { stormstrike = 4, shock = 3, fireNova = 4, lavaLash = 3 })
    S.buffs.mw = { stacks = 1, remains = 20 }
    S.swing.mh.next, S.swing.oh.next = 2.0, 2.3
    local plan = search.best(S)
    for _, key in ipairs({ "lightningBolt", "chainLightning" }) do
      local f = forcedFirst(S, key)
      assert.is_true(plan.value >= f.value - 1e-6, ("%s first: %.0f, chosen %s: %.0f"):format(key, f.value, plan.steps[1].key, plan.value))
    end
    assert.are.equal("lightningBolt", plan.steps[1].key)
  end)

  -- review example: with the node cap at 220 the last layer was cut before the Flame Shock line
  -- (a diversity entry at the end of the beam) was expanded; the shown plan was Stormstrike,
  -- Chain Lightning, Lava Lash, Bolt, and after Stormstrike the list put Flame Shock in front
  it("level 80, everything ready, Flame Shock down: the plan is the full search's, Flame Shock in the first two", function()
    local Sc = require("scenario")
    local S = Sc.state(80)
    S.totems.fire = { kind = "magma", remains = 15 }
    local plan = search.best(S)
    local full = search.best(S, { nodeCap = 1e6 })
    local keys = {}
    for i, st in ipairs(plan.steps) do keys[i] = st.key end
    assert.is_true(keys[1] == "flameShock" or keys[2] == "flameShock", table.concat(keys, ", "))
    assert.are.near(full.value, plan.value, 1e-6)
    assert.are.equal(#full.steps, #plan.steps)
    for i, st in ipairs(full.steps) do assert.are.equal(st.key, plan.steps[i].key, "step " .. i) end
  end)

  -- Shamanistic Rage returns mana with every swing: a Bolt the mana cannot pay for now is
  -- possible right after the swing ("swing, then Bolt"); the replay used to check the button
  -- before the swing, so the search's own plan did not replay (the planner then searched anew
  -- on a pulse and the first button changed without an event)
  it("a weave paid by the mana of the swing before it replays to the plan's own value", function()
    local Sc = require("scenario")
    local S = Sc.state(80)
    S.totems.fire = { kind = "magma", remains = 15 }
    S.target.fs = 12
    S.player.mana = 300
    S.buffs.rage = 10
    S.buffs.mw = { stacks = 3, remains = 20 }
    Sc.cd(S, { stormstrike = 7, lavaLash = 5, shock = 4, fireNova = 6 })
    S.swing.mh.next, S.swing.oh.next = 0.5, 1.8
    assert.is_nil(require("model").readyIn(S, "lightningBolt"))
    local plan = search.best(S)
    assert.are.equal("lightningBolt", plan.steps[1].key)
    assert.is_true(plan.steps[1].afterSwing)
    assert.are.near(plan.value, search.evaluate(S, plan.steps), 1e-6)
    for f, steps in pairs(plan.byFirst) do assert.is_number(search.evaluate(S, steps), f) end
  end)

  -- the beam compares chains by button count: "Chain Lightning, then wait for Stormstrike" beat
  -- "Chain Lightning, Fire Nova in the gap, Stormstrike" at the cut; fillIdle tries the gap
  it("a wait of a GCD or more inside the plan gets a ready button", function()
    local Sc = require("scenario")
    local S = Sc.state(80)
    S.totems.fire = { kind = "magma", remains = 15 }
    S.buffs.mw = { stacks = 5, remains = 20 }
    S.target.fs = 10
    Sc.cd(S, { stormstrike = 4, shock = 3, lavaLash = 3 })
    local plan = search.best(S)
    assert.are.near(0, plan.steps[1].at, 1e-9)
    assert.is_true(plan.steps[2].at < 1.5, ("second step at %.2f"):format(plan.steps[2].at))
    local v = search.evaluate(S, plan.steps)
    assert.are.near(plan.value, v, 1e-6)
  end)

  it("an instant (5 stacks) is never planned 'after the swing'", function()
    local S = busy({ buffs = { mw = { stacks = 5, remains = 20 } },
                     swing = { attacking = true, mh = { next = 0.3, speed = 2.6 }, oh = { next = 1.5, speed = 2.6 } } })
    local plan = search.best(S)
    local first = plan.steps[1]
    assert.is_true(first.key == "lightningBolt" or first.key == "chainLightning", first.key)
    assert.is_nil(first.afterSwing)
    assert.are.near(0, first.at, 1e-9)
  end)

  -- a held "swing, then Bolt" plan shifted until the swing is 0.03 s away
  local function nearSwing(mhNext)
    return busy({ buffs = { mw = { stacks = 3, remains = 20 } },
                  swing = { attacking = true, mh = { next = mhNext, speed = 2.6 }, oh = { next = 1.5, speed = 2.6 } } })
  end

  it("replaying 'swing, then Bolt' 0.04 s before the swing still waits for the swing", function()
    local S = nearSwing(0.03)
    local v, steps = search.evaluate(S, { { key = "lightningBolt", at = 0.04, reason = "after swing - no clip", afterSwing = true } })
    assert.is_number(v)
    assert.are.near(0.04, steps[1].at, 1e-9)
    assert.is_true(steps[1].afterSwing)
    local now = search.evaluate(S, { { key = "lightningBolt", at = 0, reason = "" } })
    assert.is_true(v > now, ("after the swing %.0f, now %.0f"):format(v, now))
  end)

  it("a planned wait shorter than READY_EPS is kept, not turned into 'press now'", function()
    local _, steps = search.evaluate(nearSwing(0.03), { { key = "lightningBolt", at = 0.02, reason = "" } })
    assert.are.near(0.02, steps[1].at, 1e-9)
  end)

  it("a swing that comes later than planned is still waited for; one already done is not", function()
    local _, late = search.evaluate(nearSwing(0.08), { { key = "lightningBolt", at = 0.04, reason = "", afterSwing = true } })
    assert.are.near(0.08 + require("model").WAIT_SWING_PAD, late[1].at, 1e-9)
    local _, done = search.evaluate(nearSwing(2.5), { { key = "lightningBolt", at = 0.02, reason = "", afterSwing = true } })
    assert.are.near(0.02, done[1].at, 1e-9)
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
    assert.are.equal("3 stacks, fits before swing", plan.steps[1].reason)
    assert.is_true(plan.steps[1].afterSwing)
  end)
end)


describe("search: a mob running in (target.meleeIn)", function()
  local util = require("util")

  local function coming(range)
    local Sc = require("scenario")
    local S = Sc.state(54, { enemies = { melee = 0, nearby = 1 } })
    S.target.range, S.target.inCombat, S.target.meleeIn = range, true, util.approachEta(range)
    return S
  end

  it("the signature tells where the mob is and when it arrives", function()
    local S = fixtures.state({ mode = "solo", target = { range = "20" } })
    local sig = search.signature(S)
    S.target.meleeIn = 2
    local coming2 = search.signature(S)
    S.target.meleeIn = 1
    local coming1 = search.signature(S)
    S.target.meleeIn, S.target.range = nil, "melee"
    local arrived = search.signature(S)
    assert.are_not.equal(sig, coming2)
    assert.are_not.equal(coming2, coming1)
    assert.are_not.equal(sig, arrived)
    assert.are_not.equal(coming1, arrived)
  end)

  it("a plan with the mob's arrival replays to its own value; sliced search = whole search", function()
    for _, range in ipairs({ "30", "20" }) do
      local S = coming(range)
      local plan = search.best(S)
      local melee = false
      for _, st in ipairs(plan.steps) do
        if st.key == "stormstrike" or st.key == "lavaLash" then
          melee = true
          assert.is_true(st.at >= S.target.meleeIn - 1e-9, st.key .. " before the mob arrives")
        end
      end
      assert.is_true(melee, range)
      local v = search.evaluate(S, plan.steps)
      assert.are.near(plan.value, v, 1e-6)
      local job = search.start(S)
      while not job:run(0.01) do end
      assert.are.equal(keys(plan), keys(job.result))
      assert.are.near(plan.value, job.result.value, 1e-9)
    end
  end)
end)
