local spells = require("spells")
local damage = require("damage")

local ROWS = {
  lightningBolt = { id = 49238, level = 79, min = 715, max = 815, coef = 0.714 },
  earthShock = { id = 49231, level = 79, min = 849, max = 895, coef = 0.386 },
  chainLightning = { id = 49271, level = 80, min = 973, max = 1111, coef = 0.571 },
  fireNova = { id = 61654, level = 80, min = 893, max = 997, coef = 0.214 },
  flameShock = { id = 49233, level = 80, min = 500, max = 500, coef = 0.214, tick = 139, tickCoef = 0.1, ticks = 6, period = 3 },
  magmaTotem = { id = 58735, level = 78, min = 371, max = 371, coef = 0.1 },
  lightningShield = { id = 49279, level = 80, min = 380, max = 380, coef = 0.267 },
}
ROWS.searingTotem = { id = 58702, level = 80, min = 90, max = 120, coef = 0.167 }
local ROWS20 = {
  lightningBolt = { id = 915, level = 20, min = 83, max = 95, coef = 0.714 },
}

local function s80(o)
  local S = {
    now = 100, gcdRemains = 0, castRemains = 0, gcd = 1.5, latency = 0.15, mode = "raid",
    player = { level = 80, mana = 8000, manaMax = 10000, baseMana = 4396, hpPct = 1, ap = 4000,
               spNature = 1200, spFire = 1200, meleeCrit = 0.30, spellCrit = 0.20, meleeHit = 0.08,
               spellHit = 0.10, spellHaste = 1.0, meleeHaste = 1.0, moving = false, inCombat = true },
    weapons = { mh = { speed = 2.6, min = 600, max = 900, enchant = "wf" },
                oh = { speed = 2.6, min = 300, max = 450, enchant = "ft" } },
    talents = {},
    spells = {
      lightningBolt = { id = 49238, rank = 14, cd = 0, cost = 300, cast = 2.5 },
      earthShock = { id = 49231, rank = 10, cd = 0, cost = 800, cast = 0 },
      chainLightning = { id = 49271, rank = 8, cd = 0, cost = 1100, cast = 2 },
      fireNova = { id = 61657, rank = 9, cd = 0, cost = 900, cast = 0 },
      flameShock = { id = 49233, rank = 9, cd = 0, cost = 700, cast = 0 },
      magmaTotem = { id = 58734, rank = 7, cd = 0, cost = 1000, cast = 0 },
      lightningShield = { id = 49281, rank = 11, cd = 0, cost = 0, cast = 0 },
    },
    buffs = { mw = { stacks = 0, remains = 0 }, ls = { charges = 0, remains = 0 },
              flurry = { charges = 0, remains = 0 }, rage = 0, lust = 0, em = 0 },
    target = { exists = true, enemy = true, level = 83, hp = 1e6, hpMax = 1e6, hpPct = 1, ttd = 60,
               range = "melee", fs = 0, ss = { charges = 0, remains = 0 } },
    totems = { fire = { remains = 0 }, water = { remains = 0 } },
    swing = { attacking = true, mh = { next = 1, speed = 2.6 }, oh = { next = 1, speed = 2.6 }, resetByInstant = {} },
    enemies = { melee = 1, nearby = 1 },
    inflight = {}, pets = { wolves = 0 },
  }
  for k, v in pairs(o or {}) do S[k] = v end
  return S
end

local function s20()
  local S = s80()
  S.player.level, S.player.ap, S.player.spNature, S.player.spFire = 20, 300, 50, 50
  S.player.meleeCrit, S.player.spellCrit, S.player.meleeHit, S.player.spellHit = 0.05, 0.05, 0, 0
  S.weapons = { mh = { speed = 3.4, min = 40, max = 60, enchant = "rb", twoHand = true } }
  S.target.level = 20
  S.spells = { lightningBolt = { id = 915, rank = 4, cd = 0, cost = 60, cast = 2.5 } }
  return S
end

local AM80 = 1 - 10643 / (10643 + 15232.5)
local AP14 = 4000 / 14

describe("damage", function()
  local orig
  before_each(function()
    orig = spells.rank
    spells.rank = function(key, id)
      if id == 915 then return ROWS20.lightningBolt end
      return ROWS[key]
    end
  end)
  after_each(function() spells.rank = orig end)

  describe("spell hit and crit", function()
    it("uses 17% base miss against +3 level and subtracts hit", function()
      assert.are.near(0.93, damage.spellHit(s80()), 1e-9)
    end)
    it("uses 4% base miss against same level", function()
      assert.are.near(0.96, damage.spellHit(s20()), 1e-9)
    end)
    it("adds 11% miss per level above +3", function()
      local S = s20(); S.player.spellHit = 0
      for d, hit in pairs({ [4] = 0.72, [5] = 0.61, [6] = 0.50 }) do
        S.target.level = S.player.level + d
        assert.are.near(hit, damage.spellHit(S), 1e-9)
      end
      S.target.level = S.player.level + 20
      assert.are.equal(0, damage.spellHit(S))
    end)
    it("treats unknown target level (-1) as +3", function()
      local S = s80(); S.target.level = -1
      assert.are.near(0.93, damage.spellHit(S), 1e-9)
    end)
    it("crit factor 1.5 base, +0.1 per Elemental Fury rank", function()
      local S = s80()
      assert.are.near(1.1, damage.spellCritFactor(S), 1e-9)
      S.talents.elementalFury = 5
      assert.are.near(1.2, damage.spellCritFactor(S), 1e-9)
    end)
  end)

  describe("direct spells", function()
    it("Lightning Bolt at 80", function()
      assert.are.near(1659.1014, damage.action(s80(), "lightningBolt"), 1e-6)
    end)
    it("Lightning Bolt at 20", function()
      assert.are.near(122.7048, damage.action(s20(), "lightningBolt"), 1e-6)
    end)
    it("Concussion adds 1% per rank", function()
      local S = s80(); S.talents.concussion = 5
      assert.are.near(1659.1014 * 1.05, damage.action(S, "lightningBolt"), 1e-6)
    end)
    it("Stormstrike debuff adds 20% to nature spells", function()
      local S = s80(); S.target.ss = { charges = 2, remains = 10 }
      assert.are.near(1659.1014 * 1.2, damage.action(S, "lightningBolt"), 1e-6)
      assert.are.near((872 + 0.386 * 1200) * 0.93 * 1.1 * 1.2, damage.action(S, "earthShock"), 1e-6)
    end)
    it("Stormstrike debuff does not affect fire", function()
      local S = s80(); S.target.ss = { charges = 2, remains = 10 }
      assert.are.near((500 + 0.214 * 1200) * 0.93 * 1.1, damage.action(S, "flameShock"), 1e-6)
    end)
    it("Chain Lightning hits up to 3 targets with 30% falloff", function()
      local S = s80(); S.enemies.nearby = 5
      local single = (1042 + 0.571 * 1200) * 0.93 * 1.1
      assert.are.equal(3, damage.targets(S, "chainLightning"))
      assert.are.near(single * 2.19, damage.action(S, "chainLightning"), 1e-6)
    end)
    it("Fire Nova hits every nearby enemy, Improved Fire Nova +10%/rank", function()
      local S = s80(); S.enemies.nearby = 4; S.talents.improvedFireNova = 2
      local per = (945 + 0.214 * 1200) * 0.93 * 1.1 * 1.2
      assert.are.equal(4, damage.targets(S, "fireNova"))
      assert.are.near(per * 4, damage.action(S, "fireNova"), 1e-6)
    end)
    it("totems, shield, cooldowns have no immediate damage", function()
      local S = s80()
      for _, k in ipairs({ "magmaTotem", "searingTotem", "fireElemental", "feralSpirit",
                           "lightningShield", "callOfElements", "shamanisticRage" }) do
        assert.are.equal(0, damage.action(S, k))
      end
    end)
    it("unknown spell returns 0", function()
      local S = s80(); S.spells.lightningBolt = nil
      assert.are.equal(0, damage.action(S, "lightningBolt"))
    end)
  end)

  describe("flame shock dot", function()
    it("returns per tick, ticks, period", function()
      local per, ticks, period = damage.dot(s80(), "flameShock")
      assert.are.near((139 + 0.1 * 1200) * 1.1, per, 1e-6)
      assert.are.equal(6, ticks)
      assert.are.equal(3, period)
    end)
    it("periodic flameShock = perTick / period", function()
      local S = s80()
      local per = damage.dot(S, "flameShock")
      assert.are.near(per / 3, damage.periodic(S, "flameShock"), 1e-9)
    end)
    it("magma pulses every 2 s on every nearby enemy", function()
      local S = s80(); S.enemies.nearby = 3
      assert.are.near((371 + 0.1 * 1200) * 0.93 * 1.1 * 3 / 2, damage.periodic(S, "magmaTotem"), 1e-6)
    end)
    it("Fire Nova and Magma hit around the totem: the whole fight with the target in melee, " ..
       "else only who hits the shaman in melee", function()
      local S = s80(); S.enemies = { melee = 1, nearby = 4 }
      assert.are.equal(4, damage.targets(S, "fireNova"))
      assert.are.equal(4, damage.targets(S, "magmaTotem"))
      S.target.range = "30"
      assert.are.equal(1, damage.targets(S, "fireNova"))
      S.enemies = { melee = 0, nearby = 4 }
      assert.are.equal(0, damage.targets(S, "magmaTotem"))
      assert.are.equal(0, damage.action(S, "fireNova"))
      assert.are.equal(0, damage.periodic(S, "magmaTotem"))
      -- Chain Lightning still jumps between the enemies of the fight
      assert.are.equal(3, damage.targets(S, "chainLightning"))
    end)
    it("magma dot = one pulse on one target, 10 pulses every 2 s", function()
      local S = s80(); S.enemies.nearby = 3
      local per, pulses, period = damage.dot(S, "magmaTotem")
      assert.are.near((371 + 0.1 * 1200) * 0.93 * 1.1, per, 1e-6)
      assert.are.equal(10, pulses)
      assert.are.equal(damage.MAGMA_PERIOD, period)
    end)
    it("searing dot = one shot, 24 shots every 2.5 s, Call of Flame +5%/rank", function()
      local S = s80(); S.talents.callOfFlame = 3
      S.spells.searingTotem = { id = 58704, rank = 10, cd = 0, cost = 300, cast = 0 }
      local per, pulses, period = damage.dot(S, "searingTotem")
      assert.are.near((105 + 0.167 * 1200) * 0.93 * 1.1 * 1.15, per, 1e-6)
      assert.are.equal(24, pulses)
      assert.are.equal(damage.SEARING_PERIOD, period)
      assert.are.near(per / period, damage.periodic(S, "searingTotem"), 1e-9)
    end)
    it("Searing Totem shoots 20 yards from the shaman's feet: a target at 30 or far is out of reach", function()
      local S = s80(); S.enemies = { melee = 0, nearby = 1 }
      for _, r in ipairs({ "melee", "20" }) do
        S.target.range = r
        assert.are.equal(0, damage.fireDelay(S, "searingTotem"), r)
        assert.are.equal(3, damage.fireUptime(S, "searingTotem", 3), r)
      end
      for _, r in ipairs({ "30", "far" }) do
        S.target.range = r
        assert.is_nil(damage.fireDelay(S, "searingTotem"), r)
        assert.are.equal(0, damage.fireUptime(S, "searingTotem", 3), r)
        -- the other fire sources are not limited by it (Magma has totemTargets of its own)
        for _, src in ipairs({ "magmaTotem", "fireElemental" }) do
          assert.are.equal(3, damage.fireUptime(S, src, 3), src)
        end
      end
      -- an enemy hitting the shaman in melee stands in reach: the totem shoots it
      S.enemies.melee = 1
      assert.are.equal(3, damage.fireUptime(S, "searingTotem", 3))
    end)
    it("an approaching target enters the Searing reach SEARING_LEAD before melee", function()
      local S = s80(); S.enemies = { melee = 0, nearby = 1 }
      S.target.range = "far"; S.target.meleeIn = 5
      assert.are.near((20 - 5) / 7, damage.SEARING_LEAD, 1e-9)
      assert.are.near(5 - damage.SEARING_LEAD, damage.fireDelay(S, "searingTotem"), 1e-9)
      assert.are.near(10 - (5 - damage.SEARING_LEAD), damage.fireUptime(S, "searingTotem", 10), 1e-9)
      assert.are.equal(0, damage.fireUptime(S, "searingTotem", 1))
      S.target.meleeIn = 1
      assert.are.equal(0, damage.fireDelay(S, "searingTotem"))
      assert.are.equal(2, damage.fireUptime(S, "searingTotem", 2))
    end)
    it("other keys and unknown spells return 0, 0, 1", function()
      local S = s80()
      for _, k in ipairs({ "lightningBolt", "earthShock", "fireElemental", "searingTotem" }) do
        local a, b, c = damage.dot(S, k)
        assert.are.same({ 0, 0, 1 }, { a, b, c })
      end
    end)
  end)

  describe("armor", function()
    it("boss armor for level 83 and unknown", function()
      assert.are.equal(10643, damage.targetArmor(83))
      assert.are.equal(10643, damage.targetArmor(-1))
      assert.are.equal(10643, damage.targetArmor(nil))
    end)
    it("interpolates by level", function()
      assert.are.equal(600, damage.targetArmor(20))
      assert.are.equal(1100, damage.targetArmor(30))
    end)
    it("mitigation formula for level 80 attacker", function()
      assert.are.near(AM80, damage.armorMult(s80()), 1e-12)
    end)
    it("explicit target.armor overrides", function()
      local S = s80(); S.target.armor = 0
      assert.are.equal(1, damage.armorMult(S))
    end)
  end)

  describe("melee", function()
    it("white table with dual wield vs +3", function()
      local t = damage.meleeTable(s80(), true)
      assert.are.near(0.19, t.miss, 1e-9)
      assert.are.near(0.065, t.dodge, 1e-9)
      assert.are.near(0.24, t.glance, 1e-9)
      assert.are.near(0.252, t.crit, 1e-9)
      assert.are.near(0.937, t.factor, 1e-9)
      assert.are.near(0.745, t.landed, 1e-9)
    end)
    it("yellow table has no glancing and no dual wield penalty", function()
      local t = damage.meleeTable(s80(), false)
      assert.are.near(0, t.miss, 1e-9)
      assert.are.near(1.187, t.factor, 1e-9)
      assert.are.near(0.935, t.landed, 1e-9)
    end)
    it("white main hand at 80", function()
      assert.are.near(750 * 0.937 * AM80, damage.white(s80(), "mh"), 1e-6)
    end)
    it("level 20 two-hander, rockbiter adds nothing", function()
      assert.are.near(36.75, damage.white(s20(), "mh"), 1e-9)
      assert.are.near(36.75, damage.auto(s20(), "mh"), 1e-9)
    end)
    it("normalized weapon damage uses 2.4 (3.3 for two-hand)", function()
      local S = s80()
      assert.are.near(750 - AP14 * 2.6 + AP14 * 2.4, damage.normalized(S, "mh"), 1e-9)
      assert.are.near(375 + 0.5 * (AP14 * 2.4 - AP14 * 2.6), damage.normalized(S, "oh"), 1e-9)
      local L = s20()
      assert.are.near(50 - 300 / 14 * 3.4 + 300 / 14 * 3.3, damage.normalized(L, "mh"), 1e-9)
    end)
    it("windfury: 20% with 3 s ICD, 2 attacks with AP bonus", function()
      local S = s80()
      local dmg, procs = damage.wf(S)
      assert.are.near(0.2 / 1.2, procs, 1e-9)
      assert.are.near((0.2 / 1.2) * 2 * (750 + 1250 / 14 * 2.6) * 1.187 * AM80, dmg, 1e-6)
    end)
    -- tooltip 29080: "Increases the damage caused by your Windfury Weapon effect by 40%";
    -- wowsims weapon_imbues.go: DamageMultiplier 1.13 / 1.27 / 1.4 on the whole attack
    it("windfury: Elemental Weapons multiplies the whole attack's damage, not the AP bonus", function()
      for rank, mult in ipairs({ 1.13, 1.27, 1.4 }) do
        local S = s80(); S.talents.elementalWeapons = rank
        local dmg = damage.wf(S)
        assert.are.near((0.2 / 1.2) * 2 * (750 + 1250 / 14 * 2.6) * mult * 1.187 * AM80, dmg, 1e-6)
      end
    end)
    it("no windfury without the enchant", function()
      local S = s80(); S.weapons.mh.enchant = "ft"
      local dmg, procs = damage.wf(S)
      assert.are.equal(0, dmg); assert.are.equal(0, procs)
    end)
    it("flametongue hit on off hand", function()
      assert.are.near((52 * 2.6 + 0.1 * 1200) * 0.93 * 1.1, damage.ftHit(s80(), "oh"), 1e-6)
      assert.are.equal(0, damage.ftHit(s80(), "mh"))
    end)
    it("weapon formulas use the weapon's own speed, not the hasted swing interval", function()
      local plain = s80(); plain.talents.maelstromWeapon = 5
      local hasted = s80(); hasted.talents.maelstromWeapon = 5
      hasted.weapons.mh.speed, hasted.weapons.mh.base = 1.73, 2.6
      hasted.weapons.oh.speed, hasted.weapons.oh.base = 1.73, 2.6
      for _, f in ipairs({ "normalized", "ftHit", "mwPerHit", "rageChance" }) do
        for _, h in ipairs({ "mh", "oh" }) do
          assert.are.near(damage[f](plain, h), damage[f](hasted, h), 1e-9)
        end
      end
      local _, p1 = damage.wf(plain)
      local d2, p2 = damage.wf(hasted)
      assert.are.near(damage.wf(plain) / p1, d2 / p2, 1e-9)
    end)
    it("static shock needs shield charges", function()
      local S = s80(); S.talents.staticShock = 3
      assert.are.equal(0, damage.staticHit(S))
      S.buffs.ls = { charges = 3, remains = 600 }
      assert.are.near(0.06 * (380 + 0.267 * 1200) * 0.93 * 1.1, damage.staticHit(S), 1e-6)
    end)
    it("auto off hand = white + flametongue per landed hit", function()
      local S = s80()
      local expected = damage.white(S, "oh") + damage.ftHit(S, "oh") * 0.745
      assert.are.near(expected, damage.auto(S, "oh"), 1e-6)
    end)
    it("auto main hand includes windfury", function()
      local S = s80()
      local wf = damage.wf(S)
      assert.are.near(damage.white(S, "mh") + wf, damage.auto(S, "mh"), 1e-6)
    end)
  end)

  describe("weapon strikes", function()
    it("Stormstrike = both weapons normalized, yellow, armor", function()
      local S = s80(); S.weapons.oh.enchant = nil
      S.spells.stormstrike = { id = 17364, rank = 1, cd = 0, cost = 400, cast = 0 }
      local w = (750 - AP14 * 2.6 + AP14 * 2.4) + (375 + 0.5 * (AP14 * 2.4 - AP14 * 2.6))
      assert.are.near(w * 1.187 * AM80, damage.action(S, "stormstrike"), 1e-6)
    end)
    -- tooltip 60103 effect "Weapon Damage - %: 100" (not Normalized Weapon Damage, as Stormstrike);
    -- wowsims lavalash.go: OHWeaponDamage(sim, AP), the weapon's own speed
    it("Lava Lash = off hand not normalized, +25% with flametongue, no armor, plus FT proc", function()
      local S = s80()
      S.spells.lavaLash = { id = 60103, rank = 1, cd = 0, cost = 200, cast = 0 }
      local expected = 375 * 1.25 * 1.187 + damage.ftHit(S, "oh") * 0.935
      assert.are.near(expected, damage.action(S, "lavaLash"), 1e-6)
    end)
    it("Lava Lash with a fast off hand: the tooltip damage, the hasted swing does not matter", function()
      local S = s80(); S.weapons.oh = { speed = 1.0, base = 1.5, min = 200, max = 300 }
      S.spells.lavaLash = { id = 60103, rank = 1, cd = 0, cost = 200, cast = 0 }
      assert.are.near(250 * 1.187, damage.action(S, "lavaLash"), 1e-6)
    end)
    it("Lava Lash without off hand = 0", function()
      local S = s80(); S.weapons.oh = nil
      S.spells.lavaLash = { id = 60103, rank = 1, cd = 0, cost = 200, cast = 0 }
      assert.are.equal(0, damage.action(S, "lavaLash"))
    end)
  end)

  describe("maelstrom", function()
    it("no talent, no stacks", function()
      assert.are.equal(0, damage.mwPerSwing(s80(), "oh"))
    end)
    it("PPM 2 per rank, scaled by landed white hits", function()
      local S = s80(); S.talents.maelstromWeapon = 5
      assert.are.near(10 * 2.6 / 60 * 0.745, damage.mwPerSwing(S, "oh"), 1e-9)
    end)
    it("main hand also counts windfury extra attacks", function()
      local S = s80(); S.talents.maelstromWeapon = 5
      local c = 10 * 2.6 / 60
      local _, procs = damage.wf(S)
      assert.are.near(c * 0.745 + procs * 2 * c * 0.935, damage.mwPerSwing(S, "mh"), 1e-9)
    end)
    it("per special hit uses yellow landed", function()
      local S = s80(); S.talents.maelstromWeapon = 5
      assert.are.near(10 * 2.6 / 60 * 0.935, damage.mwPerHit(S, "oh"), 1e-9)
    end)
  end)
end)

describe("damage with generated spell data", function()
  local fixtures = require("fixtures")

  it("Flame Shock rank 9 ticks 6 times every 3 s (18 s)", function()
    local S = fixtures.state()
    local per, ticks, period = damage.dot(S, "flameShock")
    assert.is_true(per > 0)
    assert.are.equal(6, ticks)
    assert.are.equal(3, period)
  end)

  it("uses the damage numbers of the paired totem spell for Fire Nova", function()
    local S = fixtures.state({ talents = { concussion = 0, callOfFlame = 0 } })
    local hit, crit = damage.spellHit(S), damage.spellCritFactor(S)
    assert.are.near((945 + 0.214 * 1200) * hit * crit, damage.action(S, "fireNova"), 1e-6)
  end)

  it("every catalog action returns a finite number with and without an off hand", function()
    local spells = require("spells")
    for _, oh in ipairs({ true, false }) do
      local S = fixtures.state({ enemies = { nearby = 3 } })
      if not oh then S.weapons.oh = nil; S.swing.oh = nil end
      for _, meta in ipairs(spells.CATALOG) do
        local v = damage.action(S, meta.key)
        assert.is_true(v >= 0 and v < 1e6, meta.key)
        local a, b, c = damage.dot(S, meta.key)
        assert.is_true(a >= 0 and b >= 0 and c > 0, meta.key)
      end
      assert.are.equal(0, damage.auto(S, "oh") * (oh and 0 or 1))
    end
  end)
end)

describe("damage per-search memo", function()
  local fixtures = require("fixtures")
  local util = require("util")

  it("gives the same numbers as direct calls for every buff combination", function()
    local spells = require("spells")
    for _, ls in ipairs({ 0, 3 }) do
      for _, ss in ipairs({ 0, 2 }) do
        local S = fixtures.state({ buffs = { ls = { charges = ls } }, target = { ss = { charges = ss, remains = 5 } } })
        local M = util.copy(S)
        M.memo = {}
        for _ = 1, 2 do -- second round reads the memo
          for _, meta in ipairs(spells.CATALOG) do
            assert.are.equal(damage.action(S, meta.key), damage.action(M, meta.key), meta.key)
          end
          for _, h in ipairs({ "mh", "oh" }) do
            assert.are.equal(damage.auto(S, h), damage.auto(M, h))
            assert.are.equal(damage.mwPerSwing(S, h), damage.mwPerSwing(M, h))
            assert.are.equal(damage.auto(S, h), damage.swingStats(M)[h])
          end
          for _, src in ipairs(damage.PERIODIC) do
            assert.are.equal(damage.periodic(S, src), damage.periodic(M, src))
            assert.are.equal(damage.periodic(S, src), damage.rates(M)[src])
          end
        end
      end
    end
  end)

  it("the Searing reach follows the range even when it changes inside one search", function()
    -- the approaching mob (target.meleeIn) moves the range inside one search: the memo keeps
    -- the per-target dps only, the reach is read from the state on every call
    local S = fixtures.state({ target = { range = "melee" }, enemies = { melee = 0, nearby = 1 } })
    S.memo = {}
    local dps = damage.rates(S).searingTotem
    assert.is_true(dps > 0)
    assert.are.equal(2, damage.fireUptime(S, "searingTotem", 2))
    S.target.range = "far"
    assert.are.equal(dps, damage.rates(S).searingTotem)
    assert.are.equal(0, damage.fireUptime(S, "searingTotem", 2))
    S.target.meleeIn = damage.SEARING_LEAD + 0.5
    assert.are.near(1.5, damage.fireUptime(S, "searingTotem", 2), 1e-9)
    S.target.meleeIn, S.target.range = nil, "20"
    assert.are.equal(2, damage.fireUptime(S, "searingTotem", 2))
  end)
end)
