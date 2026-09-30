local G = require("game_mock")
local snapshot = require("snapshot")
local spells = require("spells")

local function ranks(key) return spells.byKey[key].ranks end
local function top(key) local r = ranks(key); return r[#r] end

local function ctx(extra)
  local c = {
    swing = { state = function() return { attacking = true, mh = { next = 1.1, speed = 2.6 }, oh = { next = 0.3, speed = 2.6 }, resetByInstant = {} } end },
    enemies = { counts = function() return 0, 2 end },
    ttd = { add = function() end, smoothed = function() return 42 end },
    inflight = {}, mode = "auto",
  }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end

local function install(cfg)
  cfg.target = cfg.target or { level = 80, hp = 5000, hpMax = 10000, guid = "Creature-7" }
  return G.install(cfg)
end

describe("snapshot", function()
  it("picks the highest known rank and skips unknown spells", function()
    local lb = ranks("lightningBolt")
    install({ known = { [lb[1]] = true, [lb[2]] = true, [lb[3]] = true } })
    local S = snapshot.build(ctx())
    assert.are.equal(lb[3], S.spells.lightningBolt.id)
    assert.are.equal(3, S.spells.lightningBolt.rank)
    assert.is_nil(S.spells.stormstrike)
  end)

  it("falls back to the spellbook when IsSpellKnown misses a talent spell", function()
    install({ bookOnly = { [17364] = true } })
    local S = snapshot.build(ctx())
    assert.are.equal(17364, S.spells.stormstrike.id)
  end)

  it("reads Maelstrom stacks, shield charges and only the player's debuffs", function()
    install({
      known = { [top("lightningBolt")] = true },
      auras = {
        player = { HELPFUL = { { name = "Maelstrom Weapon", count = 4, expires = 106 }, { name = "Lightning Shield", count = 3, expires = 700 } } },
        target = { HARMFUL = { { name = "Flame Shock", expires = 109, caster = "player" },
                               { name = "Stormstrike", count = 2, expires = 110, caster = "raid3" } } },
      },
    })
    local S = snapshot.build(ctx())
    assert.are.equal(4, S.buffs.mw.stacks)
    assert.are.near(6, S.buffs.mw.remains, 1e-9)
    assert.are.equal(3, S.buffs.ls.charges)
    assert.are.near(9, S.target.fs, 1e-9)
    assert.are.equal(0, S.target.ss.charges)
  end)

  it("reads weapon imbues from the weapon tooltip", function()
    install({ enchants = { mh = true, oh = true },
              tooltip = { [16] = { "Some Axe", "Windfury 8 (30 min)" }, [17] = { "Other Axe", "Flametongue 10 (30 min)" } } })
    local S = snapshot.build(ctx())
    assert.are.equal("wf", S.weapons.mh.enchant)
    assert.are.equal("ft", S.weapons.oh.enchant)
  end)

  it("an imbue it does not know (Frostbrand, Earthliving) is 'other', not missing", function()
    install({ enchants = { mh = true, oh = true },
              tooltip = { [16] = { "Some Axe", "Frostbrand 9 (30 min)" }, [17] = { "Other Axe", "Earthliving 6 (30 min)" } } })
    local S = snapshot.build(ctx())
    assert.are.equal("other", S.weapons.mh.enchant)
    assert.are.equal("other", S.weapons.oh.enchant)
    local alert = require("runtime").alert(S)
    assert.is_true(alert == nil or alert.key ~= "noEnchant")
  end)

  it("has no off-hand with a two-hander and no imbue without an enchant", function()
    install({ speed = { 3.5, nil }, enchants = {} })
    local S = snapshot.build(ctx({ swing = { state = function() return { attacking = true, mh = { next = 1, speed = 3.5 } } end } }))
    assert.is_nil(S.weapons.oh)
    assert.is_nil(S.weapons.mh.enchant)
    assert.is_nil(S.swing.oh)
    assert.are.same({}, S.swing.resetByInstant)
  end)

  it("classifies fire totems and reads the water totem", function()
    install({ totems = { [1] = { "Magma Totem VII", 95, 20 }, [3] = { "Mana Spring Totem VIII", 50, 300 } } })
    local S = snapshot.build(ctx())
    assert.are.equal("magma", S.totems.fire.kind)
    assert.are.near(15, S.totems.fire.remains, 1e-9)
    assert.are.near(250, S.totems.water.remains, 1e-9)
    install({ totems = { [1] = { "Fire Elemental Totem", 90, 120 } } })
    assert.are.equal("fireElemental", snapshot.build(ctx()).totems.fire.kind)
    install({ totems = { [1] = { "Totem of Wrath IV", 90, 300 } } })
    assert.are.equal("other", snapshot.build(ctx()).totems.fire.kind)
    install({})
    assert.is_nil(snapshot.build(ctx()).totems.fire.kind)
  end)

  it("guesses mob health when the client only gives percent", function()
    install({ target = { level = 80, hp = 50, hpMax = 100 } })
    local S = snapshot.build(ctx())
    assert.is_true(S.target.guessed)
    assert.are.equal(12000, S.target.hpMax)
    assert.are.equal(6000, S.target.hp)
    install({ target = { level = 80, hp = 5000, hpMax = 20000 } })
    S = snapshot.build(ctx())
    assert.is_false(S.target.guessed)
    assert.are.equal(20000, S.target.hpMax)
    assert.are.equal(42, S.target.ttd)
  end)

  it("guesses the level of skull targets", function()
    install({ level = 80, target = { level = -1, hp = 1e6, hpMax = 1e6 } })
    local S = snapshot.build(ctx())
    assert.are.equal(83, S.target.level)
    assert.is_true(S.target.guessed)
  end)

  it("returns an empty target when there is none", function()
    G.install({})
    local S = snapshot.build(ctx())
    assert.is_false(S.target.exists)
    assert.are.equal("far", S.target.range)
  end)

  it("picks the mode from the group and honours the override", function()
    install({ raid = 10 }); assert.are.equal("raid", snapshot.build(ctx()).mode)
    install({ party = 2 }); assert.are.equal("group", snapshot.build(ctx()).mode)
    install({}); assert.are.equal("solo", snapshot.build(ctx()).mode)
    install({}); assert.are.equal("group", snapshot.build(ctx({ mode = "group" })).mode)
  end)

  it("measures range with the shortest spell that reaches", function()
    local known = { [top("stormstrike")] = true, [top("earthShock")] = true, [top("lightningBolt")] = true }
    install({ known = known, inRange = { Stormstrike = 0, ["Earth Shock"] = 1, ["Lightning Bolt"] = 1 } })
    assert.are.equal("20", snapshot.build(ctx()).target.range)
    install({ known = known, inRange = { Stormstrike = 1 } })
    assert.are.equal("melee", snapshot.build(ctx()).target.range)
    install({ known = known, inRange = { Stormstrike = 0, ["Earth Shock"] = 0, ["Lightning Bolt"] = 0 } })
    assert.are.equal("far", snapshot.build(ctx()).target.range)
    install({ known = { [top("earthShock")] = true, [top("lightningBolt")] = true }, interact = true, inRange = {} })
    assert.are.equal("melee", snapshot.build(ctx()).target.range)
  end)

  it("derives spell haste from the real Lightning Bolt cast time", function()
    install({ known = { [top("lightningBolt")] = true }, castMs = { ["Lightning Bolt"] = 2000 } })
    local S = snapshot.build(ctx())
    assert.are.near(1.25, S.player.spellHaste, 1e-9)
    assert.are.near(1.2, S.gcd, 1e-9)
    install({ known = { [top("lightningBolt")] = true }, castMs = { ["Lightning Bolt"] = 1200 },
              auras = { player = { HELPFUL = { { name = "Maelstrom Weapon", count = 2, expires = 110 } } } } })
    assert.are.near(1.25, snapshot.build(ctx()).player.spellHaste, 1e-9)
    install({ known = { [top("lightningBolt")] = true }, castMs = { ["Lightning Bolt"] = 0 }, ratings = { [20] = 10 },
              auras = { player = { HELPFUL = { { name = "Maelstrom Weapon", count = 5, expires = 110 } } } } })
    assert.are.near(1.10, snapshot.build(ctx()).player.spellHaste, 1e-9)
  end)

  it("separates spell cooldowns from the global cooldown", function()
    install({ known = { [top("stormstrike")] = true, [top("earthShock")] = true, [top("lightningBolt")] = true },
              castMs = { ["Lightning Bolt"] = 2500 },
              cooldowns = { Stormstrike = { 98, 8 }, ["Earth Shock"] = { 99.5, 1.5 }, ["Lightning Bolt"] = { 99.5, 1.5 } } })
    local S = snapshot.build(ctx())
    assert.are.near(6, S.spells.stormstrike.cd, 1e-9)
    assert.are.equal(0, S.spells.earthShock.cd)
    assert.are.near(1.0, S.gcdRemains, 1e-9)
  end)

  it("reads the current cast, latency and player stats", function()
    install({ known = { [top("lightningBolt")] = true }, casting = { name = "Lightning Bolt", startMs = 99500, endMs = 101000 },
              latencyMs = 80, ap = 3000, sp = { [3] = 500, [4] = 700 }, crit = 25, spellCrit = 15, ratings = { [6] = 3 }, hitMod = 2 })
    local S = snapshot.build(ctx())
    assert.are.near(1.0, S.castRemains, 1e-9)
    assert.are.near(0.18, S.latency, 1e-9)
    assert.are.equal(3000, S.player.ap)
    assert.are.equal(700, S.player.spNature)
    assert.are.equal(500, S.player.spFire)
    assert.are.near(0.25, S.player.meleeCrit, 1e-9)
    assert.are.near(0.05, S.player.meleeHit, 1e-9)
    assert.are.equal(4396, S.player.baseMana)
  end)

  it("turns in-flight deadlines into remains and drops expired ones", function()
    install({})
    local c = ctx({ inflight = { flameShock = 100.6, earthShock = 99.0 } })
    local S = snapshot.build(c)
    assert.are.near(0.6, S.inflight.flameShock, 1e-9)
    assert.is_nil(S.inflight.earthShock)
    assert.is_nil(c.inflight.earthShock)
  end)

  it("lets the runtime override the auto-attack flag and counts the target as an enemy", function()
    install({ known = { [top("stormstrike")] = true }, inRange = { Stormstrike = 1 } })
    local S = snapshot.build(ctx({ attacking = false }))
    assert.is_false(S.swing.attacking)
    assert.are.equal(1, S.enemies.melee)
    assert.are.equal(2, S.enemies.nearby)
  end)

  it("reuses the scan cache between builds", function()
    install({})
    local c = ctx()
    snapshot.build(c)
    local cache = c.cache
    snapshot.build(c)
    assert.are.equal(cache, c.cache)
  end)

  it("reads talents by name through the three talent functions", function()
    install({ talents = { [2] = { { "Flurry", 5 }, { "Maelstrom Weapon", 3 } } } })
    local S = snapshot.build(ctx())
    assert.are.equal(5, S.talents.flurry)
    assert.are.equal(3, S.talents.maelstromWeapon)
    assert.are.equal(0, S.talents.lavaLash)
  end)

  it("marks a slow weapon without an off-hand as two-handed, a one-hander with a shield is not", function()
    install({ speed = { 3.5, nil } })
    assert.is_true(snapshot.build(ctx()).weapons.mh.twoHand)
    install({ speed = { 2.6, nil } })
    assert.is_nil(snapshot.build(ctx()).weapons.mh.twoHand)
    install({ speed = { 2.6, 2.6 } })
    assert.is_nil(snapshot.build(ctx()).weapons.mh.twoHand)
  end)

  it("uses the item slot for two-handers when the client gives it", function()
    install({ speed = { 3.5, nil } })
    _G.GetInventoryItemLink = function() return "item:1" end
    _G.GetItemInfo = function() return "Mace", "item:1", 2, 80, 80, "Weapon", "One-Handed Maces", 1, "INVTYPE_WEAPONMAINHAND" end
    local S = snapshot.build(ctx())
    _G.GetInventoryItemLink, _G.GetItemInfo = nil, nil
    assert.is_nil(S.weapons.mh.twoHand)
  end)

  it("turns the wolves deadline into remains", function()
    install({})
    assert.are.equal(0, snapshot.build(ctx()).pets.wolves)
    assert.are.near(30, snapshot.build(ctx({ wolvesUntil = 130 })).pets.wolves, 1e-9)
  end)
end)
