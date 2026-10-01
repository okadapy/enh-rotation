local fightlog = require("fightlog")

-- a collector over fake deps: a clock, the engine's state and due button, the boss and target
local function rig(over)
  local w = { t = 0, S = nil, due = nil, boss = nil, target = "Kobold", diff = "25 Player" }
  local deps = {
    now = function() return w.t end,
    state = function() return w.S end,
    due = function() return w.due end,
    boss = function() return w.boss end,
    targetName = function() return w.target end,
    difficulty = function() return w.diff end,
  }
  for k, v in pairs(over or {}) do deps[k] = v end
  w.F = fightlog.new(deps)
  return w
end

-- an engine state in melee of an enemy, every check passing (shield, totem, enchants, swinging)
local function melee(over)
  local S = { now = 0, gcdRemains = 0, castRemains = 0,
              buffs = { mw = { stacks = 0 } }, player = { shield = "lightning" },
              spells = { flameShock = {}, lightningShield = {}, searingTotem = {} },
              target = { exists = true, enemy = true, range = "melee", fs = 10 },
              totems = { fire = { remains = 30 } },
              weapons = { mh = { enchant = "wf" }, oh = { enchant = "ft" } },
              swing = { attacking = true } }
  for k, v in pairs(over or {}) do S[k] = v end
  return S
end

local function last(t, fv, s) return { now = t, value = 0, firstValue = fv, s = s or { now = t } } end

-- n presses of the suggested button, one a second from t
local function hits(w, n, t)
  for i = 1, n do
    w.t = t + i
    w.F:press({ t = w.t, key = "stormstrike", sug = "stormstrike", due = w.t, last = last(w.t, { stormstrike = 60 }) })
  end
end

describe("addon fight collector", function()
  it("exports the option and the thresholds", function()
    assert.are.same({ type = "toggle", key = "fightSummary", name = "Fight summary in chat after a fight", default = true },
      fightlog.OPTION)
    assert.are.equal(20, fightlog.MIN_SECONDS)
    assert.are.equal(10, fightlog.MIN_PRESSES)
    assert.are.equal(0.5, fightlog.STALE)
    assert.are.equal(1.5, fightlog.LATE)
    assert.are.equal(30, fightlog.MAX_COPIES)
  end)

  it("gives nothing for a fight that never began (a /reload in combat)", function()
    local w = rig()
    w.F:press({ t = 1, key = "stormstrike", sug = "stormstrike" })
    w.F:tick(1)
    assert.is_nil(w.F:finish())
  end)

  it("gives nothing below 20 s or 10 presses", function()
    local w = rig()
    w.F:begin(); hits(w, 12, 0); w.t = 19
    assert.is_nil(w.F:finish())
    w.t = 0
    w.F:begin(); hits(w, 9, 0); w.t = 30
    assert.is_nil(w.F:finish())
  end)

  it("counts matches, the mean delay and its late presses apart", function()
    local w = rig()
    w.F:begin()
    hits(w, 10, 0)
    w.t = 11.2 -- 0.2 s after due
    w.F:press({ t = 11.2, key = "stormstrike", sug = "stormstrike", due = 11, last = last(11.2, { stormstrike = 60 }) })
    w.t = 14 -- 2 s after due: late
    w.F:press({ t = 14, key = "lavaLash", sug = "stormstrike", due = 12, last = last(14, { stormstrike = 60, lavaLash = 10 }) })
    w.t = 25
    local f = w.F:finish()
    assert.are.equal(12, f.presses)
    assert.are.equal(12, f.suggested)
    assert.are.equal(11, f.matched)
    assert.are.near(11 / 12, f.rate, 1e-9)
    assert.are.equal(1, f.late)
    assert.are.near(0.2 / 11, f.delay, 1e-9)
    assert.are.equal(0, f.lost) -- the late press is not priced
    assert.are.equal(25, f.seconds)
  end)

  it("prices a wrong press by the best first button's score, the +swing chain counted too", function()
    local w = rig()
    w.F:begin()
    hits(w, 10, 0)
    w.t = 12
    w.F:press({ t = 12, key = "lavaLash", sug = "stormstrike", due = 12,
                last = last(11.8, { stormstrike = 100, lavaLash = 70, ["lavaLash+swing"] = 80 }) })
    w.t = 30
    local f = w.F:finish()
    assert.are.equal(20, f.lost)
    assert.are.same({ sug = "stormstrike", key = "lavaLash", count = 1, lost = 20 }, f.pairs["stormstrike>lavaLash"])
  end)

  it("does not price a press against a stale plan, nor one with no suggestion", function()
    local w = rig()
    w.F:begin()
    hits(w, 10, 0)
    w.t = 12
    w.F:press({ t = 12, key = "lavaLash", sug = "stormstrike", due = 12, last = last(11.4, { stormstrike = 100, lavaLash = 70 }) })
    w.F:press({ t = 12.5, key = "lavaLash" })
    w.t = 30
    local f = w.F:finish()
    assert.are.equal(1, f.stale)
    assert.are.equal(0, f.lost)
    assert.are.equal(12, f.presses)
    assert.are.equal(11, f.suggested)
  end)

  it("keeps a copy of the searched state for a button the search had no chain for, at most 30", function()
    local w = rig()
    w.F:begin()
    hits(w, 10, 0)
    local s = { now = 12, deep = { x = 1 } }
    for i = 1, 32 do
      w.F:press({ t = 12, key = "frostShock", sug = "stormstrike", due = 12,
                  last = last(12, { stormstrike = 100, ["stormstrike+swing"] = 90 }, s) })
    end
    w.t = 30
    local f = w.F:finish()
    assert.are.equal(30, #f.pending)
    assert.are.equal(2, f.unrated)
    assert.are_not.equal(s, f.pending[1].s)
    assert.are.same(s, f.pending[1].s)
    assert.are.equal("stormstrike", f.pending[1].best)
    assert.are.equal("frostShock", f.pending[1].key)
  end)

  it("settles the copied presses one a call, and abandons the rest", function()
    local w = rig()
    w.F:begin()
    hits(w, 10, 0)
    for i = 1, 3 do
      w.F:press({ t = 12, key = "frostShock", sug = "stormstrike", due = 12, last = last(12, { stormstrike = 100 }) })
    end
    w.t = 30
    local f = w.F:finish()
    local values = { stormstrike = 100, frostShock = 60 }
    local function evaluate(_, steps) return values[steps[1].key] end
    assert.is_false(fightlog.settle(f, evaluate))
    assert.are.equal(40, f.lost)
    assert.are.equal(40, f.pairs["stormstrike>frostShock"].lost)
    values.frostShock = nil -- no longer possible: not rated
    assert.is_false(fightlog.settle(f, evaluate))
    assert.are.equal(1, f.unrated)
    fightlog.abandon(f)
    assert.are.equal(2, f.unrated)
    assert.is_true(fightlog.settle(f, evaluate))
  end)

  it("samples idle 5 stacks, idle GCD, Flame Shock and the preparation every 0.5 s", function()
    local w = rig()
    w.F:begin()
    hits(w, 10, 0)
    w.S = melee({ buffs = { mw = { stacks = 5 } }, player = {}, totems = { fire = { remains = 0 } },
                  weapons = { mh = { enchant = "wf" }, oh = {} }, swing = { attacking = false },
                  target = { exists = true, enemy = true, range = "melee", fs = 0 } })
    w.due = { key = "lightningBolt", at = 10 }
    w.t = 11
    w.F:tick(0.3) -- not a sample yet
    w.F:tick(0.3) -- a sample of 0.6 s
    w.t = 30
    local f = w.F:finish()
    assert.are.near(0.6, f.mw.idle, 1e-9)
    assert.are.near(0.6, f.gcdIdle, 1e-9)
    assert.are.near(0.6, f.fs.seen, 1e-9)
    assert.are.equal(0, f.fs.up)
    assert.are.same({ shield = 0.6, totems = 0.6, enchants = 0.6, autoAttack = 0.6 }, f.prep)
  end)

  it("a plan waiting for a swing is no idle GCD; a cast is no idle 5 stacks", function()
    local w = rig()
    w.F:begin()
    hits(w, 10, 0)
    w.S = melee({ buffs = { mw = { stacks = 5 } }, castRemains = 1 })
    w.due = { key = "lightningBolt", at = 12 } -- due later: the plan waits
    w.t = 11
    w.F:tick(0.5)
    w.t = 30
    local f = w.F:finish()
    assert.are.equal(0, f.gcdIdle)
    assert.are.equal(0, f.mw.idle)
  end)

  it("skips samples while the engine has no state", function()
    local w = rig()
    w.F:begin()
    hits(w, 10, 0)
    w.F:tick(1)
    w.t = 30
    local f = w.F:finish()
    assert.are.equal(0, f.gcdIdle)
    assert.are.equal(0, f.fs.seen)
  end)

  it("counts a Maelstrom stack that came at 5 as wasted", function()
    local w = rig()
    w.F:begin()
    w.F:aura("SPELL_AURA_APPLIED")
    for n = 2, 5 do w.F:aura("SPELL_AURA_APPLIED_DOSE", n) end
    w.F:aura("SPELL_AURA_APPLIED_DOSE", 5)
    w.F:aura("SPELL_AURA_REFRESH")
    w.F:aura("SPELL_AURA_REMOVED")
    w.F:aura("SPELL_AURA_REFRESH")
    hits(w, 10, 0)
    w.t = 30
    assert.are.equal(2, w.F:finish().mw.wasted)
  end)

  it("starts from the stacks already up when the fight begins", function()
    local w = rig()
    w.S = melee({ buffs = { mw = { stacks = 5 } } })
    w.F:begin()
    w.F:aura("SPELL_AURA_REFRESH")
    hits(w, 10, 0)
    w.t = 30
    assert.are.equal(1, w.F:finish().mw.wasted)
  end)

  it("counts hard casts in melee as delayed swings", function()
    local w = rig()
    w.F:begin()
    w.t = 10
    w.S = melee({ now = 10, swing = { attacking = true, mh = { next = 1 } } })
    w.F:castStart(2.5) -- ends 1.5 s after the swing: delayed
    w.F:castStart(0) -- instant
    w.F:castStart(0.5) -- ends before the swing (weaving): not delayed
    w.S = melee({ now = 10, swing = { attacking = true, mh = { next = 1 } }, target = { exists = true, enemy = true, range = "30" } })
    w.F:castStart(2.5) -- at range: no swing to delay
    hits(w, 10, 0)
    w.t = 30
    assert.are.equal(1, w.F:finish().swings)
  end)

  it("names a boss fight with its difficulty, else the most seen target as trash", function()
    local w = rig()
    w.F:begin()
    hits(w, 10, 0)
    w.boss = "Lord Marrowgar"
    w.F:tick(0.5)
    w.t = 30
    local f = w.F:finish()
    assert.are.equal("Lord Marrowgar", f.name)
    assert.are.equal("Lord Marrowgar 25 Player", f.key)
    assert.is_nil(f.trash)

    w.boss = nil
    w.t = 0
    w.F:begin()
    hits(w, 10, 0)
    w.target = "Kobold"; w.F:tick(0.5); w.F:tick(0.5)
    w.target = "Gnoll"; w.F:tick(0.5)
    w.t = 30
    f = w.F:finish()
    assert.are.equal("Kobold", f.name)
    assert.is_true(f.trash)
    assert.is_nil(f.key)
  end)

  it("names a fight with no target at all Unknown", function()
    local w = rig()
    w.target = nil
    w.F:begin()
    hits(w, 10, 0)
    w.F:tick(0.5)
    w.t = 30
    local f = w.F:finish()
    assert.are.equal("Unknown", f.name)
    assert.is_true(f.trash)
  end)

  it("keeps the plan's damage per second: the mean best score over the horizon", function()
    local w = rig()
    w.F:begin()
    hits(w, 10, 0) -- best 60 each
    w.t = 30
    assert.are.near(60 / 6, w.F:finish().dps, 1e-9)
  end)
end)
