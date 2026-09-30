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
    it("Fire Nova and Magma Totem only with an enemy in reach of the totem at the shaman's feet", function()
      local S = base(); S.totems.fire = { kind = "searing", remains = 30 }
      S.target.range = "30"; S.enemies = { melee = 0, nearby = 1 }
      assert.is_nil(model.readyIn(S, "fireNova"))
      assert.is_nil(model.readyIn(S, "magmaTotem"))
      S.target.range = "20"
      assert.is_nil(model.readyIn(S, "fireNova"))
      -- another mob hits the shaman in melee: it stands in the nova and the magma pulses
      S.enemies = { melee = 1, nearby = 2 }
      assert.are.equal(0, model.readyIn(S, "fireNova"))
      assert.are.equal(0, model.readyIn(S, "magmaTotem"))
      S.target.range = "melee"; S.enemies = { melee = 0, nearby = 1 }
      assert.are.equal(0, model.readyIn(S, "fireNova"))
      assert.are.equal(0, model.readyIn(S, "magmaTotem"))
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
    it("Frost Shock only when Earth Shock is not known (same cooldown, no Stormstrike bonus)", function()
      local S = base()
      assert.is_nil(model.readyIn(S, "frostShock"))
      S.spells.earthShock = nil
      assert.are.equal(0, model.readyIn(S, "frostShock"))
    end)
    it("Call of the Elements only when it changes something: no fire totem or water expiring", function()
      local S = base()
      S.spells.callOfElements = { id = 66842, rank = 1, cd = 0, cost = 0, cast = 0 }
      S.totems = { fire = { kind = "magma", remains = 15 }, water = { remains = 200 } }
      assert.is_nil(model.readyIn(S, "callOfElements"))
      S.totems.water.remains = model.COE_WATER - 1
      assert.are.equal(0, model.readyIn(S, "callOfElements"))
      S.totems = { fire = { kind = false, remains = 0 }, water = { remains = 200 } }
      assert.are.equal(0, model.readyIn(S, "callOfElements"))
    end)
    it("Call of the Elements is not offered over an active Fire Elemental (it would replace it)", function()
      local S = base()
      S.spells.callOfElements = { id = 66842, rank = 1, cd = 0, cost = 0, cast = 0 }
      S.totems = { fire = { kind = "fireElemental", remains = 60 }, water = { remains = 5 } }
      assert.is_nil(model.readyIn(S, "callOfElements"))
    end)
    -- the model spends no charges (only "any charge left" matters for Static Shock), so a refresh
    -- with charges left changes nothing unless the shield runs out inside the horizon
    it("Lightning Shield only when it is gone or runs out soon", function()
      local S = base()
      assert.is_nil(model.readyIn(S, "lightningShield"))
      S.buffs.ls.charges = 1
      assert.is_nil(model.readyIn(S, "lightningShield"))
      S.buffs.ls.remains = 4
      assert.are.equal(0, model.readyIn(S, "lightningShield"))
      S.buffs.ls = { charges = 0, remains = 0 }
      assert.are.equal(0, model.readyIn(S, "lightningShield"))
    end)
    -- only one shield can be up: Lightning Shield over Water Shield would remove it
    it("no Lightning Shield over Water Shield unless asked for", function()
      local S = base()
      S.buffs.ls = { charges = 0, remains = 0 }
      S.buffs.ws = { charges = 3, remains = 500 }
      S.player.shield = "water"
      assert.is_nil(model.readyIn(S, "lightningShield")) -- nil pref = auto
      S.shieldPref = "auto"
      assert.is_nil(model.readyIn(S, "lightningShield"))
      S.shieldPref = "water"
      assert.is_nil(model.readyIn(S, "lightningShield"))
      S.shieldPref = "lightning"
      assert.are.equal(0, model.readyIn(S, "lightningShield"))
      S.player.shield, S.buffs.ws, S.shieldPref = nil, nil, "water"
      assert.is_nil(model.readyIn(S, "lightningShield")) -- wants Water Shield: never Lightning
      S.shieldPref = "auto"
      assert.are.equal(0, model.readyIn(S, "lightningShield")) -- nothing up: as before
    end)
    it("the rule survives clones and scratch states", function()
      local S = base()
      S.buffs.ls = { charges = 0, remains = 0 }
      S.player.shield, S.shieldPref, S.memo = "water", "auto", {}
      for _, a in ipairs(model.actions(model.wait(S, 0.5))) do assert.are_not.equal("lightningShield", a.key) end
      local P = model.peekApply(model.peekWait(S, 0.5), "stormstrike")
      assert.is_nil(model.readyIn(P, "lightningShield"))
      S.player.mana = 5000
      P = model.peekApply(S, "lavaLash") -- spends mana: own player table in the scratch state
      assert.are.equal("water", P.player.shield)
      assert.is_nil(model.readyIn(P, "lightningShield"))
    end)
    it("the same fire totem is not dropped again while it outlasts what the value counts", function()
      local S = base()
      S.totems.fire = { kind = "magma", remains = 15 }
      assert.is_nil(model.readyIn(S, "magmaTotem"))
      assert.are.equal(0, model.readyIn(S, "searingTotem"))
      S.totems.fire.remains = 5
      assert.are.equal(0, model.readyIn(S, "magmaTotem"))
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
    it("a cast the target does not live to see (castTime + latency) deals no damage, but costs mana", function()
      local S = base(); S.target.ttd = 1.2
      local S2, dmg = model.apply(S, "lightningBolt")
      assert.are.equal(0, dmg)
      assert.are.equal(1e7, S2.target.hp)
      assert.are.equal(8000 - 300, S2.player.mana)
      -- lands after the cast time but before the server ends the cast: still a corpse
      S.target.ttd = 2.5 + 0.1
      assert.are.equal(0, select(2, model.apply(S, "lightningBolt")))
      S.target.ttd = 2.5 + 0.15 + 0.01
      local _, d = model.apply(S, "lightningBolt")
      assert.are.near(damage.action(S, "lightningBolt"), d, 1e-6)
    end)
    it("no kill by a cast that lands after the target died", function()
      local S = base(); S.target.hp = 100; S.target.ttd = 1.2
      local S2 = model.apply(S, "chainLightning")
      assert.are.equal(100, S2.target.hp)
    end)
    it("instants still hit a target about to die", function()
      local S = base(); S.target.ttd = 0.5
      local _, d = model.apply(S, "earthShock")
      assert.are.near(damage.action(S, "earthShock"), d, 1e-6)
      S.buffs.mw = { stacks = 5, remains = 20 }
      _, d = model.apply(S, "lightningBolt")
      assert.is_true(d > 0)
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
    it("Shamanistic Rage returns mana on every landed swing and Windfury extra attack", function()
      local S = base(); S.swing.mh.next = 0.5; S.swing.oh.next = 0.6
      local S2 = model.apply(S, "shamanisticRage")
      local white, yellow = damage.meleeTable(S, true).landed, damage.meleeTable(S, false).landed
      local _, wfProcs = damage.wf(S)
      local hits = 2 * white + wfProcs * 2 * yellow
      assert.is_true(white < 1 and wfProcs > 0)
      assert.are.near(8000 + hits * 0.15 * 4000, S2.player.mana, 1e-6)
    end)
    describe("Shamanistic Rage on special attacks", function()
      local function rageState(mana)
        local S = base(); S.buffs.rage = 10; S.player.mana = mana
        S.swing.mh.next, S.swing.oh.next = 5, 5 -- no auto attack inside the GCD
        return S
      end
      local per = 0.15 * 4000
      it("both Stormstrike hits return mana while Rage is up", function()
        local S = rageState(2000)
        local S2 = model.apply(S, "stormstrike")
        local landed = damage.meleeTable(S, false).landed
        assert.are.near(2000 - 400 + 2 * per * landed, S2.player.mana, 1e-6)
      end)
      it("one hit without an off-hand weapon", function()
        local S = rageState(2000); S.weapons.oh = nil; S.swing.oh = nil
        local S2 = model.apply(S, "stormstrike")
        assert.are.near(2000 - 400 + per * damage.meleeTable(S, false).landed, S2.player.mana, 1e-6)
      end)
      it("the Lava Lash hit returns mana while Rage is up", function()
        local S = rageState(2000)
        local S2 = model.apply(S, "lavaLash")
        assert.are.near(2000 - 200 + per * damage.meleeTable(S, false).landed, S2.player.mana, 1e-6)
      end)
      it("nothing without Rage", function()
        local S = rageState(2000); S.buffs.rage = 0
        assert.are.near(2000 - 400, model.apply(S, "stormstrike").player.mana, 1e-9)
        assert.are.near(2000 - 200, model.apply(S, "lavaLash").player.mana, 1e-9)
      end)
      it("nothing on a dead target", function()
        local S = rageState(2000); S.target.dead = true
        assert.are.near(2000 - 400, model.apply(S, "stormstrike").player.mana, 1e-9)
      end)
      it("capped at maximum mana", function()
        local S = rageState(9800)
        assert.are.equal(10000, model.apply(S, "stormstrike").player.mana)
      end)
      it("peekApply gives the same mana", function()
        for _, key in ipairs({ "stormstrike", "lavaLash" }) do
          local S = rageState(2000); S.memo = {}
          local a = model.apply(S, key).player.mana
          assert.are.equal(a, model.peekApply(S, key).player.mana, key)
        end
      end)
    end)
  end)

  describe("Call of the Elements", function()
    local function coe(fire, water)
      local S = base()
      S.spells.callOfElements = { id = 66842, rank = 1, cd = 0, cost = 0, cast = 0 }
      S.totems = { fire = fire, water = { remains = water } }
      return S
    end
    it("drops the whole set: water refreshed, fire slot gets Magma Totem even over an old one", function()
      local S2, _, dt = model.apply(coe({ kind = "magma", remains = 3 }, 5), "callOfElements")
      assert.are.equal("magma", S2.totems.fire.kind)
      assert.are.near(model.TOTEM_DURATION.magmaTotem - dt, S2.totems.fire.remains, 1e-9)
      assert.are.near(model.WATER_DURATION - dt, S2.totems.water.remains, 1e-9)
    end)
    it("uses Searing Totem when Magma Totem is not learned", function()
      local S = coe({ kind = false, remains = 0 }, 200)
      S.spells.magmaTotem = nil
      assert.are.equal("searing", model.apply(S, "callOfElements").totems.fire.kind)
    end)
  end)

  describe("swings during casts", function()
    -- base() has latency 0.15: the swing clock restarts when the server ends the cast
    it("0-stack bolt: swings during the cast are lost and timers reset at cast end + latency", function()
      local S = base(); S.swing.mh.next = 1.0; S.swing.oh.next = 2.0
      local S2, dmg, dt = model.apply(S, "lightningBolt")
      assert.are.near(2.5, dt, 1e-9)
      assert.are.near(2.6 + 0.15, S2.swing.mh.next, 1e-9)
      assert.are.near(2.6 + 0.15, S2.swing.oh.next, 1e-9)
      assert.are.near(damage.action(S, "lightningBolt"), dmg, 1e-6)
    end)
    it("3-stack bolt: a swing due during the cast lands at cast end + latency", function()
      local S = base(); S.buffs.mw = { stacks = 3, remains = 20 }
      S.swing.mh.next = 0.4; S.swing.oh.next = 1.2
      local S2, dmg, dt = model.apply(S, "lightningBolt")
      assert.are.near(1.5, dt, 1e-9)
      assert.are.near(1.0 + 0.15 + 2.6 - 1.5, S2.swing.mh.next, 1e-9)
      assert.are.near(1.2 + 2.6 - 1.5, S2.swing.oh.next, 1e-9)
      local expected = damage.action(S, "lightningBolt")
      assert.is_true(dmg > expected)
    end)
    it("a swing due just after the cast ends is held back by the latency", function()
      local S = base(); S.buffs.mw = { stacks = 3, remains = 20 }
      S.swing.mh.next = 1.05; S.swing.oh.next = 2.0
      local S2 = model.apply(S, "lightningBolt")
      assert.are.near(1.0 + 0.15 + 2.6 - 1.5, S2.swing.mh.next, 1e-9)
      S.latency = 0
      assert.are.near(1.05 + 2.6 - 1.5, model.apply(S, "lightningBolt").swing.mh.next, 1e-9)
      S.latency = 0.15
      assert.are.near(1.0 + 0.15 + 2.6 - 1.5, (model.peekApply(S, "lightningBolt")).swing.mh.next, 1e-9)
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
    it("Searing Totem deals damage only with the target within its 20 yards", function()
      local S = base(); S.totems.fire = { kind = "searing", remains = 30 }
      S.swing.attacking = false; S.enemies = { melee = 0, nearby = 1 }
      local rate = damage.periodic(S, "searingTotem")
      assert.is_true(rate > 0)
      for _, r in ipairs({ "melee", "20" }) do
        S.target.range = r
        local _, dmg = model.wait(S, 3)
        assert.are.near(rate * 3, dmg, 1e-6, r)
      end
      for _, r in ipairs({ "30", "far" }) do
        S.target.range = r
        local _, dmg = model.wait(S, 3)
        assert.are.equal(0, dmg, r)
        local _, pdmg = model.peekWait(S, 3)
        assert.are.equal(0, pdmg, r)
      end
      -- an enemy hitting the shaman in melee is shot instead
      S.enemies.melee = 1
      local _, dmg = model.wait(S, 3)
      assert.are.near(rate * 3, dmg, 1e-6)
    end)
    it("Searing Totem starts shooting an approaching target once it is within 20 yards", function()
      local S = base(); S.totems.fire = { kind = "searing", remains = 30 }
      S.swing.attacking = false; S.enemies = { melee = 0, nearby = 1 }
      S.target.range = "far"; S.target.meleeIn = damage.SEARING_LEAD + 1
      S.memo = {}
      local n = util.copy(S)
      n.memo = S.memo
      local dmg = model.advance(n, 3, nil, true)
      assert.are.near(damage.periodic(S, "searingTotem") * 2, dmg, 1e-6)
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

    it("apply with a time limit stops there: the rest of the GCD stays, later swings are not counted", function()
      local S = fixtures.state({ swing = { mh = { next = 1.0 }, oh = { next = 1.2 } } })
      local full, dFull, dt = model.apply(S, "earthShock")
      local cut, dCut, dtCut = model.apply(S, "earthShock", 0.5)
      assert.are.near(1.5, dt, 1e-9)
      assert.are.near(0.5, dtCut, 1e-9)
      assert.are.near(S.now + 0.5, cut.now, 1e-9)
      assert.are.near(1.0, cut.gcdRemains, 1e-9)
      assert.is_true(dCut < dFull) -- the swings at 1.0 and 1.2 fall after the limit
      assert.are.equal(0, full.gcdRemains)
      local P, dP, dtP = model.peekApply(S, "earthShock", 0.5)
      assert.are.equal(dCut, dP)
      assert.are.equal(dtCut, dtP)
      assert.are.near(1.0, P.gcdRemains, 1e-9)
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

describe("model: a mob running in (target.meleeIn)", function()
  local ETA20, ETA30 = 20 / 7, 30 / 7

  local function coming(range, meleeIn)
    local S = base()
    S.mode = "solo"
    S.target.range, S.target.inCombat, S.target.meleeIn = range, true, meleeIn
    S.enemies = { melee = 0, nearby = 1 }
    return S
  end

  it("counts meleeIn down: 30 yards -> 20 yards -> melee", function()
    local S = coming("30", ETA30)
    local S1 = model.wait(S, 1)
    assert.are.near(ETA30 - 1, S1.target.meleeIn, 1e-9)
    assert.are.equal("30", S1.target.range)
    local S2 = model.wait(S1, 1)
    assert.are.near(ETA30 - 2, S2.target.meleeIn, 1e-9)
    assert.are.equal("20", S2.target.range) -- 10 yards run, within 20 now
    local S3 = model.wait(S2, 3)
    assert.is_nil(S3.target.meleeIn)
    assert.are.equal("melee", S3.target.range)
    -- the input states are untouched
    assert.are.equal("30", S.target.range)
    assert.are.near(ETA30, S.target.meleeIn, 1e-9)
  end)

  it("swings start when the mob arrives, not before (a ready swing timer fires at once)", function()
    local S = coming("20", 1.0)
    S.swing.mh.next, S.swing.oh.next = 0, 0.5
    local S2, dmg = model.wait(S, 2)
    -- both hands ready at the arrival (1.0 s), next ones 2.6 s later
    assert.are.near(damage.auto(S2, "mh") + damage.auto(S2, "oh"), dmg, 1e-6)
    assert.are.near(2.6 - 1.0, S2.swing.mh.next, 1e-9)
    -- one step or two around the arrival: the same numbers
    local A, d1 = model.wait(S, 1.0)
    local B, d2 = model.wait(A, 1.0)
    assert.are.near(dmg, d1 + d2, 1e-6)
    assert.are.near(S2.swing.mh.next, B.swing.mh.next, 1e-9)
    assert.are.near(S2.swing.oh.next, B.swing.oh.next, 1e-9)
    -- a static target at 20 yards gets no swings at all
    S.target.meleeIn = nil
    local _, none = model.wait(S, 2)
    assert.are.equal(0, none)
  end)

  it("a cast still running when the mob arrives holds its swings until the cast ends", function()
    local S = coming("20", 1.0)
    S.swing.mh.next, S.swing.oh.next = 0, 0
    local S2, dmg = model.apply(S, "lightningBolt") -- 0 stacks: 2.5 s, swings reset at 2.5 + latency
    assert.are.near(damage.action(S, "lightningBolt"), dmg, 1e-6)
    assert.are.equal("melee", S2.target.range)
    assert.are.near(2.6 - (2.5 - 2.5 - 0.15), S2.swing.mh.next, 1e-9)
  end)

  it("melee buttons are ready when it arrives, shocks when it is within 20 yards", function()
    local S = coming("30", ETA30)
    assert.are.near(ETA30, model.readyIn(S, "stormstrike"), 1e-9)
    assert.are.near(ETA30, model.readyIn(S, "lavaLash"), 1e-9)
    assert.are.near(ETA30 - ETA20, model.readyIn(S, "earthShock"), 1e-9)
    assert.are.equal(0, model.readyIn(S, "lightningBolt"))
    S.gcdRemains = 2.0 -- the later of the two
    assert.are.near(2.0, model.readyIn(S, "earthShock"), 1e-9)
    assert.are.near(ETA30, model.readyIn(S, "stormstrike"), 1e-9)
    S.target.meleeIn = 6.5 -- past the horizon
    assert.is_nil(model.readyIn(S, "stormstrike"))
  end)

  it("the pull: a spell on a solo mob at range brings it in from the moment it lands", function()
    local S = coming("20", nil)
    S.target.inCombat = false
    local F = model.apply(S, "flameShock")
    assert.are.near(ETA20 - 1.5, F.target.meleeIn, 1e-9)
    S.target.range = "30"
    local L = model.apply(S, "lightningBolt")
    assert.are.near(2.5 + 0.15 + ETA30 - 2.5, L.target.meleeIn, 1e-9)
    assert.are.equal("30", L.target.range)
    -- nothing on the target: nothing comes
    assert.is_nil(model.apply(S, "lightningShield").target.meleeIn)
    -- an approach already on its way is not restarted
    S.target.meleeIn = 1.0
    assert.are.equal("melee", model.apply(S, "lightningBolt").target.range)
  end)

  it("no approach for players, in a group or from far away", function()
    local S = coming("20", nil)
    S.target.isPlayer = true
    assert.is_nil(model.apply(S, "flameShock").target.meleeIn)
    S.target.isPlayer, S.mode = false, "group"
    assert.is_nil(model.apply(S, "flameShock").target.meleeIn)
    S.mode, S.target.range = "solo", "far"
    assert.is_nil(model.apply(S, "lightningShield").target.meleeIn)
  end)

  it("the damage memo follows the range: Fire Nova hits the arrived mob", function()
    local S = coming("20", 1.0)
    S.memo = {}
    S.totems.fire = { kind = "searing", remains = 30 }
    -- at range nothing stands by the totem: 0 goes into the memo of this search
    assert.are.equal(0, damage.targets(S, "fireNova"))
    assert.are.equal(0, damage.action(S, "fireNova"))
    assert.are.equal(0, damage.rates(S).magmaTotem)
    local W = model.wait(S, 1.5)
    assert.are.equal("melee", W.target.range)
    assert.are.equal(1, damage.targets(W, "fireNova"))
    local fresh = util.copy(W); fresh.memo = nil
    assert.is_true(damage.action(fresh, "fireNova") > 0)
    assert.are.near(damage.action(fresh, "fireNova"), damage.action(W, "fireNova"), 1e-9)
    assert.is_true(damage.rates(fresh).magmaTotem > 0)
    assert.are.near(damage.rates(fresh).magmaTotem, damage.rates(W).magmaTotem, 1e-9)
    assert.is_true(model.readyIn(W, "fireNova") ~= nil)
  end)
end)

describe("model working copies (search speed)", function()
  -- contract part of a state, without the scratch bookkeeping
  local function view(S)
    local out = {}
    for _, k in ipairs({ "now", "gcdRemains", "castRemains", "gcd", "mode" }) do out[k] = S[k] end
    out.mana = S.player.mana
    out.spells = {}
    for k, sp in pairs(S.spells) do out.spells[k] = { sp.id, sp.rank, sp.cd, sp.cost, sp.cast } end
    out.buffs = util.copy(S.buffs)
    out.target = util.copy(S.target)
    out.totems = util.copy(S.totems)
    out.swing = { S.swing.attacking, util.copy(S.swing.mh), util.copy(S.swing.oh) }
    out.wolves = S.pets and S.pets.wolves or 0
    return out
  end

  local function states()
    local list = {}
    for _, over in ipairs({ {}, { buffs = { mw = { stacks = 3, remains = 20 } } }, { buffs = { rage = 10, ls = { charges = 0 } } },
                           { buffs = { rage = 10 }, player = { mana = 1500 } },
                           { spells = { stormstrike = { cd = 3 }, earthShock = { cd = 2 } }, totems = { fire = { kind = false } } },
                           { target = { ttd = 1.5, hp = 500 }, buffs = { mw = { stacks = 2, remains = 20 } } },
                           { target = { range = "30" }, enemies = { melee = 1, nearby = 3 } },
                           { target = { range = "far" }, enemies = { melee = 0, nearby = 1 },
                             totems = { fire = { kind = "searing", remains = 30 } } },
                           -- a mob running in: arriving inside a GCD, inside a cast, after it; a pull
                           { mode = "solo", target = { range = "20", meleeIn = 0.9, inCombat = true }, enemies = { melee = 0 } },
                           { mode = "solo", target = { range = "30", meleeIn = 3.1, inCombat = true }, enemies = { melee = 0 },
                             swing = { mh = { next = 0.2 } } },
                           { mode = "solo", target = { range = "20" }, enemies = { melee = 0 }, buffs = { mw = { stacks = 2, remains = 20 } } },
                           { mode = "solo", target = { range = "30" }, enemies = { melee = 0 } } }) do
      local S = fixtures.state(over)
      S.memo = {}
      list[#list + 1] = S
    end
    return list
  end

  it("peekApply and peekWait give exactly what apply and wait give", function()
    for _, S in ipairs(states()) do
      for _, a in ipairs(model.actions(S)) do
        if a.key ~= "waitSwing" then
          local S2, d2, t2 = model.apply(S, a.key)
          local P, dp, tp = model.peekApply(S, a.key)
          assert.are.equal(d2, dp, a.key)
          assert.are.equal(t2, tp, a.key)
          assert.are.same(view(S2), view(P), a.key)
          local W, dw = model.wait(S2, 2.3)
          local Q, dq = model.peekWait(S2, 2.3)
          assert.are.equal(dw, dq, a.key)
          assert.are.same(view(W), view(Q), a.key)
        end
      end
    end
  end)

  -- fillScratch refills a buffer from the same source faster (only cooldowns and entries setCd
  -- switched); apply never touches the scratch buffers, so these peeks come one after another
  it("peeks of the same state one after another give exactly what apply and wait give", function()
    for _, S in ipairs(states()) do
      local acts = model.actions(S)
      for round = 1, 2 do
        local limit = round == 2 and 0.7 or nil
        for _, a in ipairs(acts) do
          if a.key ~= "waitSwing" then
            local S2, d2 = model.apply(S, a.key, limit)
            local P, dp = model.peekApply(S, a.key, limit)
            assert.are.equal(d2, dp, a.key)
            assert.are.same(view(S2), view(P), a.key)
          end
        end
        local W, dw = model.wait(S, 1.7 * round)
        local Q, dq = model.peekWait(S, 1.7 * round)
        assert.are.equal(dw, dq)
        assert.are.same(view(W), view(Q))
      end
    end
  end)

  it("a scratch state can be the input of the next peek", function()
    local S = states()[1]
    local W1, d1 = model.wait(S, 1.2)
    local S2, d2 = model.apply(W1, "stormstrike")
    local P1, e1 = model.peekWait(S, 1.2)
    local P2, e2 = model.peekApply(P1, "stormstrike")
    assert.are.equal(d1, e1)
    assert.are.equal(d2, e2)
    assert.are.same(view(S2), view(P2))
  end)

  -- the search presses after a wait in the wait's own buffer (no second fill)
  it("peekApplyOver on a peekWait state gives exactly what wait, then apply give", function()
    for _, S in ipairs(states()) do
      for _, dt in ipairs({ 0.4, 1.2, 2.9 }) do
        local W = model.wait(S, dt)
        for _, a in ipairs(model.actions(W)) do
          if a.key ~= "waitSwing" and a.readyIn <= 0 then
            for _, limit in ipairs({ false, 0.7 }) do
              local S2, d2, t2 = model.apply(W, a.key, limit or nil)
              local P, dp, tp = model.peekApplyOver(model.peekWait(S, dt), a.key, limit or nil)
              assert.are.equal(d2, dp, a.key)
              assert.are.equal(t2, tp, a.key)
              assert.are.same(view(S2), view(P), a.key)
              -- and the buffer is filled right again from the same source afterwards
              local Q, dq = model.peekApply(S, a.key)
              local R, dr = model.apply(S, a.key)
              assert.are.equal(dr, dq, a.key)
              assert.are.same(view(R), view(Q), a.key)
            end
          end
        end
      end
    end
  end)

  it("a peek does not leave the mob's arrival in the scratch buffer for the next peek of the same state", function()
    local S = fixtures.state({ mode = "solo", target = { range = "20", meleeIn = 0.5, inCombat = true }, enemies = { melee = 0 } })
    S.memo = {}
    local P = model.peekWait(S, 1)
    assert.are.equal("melee", P.target.range)
    P = model.peekWait(S, 0.2)
    assert.are.equal("20", P.target.range)
    assert.are.near(0.3, P.target.meleeIn, 1e-9)
    assert.are.same(view(model.wait(S, 0.2)), view(P))
  end)

  it("advancing a scratch state in place equals wait", function()
    local S = states()[2]
    local W, dw = model.wait(model.apply(S, "lavaLash"), 3.1)
    local P = model.peekApply(S, "lavaLash")
    local dp = model.advance(P, 3.1)
    assert.are.equal(dw, dp)
    assert.are.same(view(W), view(P))
  end)

  -- advance lowers a scratch state's cooldowns only in its own entries (on cooldown at the fill,
  -- or switched by setCd: a shock sets the shared cooldown of the others)
  it("advancing any pressed scratch state in place equals advancing the applied state", function()
    for _, S in ipairs(states()) do
      for _, a in ipairs(model.actions(S)) do
        if a.key ~= "waitSwing" then
          local W = model.apply(S, a.key)
          local dw = model.advance(W, 2.9)
          local P = model.peekApply(S, a.key)
          local dp = model.advance(P, 2.9)
          assert.are.equal(dw, dp, a.key)
          assert.are.same(view(W), view(P), a.key)
        end
      end
    end
  end)

  -- a chain of scratch states through both buffers and back: the third one gets the first
  -- buffer's own entries (cooldowns run out in the first wait) as ready ones from its source,
  -- and setCd changes them in place
  it("a chain of peeks back into the first buffer, advanced in place, equals the applied chain", function()
    local list = states()
    local S = fixtures.state({ spells = { earthShock = { cd = 0.3 }, flameShock = { cd = 0.3 }, frostShock = { cd = 0.3 },
                                          stormstrike = { cd = 0.2 }, lavaLash = { cd = 0.35 } } })
    S.memo = {}
    list[#list + 1] = S
    for _, S0 in ipairs(list) do
      local R2 = model.wait(model.wait(S0, 0.4), 0.1)
      for _, b in ipairs(model.actions(R2)) do
        if b.key ~= "waitSwing" and b.readyIn <= 0 then
          local R3, dr = model.apply(R2, b.key)
          local dr2 = model.advance(R3, 2.2)
          local P3, dp = model.peekApply(model.peekWait(model.peekWait(S0, 0.4), 0.1), b.key)
          local dp2 = model.advance(P3, 2.2)
          assert.are.equal(dr, dp, b.key)
          assert.are.equal(dr2, dp2, b.key)
          assert.are.same(view(R3), view(P3), b.key)
        end
      end
    end
  end)

  it("a peek back into the first buffer leaves its source's mana alone", function()
    local S = fixtures.state({ buffs = { rage = 10 }, swing = { mh = { next = 0.1 }, oh = { next = 0.2 } } })
    S.memo = {}
    local P1 = model.peekWait(S, 0.5)   -- both hands swing: Rage returns mana (the buffer's own player)
    assert.is_true(P1.player ~= S.player)
    local P2 = model.peekWait(P1, 0.01) -- no swing: the same player as P1
    assert.are.equal(P1.player, P2.player)
    local mana = P2.player.mana
    local P3 = model.peekApply(P2, "earthShock") -- back into P1's buffer, mana spent
    assert.are.equal(mana, P2.player.mana)
    assert.are.equal(mana - S.spells.earthShock.cost, P3.player.mana)
  end)

  it("clone keeps every spells.CATALOG key and never shares what the model changes", function()
    local S = fixtures.state({})
    local n = model.clone(S)
    for _, meta in ipairs(spells.CATALOG) do assert.are.equal(S.spells[meta.key], n.spells[meta.key], meta.key) end
    for _, k in ipairs({ "buffs", "target", "totems", "swing", "pets", "inflight" }) do assert.are_not.equal(S[k], n[k], k) end
    assert.are_not.equal(S.buffs.mw, n.buffs.mw)
    assert.are_not.equal(S.target.ss, n.target.ss)
    assert.are_not.equal(S.swing.mh, n.swing.mh)
  end)
end)

describe("model.cooldownAllowed", function()
  local function gated(mode, target)
    local S = base()
    S.cooldowns = { feralSpirit = mode, fireElemental = mode, shamanisticRage = mode }
    target = target or {}
    S.target.isBoss, S.target.ttd = target.isBoss, target.ttd
    return S
  end

  it("without options (nil S.cooldowns or nil entry) every key is allowed, as before", function()
    local S = base()
    S.target.ttd = nil
    assert.is_true(model.cooldownAllowed(S, "fireElemental"))
    S.cooldowns = {}
    assert.is_true(model.cooldownAllowed(S, "feralSpirit"))
    assert.is_true(model.cooldownAllowed(gated("never"), "stormstrike")) -- not a gated key
  end)

  it("always / never ignore the target", function()
    assert.is_true(model.cooldownAllowed(gated("always", { ttd = 1 }), "fireElemental"))
    assert.is_false(model.cooldownAllowed(gated("never", { isBoss = true, ttd = 600 }), "fireElemental"))
  end)

  it("boss only: the boss flag, not the time to die", function()
    assert.is_true(model.cooldownAllowed(gated("boss", { isBoss = true, ttd = 5 }), "feralSpirit"))
    assert.is_false(model.cooldownAllowed(gated("boss", { ttd = 600 }), "feralSpirit"))
  end)

  it("auto: a boss, or a target that lives half the cooldown's active time; unknown ttd off a boss: no", function()
    assert.are.equal(22.5, model.COOLDOWN_TTD.feralSpirit)
    assert.are.equal(60, model.COOLDOWN_TTD.fireElemental)
    assert.is_true(model.cooldownAllowed(gated("auto", { isBoss = true, ttd = nil }), "fireElemental"))
    assert.is_false(model.cooldownAllowed(gated("auto", { ttd = nil }), "feralSpirit"))
    assert.is_false(model.cooldownAllowed(gated("auto", { ttd = 12 }), "feralSpirit"))
    assert.is_true(model.cooldownAllowed(gated("auto", { ttd = 30 }), "feralSpirit"))
    assert.is_false(model.cooldownAllowed(gated("auto", { ttd = 30 }), "fireElemental"))
    assert.is_true(model.cooldownAllowed(gated("auto", { ttd = 90 }), "fireElemental"))
  end)

  it("readyIn and the candidate list skip a key that is not allowed", function()
    local S = gated("never")
    assert.is_nil(model.readyIn(S, "shamanisticRage"))
    for _, a in ipairs(model.actions(S)) do assert.are_not.equal("shamanisticRage", a.key) end
    S.cooldowns.shamanisticRage = "always"
    assert.are.equal(0, model.readyIn(S, "shamanisticRage"))
  end)

  it("the options and the boss flag carry over to the next states (apply and peek alike)", function()
    local S = gated("boss", { isBoss = true })
    local n = model.apply(S, "stormstrike")
    assert.are.equal(S.cooldowns, n.cooldowns)
    assert.is_true(n.target.isBoss)
    local p = model.peekApply(S, "stormstrike")
    assert.are.equal(S.cooldowns, p.cooldowns)
    assert.is_true(p.target.isBoss)
    assert.is_true(model.cooldownAllowed(p, "feralSpirit"))
  end)
end)
