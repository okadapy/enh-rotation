local model = require("model")
local damage = require("damage")
local spells = require("spells")
local util = require("util")
local fixtures = require("fixtures")

local function base()
  return {
    now = 100, gcdRemains = 0, castRemains = 0, gcd = 1.5, latency = 0.15, mode = "raid",
    player = { level = 80, mana = 8000, manaMax = 10000, baseMana = 4396, hpPct = 1, ap = 4000,
               spNature = 1200, spFire = 1200, meleeCrit = 0.30, spellCrit = 0.20, meleeHit = 0.08,
               spellHit = 0.10, spellHaste = 1.0, meleeHaste = 1.0, moving = false, inCombat = true },
    weapons = { mh = { speed = 2.6, min = 600, max = 900, enchant = "wf" },
                oh = { speed = 2.6, min = 300, max = 450, enchant = "ft" } },
    talents = { maelstromWeapon = 5 },
    spells = {
      lightningBolt = { id = 49238, rank = 14, cd = 0, cost = 300, cast = 2.5 },
      chainLightning = { id = 49271, rank = 8, cd = 0, cost = 1100, cast = 2 },
      earthShock = { id = 49231, rank = 10, cd = 0, cost = 800, cast = 0 },
      flameShock = { id = 49233, rank = 9, cd = 0, cost = 700, cast = 0 },
      frostShock = { id = 49236, rank = 7, cd = 0, cost = 800, cast = 0 },
      stormstrike = { id = 17364, rank = 1, cd = 0, cost = 400, cast = 0 },
      lavaLash = { id = 60103, rank = 1, cd = 0, cost = 200, cast = 0 },
      fireNova = { id = 61657, rank = 9, cd = 0, cost = 900, cast = 0 },
      magmaTotem = { id = 58734, rank = 7, cd = 0, cost = 1000, cast = 0 },
      searingTotem = { id = 58704, rank = 10, cd = 0, cost = 300, cast = 0 },
      lightningShield = { id = 49281, rank = 11, cd = 0, cost = 0, cast = 0 },
      shamanisticRage = { id = 30823, rank = 1, cd = 0, cost = 0, cast = 0 },
    },
    buffs = { mw = { stacks = 0, remains = 0 }, ls = { charges = 3, remains = 600 },
              flurry = { charges = 0, remains = 0 }, rage = 0, lust = 0, em = 0 },
    target = { exists = true, enemy = true, level = 83, hp = 1e7, hpMax = 1e7, hpPct = 1, ttd = 300,
               range = "melee", fs = 0, ss = { charges = 0, remains = 0 } },
    totems = { fire = { remains = 0 }, water = { remains = 0 } },
    swing = { attacking = true, mh = { next = 5, speed = 2.6 }, oh = { next = 5, speed = 2.6 }, resetByInstant = {} },
    enemies = { melee = 1, nearby = 1 },
    inflight = {}, pets = { wolves = 0 },
  }
end

describe("model", function()
  describe("castTime", function()
    it("2.5 s base, -20% per Maelstrom stack, divided by haste", function()
      local S = base()
      assert.are.near(2.5, model.castTime(S, "lightningBolt"), 1e-9)
      S.buffs.mw.stacks = 3
      assert.are.near(1.0, model.castTime(S, "lightningBolt"), 1e-9)
      S.player.spellHaste = 1.25
      assert.are.near(0.8, model.castTime(S, "lightningBolt"), 1e-9)
    end)
    it("fractional stacks are floored", function()
      local S = base(); S.buffs.mw.stacks = 3.9
      assert.are.near(1.0, model.castTime(S, "lightningBolt"), 1e-9)
    end)
    it("instant at 5 stacks and for instants", function()
      local S = base(); S.buffs.mw.stacks = 5
      assert.are.equal(0, model.castTime(S, "lightningBolt"))
      assert.are.equal(0, model.castTime(S, "earthShock"))
    end)
  end)

  describe("readyIn", function()
    it("nil for unknown spells", function()
      local S = base(); S.spells.lavaLash = nil
      assert.is_nil(model.readyIn(S, "lavaLash"))
    end)
    it("waits for GCD and cooldown", function()
      local S = base(); S.gcdRemains = 0.7; S.spells.stormstrike.cd = 2
      assert.are.near(0.7, model.readyIn(S, "earthShock"), 1e-9)
      assert.are.near(2, model.readyIn(S, "stormstrike"), 1e-9)
    end)
    it("nil beyond the horizon", function()
      local S = base(); S.spells.stormstrike.cd = 7
      assert.is_nil(model.readyIn(S, "stormstrike"))
    end)
    it("nil without mana", function()
      local S = base(); S.player.mana = 100
      assert.is_nil(model.readyIn(S, "earthShock"))
    end)
    it("nil without an enemy target for targeted spells", function()
      local S = base(); S.target.exists = false
      assert.is_nil(model.readyIn(S, "earthShock"))
      S.buffs.ls.charges = 0
      assert.are.equal(0, model.readyIn(S, "lightningShield"))
    end)
    it("melee strikes need melee range, shocks 20 yd, bolts not far", function()
      local S = base(); S.target.range = "20"
      assert.is_nil(model.readyIn(S, "stormstrike"))
      assert.are.equal(0, model.readyIn(S, "earthShock"))
      S.target.range = "30"
      assert.is_nil(model.readyIn(S, "earthShock"))
      assert.are.equal(0, model.readyIn(S, "lightningBolt"))
      S.target.range = "far"
      assert.is_nil(model.readyIn(S, "lightningBolt"))
    end)
    it("Lava Lash needs an off hand", function()
      local S = base(); S.weapons.oh = nil
      assert.is_nil(model.readyIn(S, "lavaLash"))
    end)
    it("Fire Nova needs an active fire totem", function()
      local S = base()
      assert.is_nil(model.readyIn(S, "fireNova"))
      S.totems.fire = { kind = "searing", remains = 30 }
      assert.are.equal(0, model.readyIn(S, "fireNova"))
    end)
    it("does not replace Fire Elemental with Searing or Magma", function()
      local S = base(); S.totems.fire = { kind = "fireElemental", remains = 100 }
      assert.is_nil(model.readyIn(S, "magmaTotem"))
      assert.is_nil(model.readyIn(S, "searingTotem"))
    end)
    it("moving blocks hard casts but not 5-stack bolts", function()
      local S = base(); S.player.moving = true
      assert.is_nil(model.readyIn(S, "lightningBolt"))
      S.buffs.mw.stacks = 5
      assert.are.equal(0, model.readyIn(S, "lightningBolt"))
    end)
    it("Lightning Shield only when charges are missing", function()
      local S = base()
      assert.is_nil(model.readyIn(S, "lightningShield"))
      S.buffs.ls.charges = 1
      assert.are.equal(0, model.readyIn(S, "lightningShield"))
    end)
  end)

  describe("apply", function()
    it("never mutates the input state", function()
      local S = base(); S.buffs.mw.stacks = 5
      local before = model.copy(S)
      model.apply(S, "lightningBolt")
      assert.are.same(before, S)
    end)
    it("spends mana, sets cooldown and advances by GCD", function()
      local S = base()
      local S2, dmg, dt = model.apply(S, "stormstrike")
      assert.are.near(1.5, dt, 1e-9)
      assert.are.near(101.5, S2.now, 1e-9)
      assert.are.equal(7600, S2.player.mana)
      assert.are.near(8 - 1.5, S2.spells.stormstrike.cd, 1e-9)
      assert.is_true(dmg > 0)
    end)
    it("totems use a 1 s GCD", function()
      local _, _, dt = model.apply(base(), "searingTotem")
      assert.are.near(1.0, dt, 1e-9)
    end)
    it("shocks share one cooldown, Reverberation shortens it", function()
      local S = base()
      local S2 = model.apply(S, "earthShock")
      assert.are.near(6 - 1.5, S2.spells.flameShock.cd, 1e-9)
      assert.are.near(6 - 1.5, S2.spells.frostShock.cd, 1e-9)
      S.talents.reverberation = 5
      S2 = model.apply(S, "earthShock")
      assert.are.near(5 - 1.5, S2.spells.flameShock.cd, 1e-9)
    end)
    it("Improved Fire Nova shortens its cooldown", function()
      local S = base(); S.totems.fire = { kind = "searing", remains = 30 }; S.talents.improvedFireNova = 2
      local S2 = model.apply(S, "fireNova")
      assert.are.near(6 - 1.5, S2.spells.fireNova.cd, 1e-9)
    end)
    it("Lightning Bolt consumes all Maelstrom stacks", function()
      local S = base(); S.buffs.mw = { stacks = 5, remains = 20 }
      local S2 = model.apply(S, "lightningBolt")
      assert.is_true(S2.buffs.mw.stacks < 5)
      assert.is_true(S2.buffs.mw.stacks >= 0)
    end)
    it("Stormstrike puts 4 charges, nature spells consume one", function()
      local S = base()
      local S2 = model.apply(S, "stormstrike")
      assert.are.equal(4, S2.target.ss.charges)
      S2.spells.earthShock.cd = 0; S2.gcdRemains = 0
      local S3 = model.apply(S2, "earthShock")
      assert.are.equal(3, S3.target.ss.charges)
    end)
    it("Stormstrike and Lava Lash add expected Maelstrom", function()
      local S = base()
      local S2 = model.apply(S, "stormstrike")
      local expected = damage.mwPerHit(S, "mh") + damage.mwPerHit(S, "oh")
      assert.are.near(expected, S2.buffs.mw.stacks, 1e-9)
    end)
    it("Maelstrom is capped at 5", function()
      local S = base(); S.buffs.mw = { stacks = 4.9, remains = 20 }
      local S2 = model.apply(S, "stormstrike")
      assert.are.equal(5, S2.buffs.mw.stacks)
    end)
    it("Flame Shock sets the dot for ticks * period", function()
      local S2 = model.apply(base(), "flameShock")
      local _, ticks, period = damage.dot(base(), "flameShock")
      assert.are.near(ticks * period - 1.5, S2.target.fs, 1e-9)
      assert.is_nil(S2.inflight.flameShock)
    end)
    it("totems occupy the fire slot", function()
      local S2 = model.apply(base(), "magmaTotem")
      assert.are.equal("magma", S2.totems.fire.kind)
      assert.are.near(20 - 1.0, S2.totems.fire.remains, 1e-9)
    end)
    it("Lightning Shield restores charges (5 with Static Shock)", function()
      local S = base(); S.buffs.ls.charges = 0; S.talents.staticShock = 3
      local S2 = model.apply(S, "lightningShield")
      assert.are.equal(5, S2.buffs.ls.charges)
    end)
    it("Shamanistic Rage returns mana on every swing", function()
      local S = base(); S.swing.mh.next = 0.5; S.swing.oh.next = 0.6
      local S2 = model.apply(S, "shamanisticRage")
      assert.are.near(8000 + 2 * 0.15 * 4000, S2.player.mana, 1e-6)
    end)
  end)

  describe("swings during casts", function()
    it("0-stack bolt: swings during the cast are lost and timers reset at cast end", function()
      local S = base(); S.swing.mh.next = 1.0; S.swing.oh.next = 2.0
      local S2, dmg, dt = model.apply(S, "lightningBolt")
      assert.are.near(2.5, dt, 1e-9)
      assert.are.near(2.6, S2.swing.mh.next, 1e-9)
      assert.are.near(2.6, S2.swing.oh.next, 1e-9)
      assert.are.near(damage.action(S, "lightningBolt"), dmg, 1e-6)
    end)
    it("3-stack bolt: a swing due during the cast lands at cast end", function()
      local S = base(); S.buffs.mw = { stacks = 3, remains = 20 }
      S.swing.mh.next = 0.4; S.swing.oh.next = 1.2
      local S2, dmg, dt = model.apply(S, "lightningBolt")
      assert.are.near(1.5, dt, 1e-9)
      assert.are.near(1.0 + 2.6 - 1.5, S2.swing.mh.next, 1e-9)
      assert.are.near(1.2 + 2.6 - 1.5, S2.swing.oh.next, 1e-9)
      local expected = damage.action(S, "lightningBolt")
      assert.is_true(dmg > expected)
    end)
    it("instant spell does not touch swings by default", function()
      local S = base(); S.swing.mh.next = 0.4
      local S2 = model.apply(S, "earthShock")
      assert.are.near(0.4 + 2.6 - 1.5, S2.swing.mh.next, 1e-9)
    end)
    it("instant spell resets swings when calibration says so", function()
      local S = base(); S.swing.mh.next = 0.4; S.swing.resetByInstant = { earthShock = true }
      local S2 = model.apply(S, "earthShock")
      assert.are.near(2.6 - 1.5, S2.swing.mh.next, 1e-9)
    end)
  end)

  describe("wait", function()
    it("autos land on schedule and add Maelstrom", function()
      local S = base(); S.swing.mh.next = 0.5; S.swing.oh.next = 1.0
      local S2, dmg = model.wait(S, 2)
      assert.are.near(damage.auto(S, "mh") + damage.auto(S, "oh"), dmg, 1e-6)
      assert.are.near(0.5 + 2.6 - 2, S2.swing.mh.next, 1e-9)
      assert.are.near(damage.mwPerSwing(S, "mh") + damage.mwPerSwing(S, "oh"), S2.buffs.mw.stacks, 1e-9)
    end)
    it("no swings when not attacking or not in melee range", function()
      local S = base(); S.swing.mh.next = 0.5; S.swing.attacking = false
      local _, dmg = model.wait(S, 2)
      assert.are.equal(0, dmg)
      S.swing.attacking = true; S.target.range = "30"
      _, dmg = model.wait(S, 2)
      assert.are.equal(0, dmg)
    end)
    it("Flame Shock ticks continuously, limited by its remaining time", function()
      local S = base(); S.target.fs = 2
      local _, dmg = model.wait(S, 3)
      assert.are.near(damage.periodic(S, "flameShock") * 2, dmg, 1e-6)
    end)
    it("damage is limited by time to die", function()
      local S = base(); S.target.fs = 10; S.target.ttd = 1
      local S2, dmg = model.wait(S, 3)
      assert.are.near(damage.periodic(S, "flameShock") * 1, dmg, 1e-6)
      assert.is_true(S2.target.dead)
    end)
    it("dead target takes no damage", function()
      local S = base(); S.target.dead = true; S.target.fs = 10; S.swing.mh.next = 0.1
      local _, dmg = model.wait(S, 3)
      assert.are.equal(0, dmg)
    end)
    it("fire totem and wolves deal damage while active", function()
      local S = base(); S.totems.fire = { kind = "magma", remains = 1 }; S.pets.wolves = 2
      local _, dmg = model.wait(S, 3)
      local expected = damage.periodic(S, "magmaTotem") * 1 + damage.periodic(S, "feralSpirit") * 2
      assert.are.near(expected, dmg, 1e-6)
    end)
    it("timers count down and expire", function()
      local S = base()
      S.spells.stormstrike.cd = 2; S.gcdRemains = 1; S.target.fs = 1
      S.target.ss = { charges = 2, remains = 1 }; S.buffs.mw = { stacks = 2, remains = 1 }
      S.totems.fire = { kind = "searing", remains = 1 }; S.inflight = { flameShock = 1 }
      local S2 = model.wait(S, 1.5)
      assert.are.near(0.5, S2.spells.stormstrike.cd, 1e-9)
      assert.are.equal(0, S2.gcdRemains)
      assert.are.equal(0, S2.target.fs)
      assert.are.equal(0, S2.target.ss.charges)
      assert.are.equal(0, S2.buffs.mw.stacks)
      assert.is_nil(S2.totems.fire.kind)
      assert.is_nil(S2.inflight.flameShock)
    end)
  end)

  describe("actions", function()
    it("lists ready spells and waitSwing", function()
      local S = base(); S.swing.mh.next = 0.8; S.swing.oh.next = 1.3
      local keys = {}
      for _, a in ipairs(model.actions(S)) do keys[a.key] = a.readyIn end
      assert.are.equal(0, keys.stormstrike)
      assert.is_nil(keys.fireNova)
      assert.is_nil(keys.lightningShield)
      assert.are.near(0.81, keys.waitSwing, 1e-9)
    end)
  end)
  describe("contract v2", function()
    it("model.copy is util.copy", function()
      assert.are.equal(util.copy, model.copy)
    end)

    it("readyIn is never earlier than GCD or the current cast", function()
      local S = base(); S.castRemains = 1.2; S.gcdRemains = 0.4
      assert.are.near(1.2, model.readyIn(S, "earthShock"), 1e-9)
      assert.are.near(1.2, model.readyIn(S, "searingTotem"), 1e-9)
    end)

    it("readyIn equal to the horizon is filtered out", function()
      local S = base(); S.spells.stormstrike.cd = model.HORIZON
      assert.is_nil(model.readyIn(S, "stormstrike"))
      S.spells.stormstrike.cd = model.HORIZON - 0.01
      assert.are.near(model.HORIZON - 0.01, model.readyIn(S, "stormstrike"), 1e-9)
    end)

    it("Fire Nova: kind false means no totem, 'other' is a foreign totem and allows it", function()
      local S = base(); S.totems.fire = { kind = false, remains = 30 }
      assert.is_nil(model.readyIn(S, "fireNova"))
      S.totems.fire = { kind = "other", remains = 30 }
      assert.are.equal(0, model.readyIn(S, "fireNova"))
      local _, dmg = model.wait(S, 2)
      assert.are.equal(0, dmg)
    end)

    it("apply advances now by dt and lowers target hp by the damage", function()
      local S = base(); S.swing.mh.next = 0.5
      local S2, dmg, dt = model.apply(S, "stormstrike")
      assert.are.near(S.now + dt, S2.now, 1e-9)
      assert.are.near(S.target.hp - dmg, S2.target.hp, 1e-6)
    end)

    it("hp never goes below 0 and the target dies", function()
      local S = base(); S.target.hp = 10
      local S2 = model.apply(S, "stormstrike")
      assert.are.equal(0, S2.target.hp)
      assert.is_true(S2.target.dead)
      local S3, dmg = model.wait(S2, 3)
      assert.are.equal(0, dmg)
      assert.are.equal(0, S3.target.hp)
    end)

    it("no swing damage after time to die", function()
      local S = base(); S.target.ttd = 0.3; S.swing.mh.next = 0.5; S.swing.oh.next = 0.6
      local S2, dmg = model.wait(S, 2)
      assert.are.equal(0, dmg)
      assert.is_true(S2.target.dead)
    end)

    it("actions follow spells.CATALOG order, waitSwing last at next swing + 0.01", function()
      local S = fixtures.state()
      S.swing.mh.next, S.swing.oh.next = 1.2, 0.4
      local list = model.actions(S)
      local pos = {}
      for i, m in ipairs(spells.CATALOG) do pos[m.key] = i end
      for i = 2, #list - 1 do
        assert.is_true(pos[list[i - 1].key] < pos[list[i].key])
      end
      assert.are.equal("waitSwing", list[#list].key)
      assert.are.near(0.41, list[#list].readyIn, 1e-9)
      for _, a in ipairs(list) do assert.is_true(a.readyIn < model.HORIZON) end
    end)

    it("no waitSwing when auto attack is off or the swing is beyond the horizon", function()
      local S = base(); S.swing.attacking = false
      for _, a in ipairs(model.actions(S)) do assert.are_not.equal("waitSwing", a.key) end
      S = base(); S.swing.mh.next = 6.5; S.swing.oh.next = 7
      for _, a in ipairs(model.actions(S)) do assert.are_not.equal("waitSwing", a.key) end
    end)

    it("works without an off hand", function()
      local S = base(); S.weapons.oh = nil; S.swing.oh = nil; S.swing.mh.next = 0.2
      local S2, dmg = model.apply(S, "stormstrike")
      assert.is_true(dmg > 0)
      assert.is_nil(S2.swing.oh)
      local _, d2 = model.wait(S2, 3)
      assert.is_true(d2 > 0)
      for _, a in ipairs(model.actions(S)) do assert.are_not.equal("lavaLash", a.key) end
    end)

    it("every ready action of the fixture applies without errors and without mutating S", function()
      local S = fixtures.state({ buffs = { ls = { charges = 0 } } })
      local before = util.copy(S)
      for _, a in ipairs(model.actions(S)) do
        if a.key ~= "waitSwing" then
          local S1 = a.readyIn > 0 and model.wait(S, a.readyIn) or S
          local S2, dmg, dt = model.apply(S1, a.key)
          assert.is_true(dmg >= 0, a.key)
          assert.is_true(dt > 0, a.key)
        end
      end
      assert.are.same(before, S)
    end)
  end)
end)
