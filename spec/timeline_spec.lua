local G = require("game_mock")
local spells = require("spells")

-- timeline only needs model.castTime; a fake keeps this spec independent of the real model
local realModel = package.loaded.model
local model = { castTime = function() return 1.0 end }
package.loaded.model = model
local timeline = require("timeline")
package.loaded.model = realModel

local function S(patch)
  local s = {
    now = 100, gcdRemains = 0, latency = 0.15,
    buffs = { mw = { stacks = 3, remains = 20 } },
    spells = { lightningBolt = { id = 49238, rank = 14, cd = 0, cost = 400, cast = 2.5 } },
    swing = { attacking = true, mh = { next = 1.0, speed = 2.6 }, oh = { next = 0.4, speed = 2.6 } },
  }
  for k, v in pairs(patch or {}) do s[k] = v end
  return s
end

local function plan(...)
  local steps = {}
  for i, st in ipairs({ ... }) do steps[i] = { key = st[1], at = st[2], reason = st[3] } end
  return { value = 1, steps = steps }
end

describe("timeline layout", function()
  local realCast
  before_each(function()
    realCast = model.castTime
    model.castTime = function() return 1.0 end
  end)
  after_each(function() model.castTime = realCast end)

  it("maps seconds onto the scale", function()
    local o = timeline.options({})
    assert.are.equal(60, timeline.xOf(0, o))
    assert.are.equal(340, timeline.xOf(6, o))
    assert.are.equal(200, timeline.xOf(3, o))
  end)

  it("puts the first action on the now line and the rest at their times", function()
    local L = timeline.layout(plan({ "stormstrike", 0, "Stormstrike" }, { "waitSwing", 1.0 }, { "lavaLash", 1.5 },
      { "lightningBolt", 2.4 }, { "earthShock", 3.0 }, { "fireNova", 4.5 }), S(), { icons = 3 }, 0)
    assert.are.equal(3, #L.icons)
    assert.are.same({ "stormstrike", "lavaLash", "lightningBolt" }, { L.icons[1].key, L.icons[2].key, L.icons[3].key })
    assert.is_true(L.icons[1].big)
    assert.are.equal(64, L.icons[1].size)
    assert.are.equal(60, L.icons[1].x)
    assert.are.near(130, L.icons[2].x, 1e-9)
    assert.are.near(172, L.icons[3].x, 1e-9)
    assert.are.equal(spells.byKey.stormstrike.icon, L.icons[1].icon)
    assert.are.equal("Stormstrike", L.reason)
  end)

  it("keeps the rest of the plan in place while the first button is overdue", function()
    local p = plan({ "stormstrike", 0.2 }, { "lavaLash", 1.7 }, { "lightningBolt", 3.2 })
    local on = timeline.layout(p, S(), {}, 0.2)
    local late = timeline.layout(p, S(), {}, 0.6) -- pressed 0.4 s late: nothing moves
    assert.are.equal(60, late.icons[1].x)
    assert.are.near(on.icons[2].x, late.icons[2].x, 1e-9)
    assert.are.near(on.icons[3].x, late.icons[3].x, 1e-9)
    local before = timeline.layout(p, S(), {}, 0.1) -- before it is due, all run down
    assert.is_true(before.icons[2].x > on.icons[2].x)
  end)

  it("pushes overlapping icons to the right", function()
    local L = timeline.layout(plan({ "stormstrike", 0 }, { "lavaLash", 0.3 }), S(), {}, 0)
    assert.are.near(113, L.icons[2].x, 1e-9)
  end)

  it("lists future swings of both hands in time order", function()
    local t = timeline.swingTimes(S(), 6)
    local got = {}
    for i, s in ipairs(t) do got[i] = s.hand .. "@" .. s.t end
    assert.are.same({ "oh@0.4", "mh@1", "oh@3", "mh@3.6", "oh@5.6" }, got)
    assert.are.same({}, timeline.swingTimes(S({ swing = { attacking = false, mh = { next = 1, speed = 2.6 } } }), 6))
  end)

  it("works with a single two-handed weapon", function()
    local t = timeline.swingTimes(S({ swing = { attacking = true, mh = { next = 0.5, speed = 3.5 } } }), 6)
    assert.are.equal(2, #t)
    assert.are.equal("mh", t[2].hand)
  end)

  it("finds the first gap between swings that fits the cast", function()
    local a, b = timeline.castWindow(S(), timeline.swingTimes(S(), 6))
    assert.are.near(1.0, a, 1e-9)
    assert.are.near(1.85, b, 1e-9)
  end)

  it("shows no cast window at 0 or 5 Maelstrom stacks", function()
    local s0 = S({ buffs = { mw = { stacks = 0, remains = 0 } } })
    assert.is_nil(timeline.castWindow(s0, timeline.swingTimes(s0, 6)))
    local s5 = S({ buffs = { mw = { stacks = 5, remains = 10 } } })
    assert.is_nil(timeline.castWindow(s5, timeline.swingTimes(s5, 6)))
  end)

  it("slides ticks, window and GCD band left as time passes", function()
    local L = timeline.layout(plan({ "stormstrike", 0 }), S({ gcdRemains = 1.2 }), {}, 0.5)
    assert.are.equal("mh", L.ticks[1].hand)
    assert.are.near(0.5, L.ticks[1].t, 1e-9)
    assert.are.near(0.5, L.window.t1, 1e-9)
    assert.are.equal(60, L.gcd.x1)
    assert.are.near(timeline.xOf(0.7, timeline.options({})), L.gcd.x2, 1e-9)
    assert.is_nil(timeline.layout(plan(), S({ gcdRemains = 1.2 }), {}, 1.5).gcd)
  end)

  it("counts Maelstrom dots", function()
    assert.are.equal(3, timeline.layout(plan(), S(), {}, 0).dots)
    assert.are.equal(5, timeline.layout(plan(), S({ buffs = { mw = { stacks = 7, remains = 1 } } }), {}, 0).dots)
  end)
end)

describe("timeline render", function()
  local realCast
  before_each(function()
    G.install({ now = 100 })
    realCast = model.castTime
    model.castTime = function() return 1.0 end
  end)
  after_each(function() model.castTime = realCast end)

  it("draws icons, glow and hides unused slots", function()
    local tl = timeline.new(CreateFrame("Frame"), { icons = 4 })
    tl:render(plan({ "stormstrike", 0, "Stormstrike" }, { "lavaLash", 1.5 }), S(), 100)
    tl.frame.scripts.OnUpdate(tl.frame, 0.016)
    assert.is_true(tl.icons[1].shown)
    assert.are.equal(spells.byKey.stormstrike.icon, tl.icons[1].texture)
    assert.is_true(tl.glow.shown)
    assert.is_false(tl.icons[3].shown)
    assert.are.equal("Stormstrike", tl.reason.text)
  end)

  it("glides an icon to its new place instead of jumping", function()
    local tl = timeline.new(CreateFrame("Frame"), {})
    tl:render(plan({ "stormstrike", 0 }, { "lavaLash", 1.5 }), S(), 100)
    tl:tick(0.016)
    assert.are.near(130, tl.cur.lavaLash, 1e-9)
    tl:render(plan({ "stormstrike", 0 }, { "lavaLash", 3.0 }), S(), 100)
    tl:tick(0.05)
    assert.are.near(172, tl.cur.lavaLash, 1e-9)
  end)

  it("shows and hides the alert icon", function()
    local tl = timeline.new(CreateFrame("Frame"), {})
    tl:setAlert({ icon = "Interface\\Icons\\X" })
    assert.is_true(tl.alert.shown)
    assert.are.equal("Interface\\Icons\\X", tl.alert.texture)
    tl:setAlert(nil)
    assert.is_false(tl.alert.shown)
  end)

  it("hides the reason text when the option is off", function()
    local tl = timeline.new(CreateFrame("Frame"), { showReason = false })
    tl:render(plan({ "stormstrike", 0, "Stormstrike" }), S(), 100)
    tl:tick(0.016)
    assert.is_false(tl.reason.shown)
  end)

  it("glides two copies of the same spell separately", function()
    local tl = timeline.new(CreateFrame("Frame"), {})
    tl:render(plan({ "lightningBolt", 0 }, { "lightningBolt", 3.0 }), S(), 100)
    tl:tick(0.016)
    assert.are.equal(60, tl.cur.lightningBolt)
    assert.are.near(200, tl.cur["lightningBolt#2"], 1e-9)
  end)

  it("draws an empty plan with a two-hander without errors", function()
    local tl = timeline.new(CreateFrame("Frame"), {})
    tl:render({ value = 0, steps = {} }, S({ swing = { attacking = true, mh = { next = 0.5, speed = 3.5 } },
      buffs = { mw = { stacks = 0, remains = 0 } } }), 100)
    tl:tick(0.016)
    assert.is_false(tl.icons[1].shown)
    assert.is_false(tl.glow.shown)
    assert.is_false(tl.reason.shown)
    assert.is_false(tl.window.shown)
    assert.are.equal(2, #tl.ticks)
  end)

  it("reuses an old timeline: same frame, no new textures, new options", function()
    local parent = CreateFrame("Frame")
    local tl = timeline.new(parent, { icons = 4 })
    local n = #tl.frame.children
    local other = CreateFrame("Frame")
    local tl2 = timeline.new(other, { icons = 2 }, tl)
    assert.are.equal(tl, tl2)
    assert.are.equal(other, tl.frame.parent)
    assert.are.equal(2, #tl.icons)
    assert.are.equal(n, #tl.frame.children)
    timeline.new(other, { icons = 4 }, tl)
    assert.are.equal(4, #tl.icons)
    assert.are.equal(n, #tl.frame.children)
  end)

  it("a tick that dies half-way stops the timeline instead of failing every frame", function()
    local tl = timeline.new(CreateFrame("Frame"), {})
    local reported = 0
    tl.onError = function() reported = reported + 1 end
    tl.tick = function() error("boom") end
    assert.has_error(function() tl.frame.scripts.OnUpdate(tl.frame, 0.02) end)
    tl.frame.scripts.OnUpdate(tl.frame, 0.02)
    assert.are.equal(1, reported)
    assert.is_nil(tl.frame.scripts.OnUpdate)
    assert.is_false(tl.frame.shown)
  end)
end)
