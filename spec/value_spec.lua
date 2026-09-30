local value = require("value")
local stubs = require("stubs")
local fixtures = require("fixtures")
local util = require("util")

local function after(S, hp)
  local S2 = util.copy(S)
  S2.target.hp = hp
  return S2
end

local saved, damage
before_each(function()
  saved = package.loaded.damage
  damage = stubs.damage()
  package.loaded.damage = damage
end)
after_each(function() package.loaded.damage = saved end)

describe("value.step", function()
  it("solo: damage above the target's remaining health is worth nothing, killing gives a bonus", function()
    local S = fixtures.state({ mode = "solo", target = { hp = 500, hpMax = 10000 } })
    local v = value.step(S, after(S, 0), 2000, 0)
    assert.are.near(500 + value.WEIGHTS.solo.kill * 10000, v, 1e-6)
  end)

  it("group: overkill counts at 0.2 and there is no kill bonus", function()
    local S = fixtures.state({ mode = "group", target = { hp = 500, hpMax = 10000 } })
    local v = value.step(S, after(S, 0), 2000, 0)
    assert.are.near(500 + 1500 * 0.2, v, 1e-6)
  end)

  it("subtracts spent mana at the mode's price and rewards mana gained", function()
    local S = fixtures.state({ mode = "solo" })
    local price = value.manaPrice(S)
    assert.are.near(1000 - 300 * price, value.step(S, after(S, S.target.hp - 1000), 1000, 300), 1e-6)
    assert.are.near(1000 + 300 * price, value.step(S, after(S, S.target.hp - 1000), 1000, -300), 1e-6)
  end)

  it("solo: a target that is already dead gives neither damage nor a second kill bonus", function()
    local S = fixtures.state({ mode = "solo", target = { hp = 0, hpMax = 10000 } })
    assert.are.near(0, value.step(S, after(S, 0), 2000, 0), 1e-9)
  end)

  it("pvp uses group weights", function()
    assert.are.same(value.WEIGHTS.group, value.WEIGHTS.pvp)
  end)
end)

describe("value.manaPrice", function()
  it("solo: mana gets more expensive as it runs low", function()
    local full = fixtures.state({ mode = "solo", player = { mana = 10000, manaMax = 10000 } })
    local low = fixtures.state({ mode = "solo", player = { mana = 2000, manaMax = 10000 } })
    assert.is_true(value.manaPrice(low) > value.manaPrice(full) * 2)
  end)

  -- solo, mana that runs out costs drinking time: a full bar is worth SOLO_REGEN seconds of damage
  it("solo: a full bar of mana is worth SOLO_REGEN seconds of the character's damage", function()
    local S = fixtures.state({ mode = "solo", player = { mana = 10000, manaMax = 10000 }, spells = { shamanisticRage = { cd = 0 } } })
    local dps = (damage.auto(S, "mh") / S.swing.mh.speed + damage.auto(S, "oh") / S.swing.oh.speed) * value.MELEE_SHARE
    assert.are.near(value.SOLO_REGEN * dps, value.manaPrice(S) * 10000, 1e-6)
  end)

  it("solo: mana is dearer while Shamanistic Rage is on cooldown", function()
    local ready = fixtures.state({ mode = "solo", spells = { shamanisticRage = { cd = 0 } } })
    local onCd = fixtures.state({ mode = "solo", spells = { shamanisticRage = { cd = 30 } } })
    assert.are.near(value.manaPrice(ready) * 1.5, value.manaPrice(onCd), 1e-9)
  end)

  it("group: nearly free unless the fight outlasts the mana", function()
    local fine = fixtures.state({ mode = "group", player = { mana = 9000, manaMax = 10000 }, target = { ttd = 60 } })
    local oom = fixtures.state({ mode = "group", player = { mana = 1000, manaMax = 10000 }, target = { ttd = 60 } })
    local solo = fixtures.state({ mode = "solo", player = { mana = 9000, manaMax = 10000 } })
    assert.is_true(value.manaPrice(fine) < value.manaPrice(solo) * 0.1)
    assert.is_true(value.manaPrice(oom) > value.manaPrice(fine) * 5)
  end)

  it("group: a long boss fight at 80% mana is no reason to save mana", function()
    local S = fixtures.state({ mode = "raid", player = { mana = 8000, manaMax = 10000 }, target = { ttd = 180 } })
    local fine = fixtures.state({ mode = "raid", player = { mana = 9000, manaMax = 10000 }, target = { ttd = 60 } })
    assert.are.near(value.manaPrice(fine), value.manaPrice(S), 1e-12)
  end)

  it("unknown mode falls back to group weights", function()
    local S = fixtures.state({ mode = "weird" })
    local G = fixtures.state({ mode = "group" })
    assert.are.near(value.manaPrice(G), value.manaPrice(S), 1e-12)
  end)
end)

describe("value.terminal", function()
  local function base(over)
    -- Fire Nova just pressed (full 10 s cooldown) so a fire totem does not also add Fire Nova value
    -- no water totem either: the support-totem value has a test of its own
    local o = { totems = { fire = { kind = false, remains = 0 }, water = { remains = 0 } }, target = { fs = 0 }, buffs = { mw = { stacks = 0, remains = 0 } },
                spells = { fireNova = { cd = 10 } } }
    for k, v in pairs(over or {}) do o[k] = v end
    o.totems.water = o.totems.water or { remains = 0 }
    return fixtures.state(o)
  end

  it("more Maelstrom stacks are worth more", function()
    local s0 = base()
    local s4 = base({ buffs = { mw = { stacks = 4, remains = 20 } } })
    local lb = damage.action(s4, "lightningBolt")
    -- future damage like a ready button, so at the same discount
    assert.are.near(4 * value.MW_SHARE * lb * value.DISCOUNT, value.terminal(s4) - value.terminal(s0), 1e-6)
  end)

  it("counts how far each hand's swing has come: a delayed swing is lost auto-attack time", function()
    local function at(mh, oh) return base({ swing = { attacking = true, mh = { next = mh, speed = 2.6 }, oh = { next = oh, speed = 2.6 } } }) end
    local fresh, near = at(2.6, 2.6), at(0.26, 1.3)
    local expect = 0.9 * damage.auto(near, "mh") + 0.5 * damage.auto(near, "oh")
    assert.are.near(expect, value.terminal(near) - value.terminal(fresh), 1e-6)
    local idle = at(0.26, 1.3); idle.swing.attacking = false
    assert.are.near(value.terminal(fresh), value.terminal(idle), 1e-6)
  end)

  it("counts remaining Flame Shock damage at the discount, limited by time to die", function()
    local long = base({ target = { fs = 9, ttd = 60 } })
    local short = base({ target = { fs = 9, ttd = 3 } })
    local dps = damage.periodic(long, "flameShock")
    -- 9 s vs 3 s of ticking, both at DISCOUNT 0.5
    assert.are.near(6 * dps * value.DISCOUNT, value.terminal(long) - value.terminal(short), 1e-6)
  end)

  it("a dead target is worth no remaining DoT damage", function()
    local dead = base({ target = { fs = 9, dead = true } })
    local none = base({ target = { dead = true } })
    assert.are.near(value.terminal(none), value.terminal(dead), 1e-9)
  end)

  it("a ready Stormstrike is worth half of pressing it", function()
    local ready = base({ spells = { stormstrike = { cd = 0 } } })
    local onCd = base({ spells = { stormstrike = { cd = 8 } } }) -- just pressed: full 8 s cooldown
    local ss = damage.action(ready, "stormstrike")
    assert.are.near(ss * value.DISCOUNT, value.terminal(ready) - value.terminal(onCd), 1e-6)
  end)

  it("a button on cooldown keeps the part of its value it has already recovered", function()
    local fresh = base({ spells = { stormstrike = { cd = 8 } } })
    local soon = base({ spells = { stormstrike = { cd = 2 } } })
    local ss = damage.action(soon, "stormstrike")
    assert.are.near(ss * value.DISCOUNT * 6 / 8, value.terminal(soon) - value.terminal(fresh), 1e-6)
  end)

  it("a ready Fire Nova counts only with a fire totem down", function()
    local noTotem = base({ spells = { fireNova = { cd = 0 } } })
    local other = base({ spells = { fireNova = { cd = 0 } }, totems = { fire = { kind = "other", remains = 10 } } })
    local onCd = base({ spells = { fireNova = { cd = 10 } }, totems = { fire = { kind = "other", remains = 10 } } })
    assert.are.near(damage.action(other, "fireNova") * value.DISCOUNT, value.terminal(other) - value.terminal(onCd), 1e-6)
    assert.are.near(value.terminal(onCd), value.terminal(noTotem), 1e-6)
  end)

  it("after the target died a fire totem no longer makes Fire Nova worth more", function()
    local none = base({ spells = { fireNova = { cd = 0 } }, target = { dead = true } })
    local totem = base({ spells = { fireNova = { cd = 0 } }, target = { dead = true }, totems = { fire = { kind = "searing", remains = 50 } } })
    assert.are.near(value.terminal(none), value.terminal(totem), 1e-6)
  end)

  it("an active Magma Totem adds its remaining pulses", function()
    local none = base()
    local magma = base({ totems = { fire = { kind = "magma", remains = 10 } } })
    assert.are.near(10 * damage.periodic(magma, "magmaTotem") * value.DISCOUNT,
      value.terminal(magma) - value.terminal(none), 1e-6)
  end)

  it("Fire Elemental and wolves add their remaining damage", function()
    local none = base()
    local fe = base({ totems = { fire = { kind = "fireElemental", remains = 4 } } })
    local wolves = base({ pets = { wolves = 5 } })
    assert.are.near(4 * damage.periodic(fe, "fireElemental") * value.DISCOUNT, value.terminal(fe) - value.terminal(none), 1e-6)
    assert.are.near(5 * damage.periodic(wolves, "feralSpirit") * value.DISCOUNT, value.terminal(wolves) - value.terminal(none), 1e-6)
  end)

  it("remaining totem and DoT time counts only up to TAIL seconds: the button can be pressed again later", function()
    local tail = base({ totems = { fire = { kind = "searing", remains = value.TAIL } } })
    local long = base({ totems = { fire = { kind = "searing", remains = 50 } } })
    assert.is_true(value.TAIL >= 10 and value.TAIL < 20)
    assert.are.near(value.terminal(tail), value.terminal(long), 1e-6)
    local fs = base({ target = { fs = value.TAIL + 6, ttd = 60 } })
    assert.are.near(value.TAIL * damage.periodic(fs, "flameShock") * value.DISCOUNT, value.terminal(fs) - value.terminal(base()), 1e-6)
  end)

  it("support totems (the water slot stands for the set) are worth a share of auto-attack damage", function()
    local short = base({ totems = { fire = { kind = false, remains = 0 }, water = { remains = 2 } } })
    local long = base({ totems = { fire = { kind = false, remains = 0 }, water = { remains = 200 } } })
    local dps = damage.auto(long, "mh") / long.swing.mh.speed + damage.auto(long, "oh") / long.swing.oh.speed
    assert.is_true(value.SUPPORT > 0 and value.SUPPORT <= 0.1)
    assert.are.near((value.TAIL - 2) * value.SUPPORT * dps * value.DISCOUNT, value.terminal(long) - value.terminal(short), 1e-6)
  end)

  it("survives a state without pets, spells, totems or auto-attack", function()
    local S = base()
    S.pets, S.spells = nil, {}
    S.swing.attacking = false
    S.totems.water = nil
    assert.are.equal(0, value.terminal(S))
  end)
end)

describe("value on the real damage module #integration", function()
  before_each(function() package.loaded.damage = saved end)

  it("remaining Magma Totem and Flame Shock are worth something", function()
    local S0 = fixtures.state({ totems = { fire = { kind = false, remains = 0 } }, target = { fs = 0 } })
    local S1 = fixtures.state({ totems = { fire = { kind = "magma", remains = 10 } }, target = { fs = 9 } })
    assert.is_true(value.terminal(S1) > value.terminal(S0))
  end)
end)
