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

  it("solo: a target that dies at its time-to-die inside the step is a kill too, and only once", function()
    -- the model stops counting damage at the time-to-die: the target is dead with health left
    local S = fixtures.state({ mode = "solo", target = { hp = 900, hpMax = 10000 } })
    local S2 = after(S, 400)
    S2.target.dead = true
    assert.are.near(500 + value.WEIGHTS.solo.kill * 10000, value.step(S, S2, 500, 0), 1e-6)
    local S3 = after(S2, 400)
    assert.are.near(0, value.step(S2, S3, 0, 0), 1e-9)
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

  -- the search presses in the buffer of the wait before: it takes the price first and passes it
  it("a price given by the caller is used instead of manaPrice(S), with the same result", function()
    local S = fixtures.state({ mode = "solo", target = { hp = 500, hpMax = 10000 } })
    local S2 = after(S, 0)
    local price = value.manaPrice(S)
    assert.are.equal(value.step(S, S2, 2000, 300), value.step(S, S2, 2000, 300, price))
    local pre = { mode = S.mode, target = { hp = S.target.hp, hpMax = S.target.hpMax, dead = S.target.dead } }
    assert.are.equal(value.step(S, S2, 2000, 300), value.step(pre, S2, 2000, 300, price))
    assert.are.near(value.step(S, S2, 2000, 0) - 300 * 2 * price, value.step(S, S2, 2000, 300, 2 * price), 1e-6)
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
  -- drinking is linear: the last mana point costs the same seconds of drinking as the first
  it("solo: the price does not depend on how full the bar is or on Shamanistic Rage", function()
    local full = fixtures.state({ mode = "solo", player = { mana = 10000, manaMax = 10000 }, spells = { shamanisticRage = { cd = 0 } } })
    local low = fixtures.state({ mode = "solo", player = { mana = 800, manaMax = 10000 }, spells = { shamanisticRage = { cd = 40 } } })
    assert.are.near(value.manaPrice(full), value.manaPrice(low), 1e-9)
  end)

  -- solo, mana that runs out costs drinking time: a point is 1 / drinkRate seconds of damage
  it("solo: a mana point is worth the character's damage over the seconds it takes to drink", function()
    local S = fixtures.state({ mode = "solo", player = { mana = 10000, manaMax = 10000 }, spells = { shamanisticRage = { cd = 0 } } })
    local dps = (damage.auto(S, "mh") / S.swing.mh.speed + damage.auto(S, "oh") / S.swing.oh.speed) * value.MELEE_SHARE
    assert.are.near(dps / value.drinkRate(S.player.level), value.manaPrice(S), 1e-9)
    local low = fixtures.state({ mode = "solo", player = { level = 52, mana = 1000, manaMax = 2800 } })
    assert.are.near(dps / (2934 / 30), value.manaPrice(low), 1e-9)
  end)

  -- the player's solo mana option scales the drinking price; the reserve stays as it is
  it("solo: the mana option multiplies the price (save 1.5, balanced / nil 1, spend 0.5), not in a group", function()
    assert.are.same({ balanced = 1.0, save = 1.5, spend = 0.5 }, value.MANA_POLICY)
    local S = fixtures.state({ mode = "solo", player = { mana = 5000, manaMax = 10000 } })
    local base = value.manaPrice(S)
    for name, f in pairs(value.MANA_POLICY) do
      S.manaPolicy = name
      assert.are.near(f * base, value.manaPrice(S), 1e-9, name)
    end
    S.manaPolicy = "unknown"
    assert.are.near(base, value.manaPrice(S), 1e-9)
    S.manaPolicy, S.spells = "spend", { stormstrike = { cost = 100 }, earthShock = { cost = 121 } }
    assert.are.equal(221, value.manaReserve(S))
    local G = fixtures.state({ mode = "group", player = { mana = 9000, manaMax = 10000 } })
    local g = value.manaPrice(G)
    G.manaPolicy = "save"
    assert.are.near(g, value.manaPrice(G), 1e-12)
  end)

  -- 3.3.5a water (wotlkdb.com): the best drink of the character's level
  it("drinkRate: the best water the level can drink", function()
    assert.are.near(2934 / 30, value.drinkRate(52), 1e-9) -- Morning Glory Dew (45)
    assert.are.near(2934 / 30, value.drinkRate(54), 1e-9)
    assert.are.near(4200 / 30, value.drinkRate(55), 1e-9) -- Conjured Crystal Water (55)
    assert.are.near(19200 / 30, value.drinkRate(80), 1e-9) -- Honeymint Tea (75)
    assert.are.near(151 / 18, value.drinkRate(1), 1e-9) -- Refreshing Spring Water
  end)

  -- a party drinks between pulls too, half of it while the healer drinks anyway (issue #22)
  it("group: half the solo drinking price, however full the bar is", function()
    local fine = fixtures.state({ mode = "group", player = { mana = 9000, manaMax = 10000 }, target = { ttd = 60 } })
    local oom = fixtures.state({ mode = "group", player = { mana = 1000, manaMax = 10000 }, target = { ttd = 60 } })
    local solo = fixtures.state({ mode = "solo", player = { mana = 9000, manaMax = 10000 } })
    assert.are.near(0.5 * value.manaPrice(solo), value.manaPrice(fine), 1e-9)
    assert.are.near(value.manaPrice(fine), value.manaPrice(oom), 1e-9)
  end)

  it("raid: nearly free unless the fight outlasts the mana", function()
    local fine = fixtures.state({ mode = "raid", player = { mana = 9000, manaMax = 10000 }, target = { ttd = 60 } })
    local oom = fixtures.state({ mode = "raid", player = { mana = 1000, manaMax = 10000 }, target = { ttd = 60 } })
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

describe("value.manaReserve", function()
  it("solo: one press of each known Stormstrike, Earth Shock and Lava Lash", function()
    local S = fixtures.state({ mode = "solo" })
    local sp = S.spells
    assert.are.equal(sp.stormstrike.cost + sp.earthShock.cost + sp.lavaLash.cost, value.manaReserve(S))
    S.spells.lavaLash, S.spells.stormstrike = nil, nil -- before level 40
    assert.are.equal(sp.earthShock.cost, value.manaReserve(S))
  end)

  it("group and raid keep no reserve: mana is nearly free there", function()
    assert.are.equal(0, value.manaReserve(fixtures.state({ mode = "group" })))
    assert.are.equal(0, value.manaReserve(fixtures.state({ mode = "raid" })))
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

  it("Searing Totem out of reach is worth nothing; an approaching target counts from when it is in reach", function()
    local none = base({ target = { range = "30", ttd = 60 }, enemies = { melee = 0, nearby = 1 } })
    local out = base({ target = { range = "30", ttd = 60 }, enemies = { melee = 0, nearby = 1 },
                       totems = { fire = { kind = "searing", remains = 50 } } })
    assert.are.near(value.terminal(none), value.terminal(out), 1e-6)
    local coming = base({ target = { range = "30", ttd = 60, meleeIn = 4 }, enemies = { melee = 0, nearby = 1 },
                          totems = { fire = { kind = "searing", remains = 50 } } })
    local inReach = value.TAIL - (4 - damage.SEARING_LEAD)
    assert.are.near(inReach * damage.periodic(coming, "searingTotem") * value.DISCOUNT,
      value.terminal(coming) - value.terminal(none), 1e-6)
    local near = base({ target = { range = "20", ttd = 60 }, enemies = { melee = 0, nearby = 1 },
                        totems = { fire = { kind = "searing", remains = 50 } } })
    assert.are.near(value.TAIL * damage.periodic(near, "searingTotem") * value.DISCOUNT,
      value.terminal(near) - value.terminal(none), 1e-6)
  end)

  it("Fire Elemental and wolves add their remaining damage", function()
    local none = base()
    local fe = base({ totems = { fire = { kind = "fireElemental", remains = 4 } } })
    local wolves = base({ pets = { wolves = 5 } })
    assert.are.near(4 * damage.periodic(fe, "fireElemental") * value.DISCOUNT, value.terminal(fe) - value.terminal(none), 1e-6)
    assert.are.near(5 * damage.periodic(wolves, "feralSpirit") * value.DISCOUNT, value.terminal(wolves) - value.terminal(none), 1e-6)
  end)

  it("remaining totem time counts only up to TAIL seconds: the totem can be dropped again later", function()
    local tail = base({ totems = { fire = { kind = "searing", remains = value.TAIL } } })
    local long = base({ totems = { fire = { kind = "searing", remains = 50 } } })
    assert.is_true(value.TAIL >= 10 and value.TAIL < 20)
    assert.are.near(value.terminal(tail), value.terminal(long), 1e-6)
  end)

  -- stub damage: Earth Shock 1800, Flame Shock 900 + 100 dps; the shock cooldown is 6 s
  describe("Flame Shock and the shock slot (a recast overwrites the DoT)", function()
    local function fs18() damage.dot = function(_, key) if key == "flameShock" then return 300, 6, 3 end return 0, 0, 1 end end
    -- average shock press when Flame Shock (duration d) is kept up: one Flame Shock, the rest Earth Shocks
    local function cycle(d) local n = d / 6; return (900 + 100 * d + (n - 1) * 1800) / n end

    it("the whole remaining DoT counts, not only TAIL seconds: a recast cannot add to it", function()
      fs18()
      local long = base({ target = { fs = 17, ttd = 60 } })
      local short = base({ target = { fs = 5, ttd = 60 } })
      assert.is_true(17 > value.TAIL)
      -- both far from expiry: the shock slot stays Earth Shock in both
      assert.are.near(12 * 100 * value.DISCOUNT, value.terminal(long) - value.terminal(short), 1e-6)
    end)

    it("a ready shock with the DoT gone is worth the average press of the Flame Shock cycle", function()
      fs18()
      local ready = base({ target = { fs = 0, ttd = 60 } })
      local onCd = base({ target = { fs = 0, ttd = 60 }, spells = { fireNova = { cd = 10 }, earthShock = { cd = 6 }, flameShock = { cd = 6 } } })
      -- (900 + 1800 + 2 x 1800) / 3 = 2100 > Earth Shock 1800
      assert.are.near(cycle(18) * value.DISCOUNT, value.terminal(ready) - value.terminal(onCd), 1e-6)
    end)

    it("ticks a recast would clip add nothing: refreshing now or at expiry ends in the same worth", function()
      fs18()
      local gone = base({ target = { fs = 0, ttd = 60 } })
      local ending = base({ target = { fs = 2, ttd = 60 } })
      -- 2 s left: 2100 - 200 > 1800, the slot is still the recast, which loses those 2 s again
      assert.are.near(value.terminal(gone), value.terminal(ending), 1e-6)
    end)

    it("ticks worth more than the recast's gain over Earth Shock keep the Earth Shock", function()
      fs18()
      local gone = base({ target = { fs = 0, ttd = 60 } })
      local running = base({ target = { fs = 5, ttd = 60 } })
      -- 5 s x 100 against 2100 - 1800 = 300: the slot is Earth Shock, the DoT keeps its 500
      assert.are.near((500 + 1800 - cycle(18)) * value.DISCOUNT, value.terminal(running) - value.terminal(gone), 1e-6)
    end)

    it("no Flame Shock known or no live target: the shock slot is Earth Shock", function()
      fs18()
      local noFs = base({ target = { fs = 0, ttd = 60 } })
      noFs.spells.flameShock = nil
      local onCd = base({ target = { fs = 0, ttd = 60 }, spells = { fireNova = { cd = 10 }, earthShock = { cd = 6 } } })
      onCd.spells.flameShock = nil
      assert.are.near(1800 * value.DISCOUNT, value.terminal(noFs) - value.terminal(onCd), 1e-6)
    end)
  end)

  it("support totems (the water slot stands for the set) are worth a share of auto-attack damage", function()
    local short = base({ totems = { fire = { kind = false, remains = 0 }, water = { remains = 2 } } })
    local long = base({ totems = { fire = { kind = false, remains = 0 }, water = { remains = 200 } } })
    local dps = damage.auto(long, "mh") / long.swing.mh.speed + damage.auto(long, "oh") / long.swing.oh.speed
    assert.is_true(value.SUPPORT > 0 and value.SUPPORT <= 0.1)
    assert.are.near((value.TAIL - 2) * value.SUPPORT * dps * value.DISCOUNT, value.terminal(long) - value.terminal(short), 1e-6)
  end)

  -- stub damage: Stormstrike 2000 (351 mana), Earth Shock 1800 (791), Lava Lash 1500 (176)
  describe("solo mana reserve while the target is on its way", function()
    local function at(mana, over)
      local o = { mode = "solo", player = { mana = mana }, target = { range = "20", fs = 0 } }
      for k, v in pairs(over or {}) do o[k] = v end
      return base(o)
    end

    it("mana the end state lacks costs the melee presses it cannot pay for, at full damage", function()
      local full = value.terminal(at(2000))
      assert.are.near(full, value.terminal(at(value.manaReserve(at(0)))), 1e-6)
      -- 600 buys Stormstrike + Lava Lash (527): Earth Shock is lost
      assert.are.near(full - 1800, value.terminal(at(600)), 1e-6)
      -- 400 buys Stormstrike (351) or Lava Lash, the better one: Earth Shock and Lava Lash are lost
      assert.are.near(full - 3300, value.terminal(at(400)), 1e-6)
      assert.are.near(full - 5300, value.terminal(at(100)), 1e-6)
    end)

    it("only buttons the character knows are kept for", function()
      local function known(mana)
        local S = at(mana); S.spells.stormstrike = nil -- before level 40
        return S
      end
      assert.are.equal(967, value.manaReserve(known(0)))
      -- 900 buys Earth Shock (791) or Lava Lash (176), not both: Lava Lash is lost
      assert.are.near(value.terminal(known(967)) - 1500, value.terminal(known(900)), 1e-6)
    end)

    it("not in melee, not for a dead target, not in a group", function()
      local melee = function(m) return at(m, { target = { range = "melee", fs = 0 } }) end
      assert.are.near(value.terminal(melee(2000)), value.terminal(melee(100)), 1e-6)
      local dead = function(m) return at(m, { target = { range = "20", fs = 0, dead = true } }) end
      assert.are.near(value.terminal(dead(2000)), value.terminal(dead(100)), 1e-6)
      local group = function(m) return at(m, { mode = "group" }) end
      assert.are.near(value.terminal(group(2000)), value.terminal(group(100)), 1e-6)
    end)
  end)

  -- Shamanistic Rage: 15 s of mana from melee hits (10 PPM), 1 min cooldown
  describe("Shamanistic Rage", function()
    local RATE = 20 -- mana a second from auto attacks under Rage (stub)
    before_each(function() damage.rageManaRate = function() return RATE end end)
    local function rage(cd, left, over)
      local S = base(over)
      S.mode = "solo"
      S.player.mana, S.player.manaMax = 1000, 10000
      S.spells.shamanisticRage = { id = 30823, rank = 1, cd = cd, cost = 0 }
      S.buffs.rage = left
      return S
    end
    local function worth(S, secs) return RATE * secs * value.manaPrice(S) * value.DISCOUNT end

    it("ready, it is a whole window for a later fight; on cooldown the recovered share", function()
      local S = rage(0, 0)
      assert.are.near(worth(S, value.RAGE_DURATION), value.rageValue(S, damage, true), 1e-6)
      for _, mode in ipairs({ "group", "pvp" }) do -- pvp has the group weights
        local G = rage(0, 0); G.mode = mode
        local none = rage(0, 0); none.mode = mode; none.spells.shamanisticRage = nil
        assert.are.near(value.terminal(none) + worth(G, value.RAGE_DURATION), value.terminal(G), 1e-6)
      end
      local R = rage(0, 0); R.mode = "raid"
      none = rage(0, 0); none.mode = "raid"; none.spells.shamanisticRage = nil
      assert.are.near(value.terminal(none), value.terminal(R), 1e-6) -- not in a raid
      S = rage(value.RAGE_CD / 2, 0)
      assert.are.near(worth(S, value.RAGE_DURATION / 2), value.rageValue(S, damage, true), 1e-6)
    end)

    it("a running window counts its seconds left on a live target in melee, not past its death", function()
      local S = rage(55, 10, { target = { ttd = 60 } })
      local share = value.RAGE_DURATION * (1 - 55 / value.RAGE_CD)
      assert.are.near(worth(S, share + 10), value.rageValue(S, damage, true), 1e-6)
      S = rage(55, 10, { target = { ttd = 3 } })
      assert.are.near(worth(S, share + 3), value.rageValue(S, damage, true), 1e-6)
      assert.are.near(worth(S, share), value.rageValue(S, damage, false), 1e-6) -- dead target
      S = rage(55, 10, { target = { ttd = 60 } })
      S.swing.attacking = false
      assert.are.near(worth(S, share), value.rageValue(S, damage, true), 1e-6)
    end)

    it("pressing it on a mob dying in 3 s loses more than it returns there", function()
      local ready = rage(0, 0, { target = { ttd = 3 } })
      local used = rage(value.RAGE_CD, value.RAGE_DURATION, { target = { ttd = 3 } })
      local gained = RATE * 3 * value.manaPrice(ready) -- mana returned before the mob dies
      assert.is_true(value.terminal(used) + gained < value.terminal(ready))
    end)
  end)

  -- solo, the seconds after a kill go to the next mob: a second is worth the character's dps
  it("solo: a kill inside the horizon is worth the seconds after it at the discount", function()
    local S = base({ mode = "solo", target = { hp = 0, dead = true } })
    local none = value.terminal(S)
    S.target.diedAt = S.now - 2.5
    assert.are.near(none + 2.5 * value.dpsEstimate(S) * value.DISCOUNT, value.terminal(S), 1e-6)
    S.target.diedAt = false
    assert.are.near(none, value.terminal(S), 1e-9)
    local G = base({ mode = "group", target = { hp = 0, dead = true } })
    local g0 = value.terminal(G)
    G.target.diedAt = G.now - 2.5
    assert.are.near(g0, value.terminal(G), 1e-9)
  end)

  -- against the search's "nothing pressed" kill (memo.killBase): a kill that much sooner counts
  -- only the seconds beyond FINISH_MIN; a later one, or no baseline, in full
  it("solo: a kill sooner than the one without presses counts only the seconds beyond FINISH_MIN", function()
    local S = base({ mode = "solo", target = { hp = 0, dead = true } })
    local per = value.dpsEstimate(S) * value.DISCOUNT
    S.target.diedAt = S.now - 2.5
    S.memo = { killBase = S.now - 1.0 } -- 1.5 s sooner than without presses
    assert.are.near((2.5 - value.FINISH_MIN) * per, value.killCredit(S, false), 1e-6)
    S.memo.killBase = S.now - 2.3 -- 0.2 s sooner: as if at the baseline
    assert.are.near(2.3 * per, value.killCredit(S, false), 1e-6)
    S.memo.killBase = S.now - 3.0 -- later than without presses: in full
    assert.are.near(2.5 * per, value.killCredit(S, false), 1e-6)
    S.memo = {} -- no baseline
    assert.are.near(2.5 * per, value.killCredit(S, false), 1e-6)
  end)

  -- the expected time of death (model: survival) can fall after the horizon's end with the health
  -- already gone: a press that moves it from 7.2 s to 5.8 s (horizon 6 s) saves the same seconds
  -- as one inside the horizon. At 0 for every death after S.now it saved nothing, and a mob dying
  -- just after the horizon was finished by the swings alone (recorded #55, #65).
  it("solo: a kill expected after the horizon's end counts the seconds to it below zero", function()
    local S = base({ mode = "solo", target = { hp = 0, dead = true } })
    local per = value.dpsEstimate(S) * value.DISCOUNT
    S.memo = { killBase = S.now + 1.2 }
    S.target.diedAt = S.now + 1.2 -- nothing pressed
    local idle = value.killCredit(S, false)
    assert.are.near(-1.2 * per, idle, 1e-6)
    S.target.diedAt = S.now - 0.2 -- 1.4 s sooner
    assert.are.near((1.4 - value.FINISH_MIN) * per, value.killCredit(S, false) - idle, 1e-6)
    S.target.diedAt = S.now + 0.5 -- 0.7 s sooner, still after the end
    assert.are.near((0.7 - value.FINISH_MIN) * per, value.killCredit(S, false) - idle, 1e-6)
  end)

  -- solo, Lightning Shield missing costs a GCD later: put up in a free GCD it costs nothing
  it("solo and group: a missing Lightning Shield is worth a GCD of damage at the discount, if it is wanted", function()
    for _, mode in ipairs({ "solo", "group" }) do
      local S = base({ mode = mode, spells = { fireNova = { cd = 10 }, lightningShield = { id = 49281, rank = 11, cd = 0, cost = 0 } } })
      local up = value.terminal(S)
      S.buffs.ls.charges = 0
      assert.are.near(up - (S.gcd or 1.5) * value.dpsEstimate(S) * value.DISCOUNT, value.terminal(S), 1e-6)
      S.shieldPref = "water"
      assert.are.near(up, value.terminal(S), 1e-6)
    end
    local S = base({ mode = "raid", spells = { fireNova = { cd = 10 }, lightningShield = { id = 49281, rank = 11, cd = 0, cost = 0 } } })
    local up = value.terminal(S)
    S.buffs.ls.charges = 0
    assert.are.near(up, value.terminal(S), 1e-6) -- not in a raid
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
