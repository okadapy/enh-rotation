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

  it("tells which shield is on the player and passes the shield option on", function()
    install({ auras = { player = { HELPFUL = { { name = "Water Shield", count = 3, expires = 700 } } } } })
    local S = snapshot.build(ctx({ shield = "water" }))
    assert.are.equal("water", S.player.shield)
    assert.are.equal(3, S.buffs.ws.charges)
    assert.are.near(600, S.buffs.ws.remains, 1e-9)
    assert.are.equal(0, S.buffs.ls.charges)
    assert.are.equal("water", S.shieldPref)
    install({ auras = { player = { HELPFUL = { { name = "Lightning Shield", count = 3, expires = 700 } } } } })
    S = snapshot.build(ctx())
    assert.are.equal("lightning", S.player.shield)
    assert.is_nil(S.buffs.ws)
    assert.are.equal("auto", S.shieldPref)
    install({})
    S = snapshot.build(ctx({ shield = "bogus" }))
    assert.is_nil(S.player.shield)
    assert.are.equal("auto", S.shieldPref)
  end)

  it("reads weapon imbues from the weapon tooltip", function()
    install({ enchants = { mh = true, oh = true },
              tooltip = { [16] = { "Some Axe", "Windfury 8 (30 min)" }, [17] = { "Other Axe", "Flametongue 10 (30 min)" } } })
    local S = snapshot.build(ctx())
    assert.are.equal("wf", S.weapons.mh.enchant)
    assert.are.equal("ft", S.weapons.oh.enchant)
  end)

  it("reads the weapon's own speed from the tooltip, the swing interval stays hasted", function()
    install({ speed = { 1.73, 1.73 }, enchants = { mh = true, oh = true },
              tooltip = { [16] = { "Some Axe", "209 - 273 Damage", "Speed 2.70", "Windfury 8 (30 min)" },
                          [17] = { "Other Axe", "Скорость 2,60", "Flametongue 10 (30 min)" } } })
    local S = snapshot.build(ctx())
    assert.are.equal(1.73, S.weapons.mh.speed)
    assert.are.equal(2.7, S.weapons.mh.base)
    assert.are.equal(2.6, S.weapons.oh.base)
    install({ speed = { 1.73, 1.73 }, enchants = {} })
    S = snapshot.build(ctx())
    assert.is_nil(S.weapons.mh.base)
  end)

  it("a weapon swap rereads the speed at once, with the same imbues", function()
    install({ speed = { 1.73, 1.73 }, enchants = { mh = true, oh = true }, links = { [16] = "axe:1", [17] = "axe:2" },
              tooltip = { [16] = { "Some Axe", "Speed 2.70" }, [17] = { "Other Axe", "Speed 2.60" } } })
    local c = ctx()
    assert.are.equal(2.7, snapshot.build(c).weapons.mh.base)
    install({ speed = { 1.73, 1.73 }, enchants = { mh = true, oh = true }, links = { [16] = "sword:3", [17] = "axe:2" },
              tooltip = { [16] = { "Fast Sword", "Speed 1.80" }, [17] = { "Other Axe", "Speed 2.60" } } })
    assert.are.equal(1.8, snapshot.build(c).weapons.mh.base)
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

  it("marks a boss (world boss or level ??) and copies the player's cooldown options", function()
    install({ target = { level = 80, hp = 5000, hpMax = 10000 } })
    local S = snapshot.build(ctx())
    assert.is_false(S.target.isBoss)
    assert.is_nil(S.cooldowns)
    install({ target = { level = -1, hp = 5000, hpMax = 10000 } })
    assert.is_true(snapshot.build(ctx()).target.isBoss)
    install({ target = { level = 83, hp = 5000, hpMax = 10000, classification = "worldboss" } })
    assert.is_true(snapshot.build(ctx()).target.isBoss)
    install({ target = { level = 82, hp = 5000, hpMax = 10000, classification = "elite" } })
    assert.is_false(snapshot.build(ctx()).target.isBoss)
    install({})
    local cds = { feralSpirit = "auto", fireElemental = "boss", shamanisticRage = "always" }
    assert.are.equal(cds, snapshot.build(ctx({ cooldowns = cds })).cooldowns)
    -- the weaving option: nil without it (the model decides, as before the option)
    assert.is_nil(snapshot.build(ctx()).weaveMin)
    assert.are.equal(5, snapshot.build(ctx({ weaveMin = 5 })).weaveMin)
    -- the solo mana option: nil without it (value: balanced)
    assert.is_nil(snapshot.build(ctx()).manaPolicy)
    assert.are.equal("spend", snapshot.build(ctx({ manaPolicy = "spend" })).manaPolicy)
  end)

  it("decides the long cooldowns' gate once per snapshot (S.cdAllowed), latched per target", function()
    local cds = { feralSpirit = "auto", fireElemental = "never", shamanisticRage = "always" }
    local ttd = 42
    local c = ctx({ cooldowns = cds, ttd = { add = function() end, smoothed = function() return ttd end } })
    install({ target = { level = 80, hp = 5000, hpMax = 10000, guid = "Creature-7" } })
    assert.is_nil(snapshot.build(ctx()).cdAllowed) -- no options: nothing decided (model decides as before)
    local S = snapshot.build(c)
    assert.are.same({ feralSpirit = true, fireElemental = false, shamanisticRage = true }, S.cdAllowed)
    assert.are.equal("Creature-7", c.cdLatch[1].guid)
    ttd = 20 -- below 22.5, above 22.5 x 0.75: the latch holds
    assert.is_true(snapshot.build(c).cdAllowed.feralSpirit)
    ttd = 16 -- below 16.875: released
    assert.is_false(snapshot.build(c).cdAllowed.feralSpirit)
    ttd = 20 -- released: back to the plain line
    assert.is_false(snapshot.build(c).cdAllowed.feralSpirit)
    ttd = 23
    assert.is_true(snapshot.build(c).cdAllowed.feralSpirit)
    -- another target: a fresh latch, the first one kept
    install({ target = { level = 80, hp = 5000, hpMax = 10000, guid = "Creature-8" } })
    ttd = 20
    assert.is_false(snapshot.build(c).cdAllowed.feralSpirit)
    assert.are.equal("Creature-8", c.cdLatch[1].guid)
    assert.are.equal("Creature-7", c.cdLatch[2].guid)
    install({ target = { level = 80, hp = 5000, hpMax = 10000, guid = "Creature-7" } })
    assert.is_true(snapshot.build(c).cdAllowed.feralSpirit)
  end)

  it("cooldownGate: latch per GUID, cleared without options", function()
    local model = require("model")
    local need = model.COOLDOWN_TTD.feralSpirit
    local function S(ttd, boss)
      return { cooldowns = { feralSpirit = "auto", fireElemental = "boss" }, target = { ttd = ttd, isBoss = boss } }
    end
    local c = {}
    assert.are.same({ feralSpirit = false, fireElemental = false, shamanisticRage = true }, snapshot.cooldownGate(c, S(need - 1), "A"))
    assert.is_true(snapshot.cooldownGate(c, S(need), "A").feralSpirit)
    for _, t in ipairs({ 24, 21, 23, 22, 25, 21, 17 }) do
      assert.is_true(snapshot.cooldownGate(c, S(t), "A").feralSpirit, "ttd " .. t)
    end
    assert.is_true(snapshot.cooldownGate(c, S(nil), "A").feralSpirit) -- unknown ttd does not release
    assert.is_false(snapshot.cooldownGate(c, S(need * 0.75 - 0.01), "A").feralSpirit)
    assert.is_false(snapshot.cooldownGate(c, S(21), "A").feralSpirit)
    assert.is_true(snapshot.cooldownGate(c, S(30), "A").feralSpirit)
    assert.is_false(snapshot.cooldownGate(c, S(21), "B").feralSpirit) -- new target: no latch
    snapshot.cooldownGate(c, S(30), "B")
    assert.is_nil(snapshot.cooldownGate(c, { target = { ttd = 30 } }, "B"))
    assert.is_nil(c.cdLatch)
    assert.is_false(snapshot.cooldownGate(c, S(21), "B").feralSpirit)
    assert.is_false(snapshot.cooldownGate(c, S(21), "A").feralSpirit) -- no options dropped A's too
    -- no target (nil GUID): nothing latches
    snapshot.cooldownGate(c, S(30), nil)
    assert.is_false(snapshot.cooldownGate(c, S(21), nil).feralSpirit)
    -- a boss: allowed whatever the ttd, "boss" too
    local b = snapshot.cooldownGate(c, S(1, true), "Boss")
    assert.is_true(b.feralSpirit)
    assert.is_true(b.fireElemental)
  end)

  it("cooldownGate: latches for the last LATCH_TARGETS GUIDs", function()
    assert.are.equal(3, snapshot.LATCH_TARGETS)
    local need = require("model").COOLDOWN_TTD.feralSpirit
    local function S(ttd) return { cooldowns = { feralSpirit = "auto" }, target = { ttd = ttd } } end
    local function gate(c, ttd, guid) return snapshot.cooldownGate(c, S(ttd), guid).feralSpirit end
    local low = need * 0.75 + 0.5 -- below the line, above the release
    -- A -> B -> A: A keeps its latch (the review's case: 30, 15, 21)
    local c = {}
    assert.is_true(gate(c, 30, "A"))
    assert.is_false(gate(c, 15, "B"))
    assert.is_true(gate(c, 21, "A"))
    assert.is_false(gate(c, 21, "B"))
    -- no target in between: nothing latched, nothing dropped
    assert.is_true(gate(c, 30, nil))
    assert.is_false(gate(c, low, nil))
    assert.are.equal(2, #c.cdLatch)
    assert.is_true(gate(c, low, "A"))
    -- the same GUID again reuses its slot: no new table
    local slot = c.cdLatch[1]
    gate(c, low, "A")
    assert.are.equal(slot, c.cdLatch[1])
    assert.are.equal(2, #c.cdLatch)
    -- a 4th GUID drops the least recently seen
    c = {}
    for _, g in ipairs({ "A", "B", "C" }) do assert.is_true(gate(c, 30, g)) end
    assert.is_true(gate(c, low, "A")) -- A seen last: B is now the oldest
    assert.is_true(gate(c, 30, "D"))
    assert.are.equal(3, #c.cdLatch)
    assert.are.same({ "D", "A", "C" }, { c.cdLatch[1].guid, c.cdLatch[2].guid, c.cdLatch[3].guid })
    assert.is_false(gate(c, low, "B")) -- B evicted: back to the plain line (and B pushes C out)
    assert.are.same({ "B", "D", "A" }, { c.cdLatch[1].guid, c.cdLatch[2].guid, c.cdLatch[3].guid })
    assert.is_true(gate(c, low, "D"))
    assert.is_true(gate(c, low, "A"))
    assert.is_false(gate(c, low, "C"))
    -- release per GUID: A released, D untouched
    assert.is_false(gate(c, need * 0.75 - 0.01, "A"))
    assert.is_false(gate(c, low, "A"))
    assert.is_true(gate(c, low, "D"))
    -- no options: all cleared
    assert.is_nil(snapshot.cooldownGate(c, { target = { ttd = 30 } }, "D"))
    assert.is_nil(c.cdLatch)
    assert.is_false(gate(c, low, "D"))
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

  describe("a mob running in", function()
    local known = { [top("stormstrike")] = true, [top("earthShock")] = true, [top("lightningBolt")] = true }
    local TWENTY = { Stormstrike = 0, ["Earth Shock"] = 1, ["Lightning Bolt"] = 1 }
    local THIRTY = { Stormstrike = 0, ["Earth Shock"] = 0, ["Lightning Bolt"] = 1 }
    local function target(extra)
      local t = { level = 54, hp = 3000, hpMax = 3000, guid = "Creature-9" }
      for k, v in pairs(extra or {}) do t[k] = v end
      return t
    end

    it("a mob fighting us at 20 or 30 yards is in melee in distance / 7 yd/s", function()
      install({ known = known, inRange = TWENTY, target = target({ inCombat = true }) })
      local t = snapshot.build(ctx()).target
      assert.is_true(t.inCombat)
      assert.is_false(t.isPlayer)
      assert.are.near(20 / 7, t.meleeIn, 1e-9)
      install({ known = known, inRange = THIRTY, target = target({ inCombat = true }) })
      assert.are.near(30 / 7, snapshot.build(ctx()).target.meleeIn, 1e-9)
    end)

    it("our Flame Shock on it counts as fighting us", function()
      install({ known = known, inRange = TWENTY, inCombat = false, target = target({ inCombat = false }),
                auras = { target = { HARMFUL = { { name = "Flame Shock", expires = 109, caster = "player" } } } } })
      local t = snapshot.build(ctx()).target
      assert.is_true(t.inCombat)
      assert.are.near(20 / 7, t.meleeIn, 1e-9)
    end)

    it("stays put: out of combat, a player, in a group, in melee or far away", function()
      install({ known = known, inRange = TWENTY, target = target({ inCombat = false }) })
      local t = snapshot.build(ctx()).target
      assert.is_false(t.inCombat)
      assert.is_nil(t.meleeIn)
      -- the mob fights someone else while we are out of combat
      install({ known = known, inRange = TWENTY, inCombat = false, target = target({ inCombat = true }) })
      assert.is_nil(snapshot.build(ctx()).target.meleeIn)
      install({ known = known, inRange = TWENTY, target = target({ inCombat = true, player = true }) })
      t = snapshot.build(ctx()).target
      assert.is_true(t.isPlayer)
      assert.is_nil(t.meleeIn)
      install({ known = known, inRange = TWENTY, party = 2, target = target({ inCombat = true }) })
      assert.is_nil(snapshot.build(ctx()).target.meleeIn)
      install({ known = known, inRange = { Stormstrike = 1 }, target = target({ inCombat = true }) })
      assert.is_nil(snapshot.build(ctx()).target.meleeIn)
      install({ known = known, inRange = { Stormstrike = 0, ["Earth Shock"] = 0, ["Lightning Bolt"] = 0 }, target = target({ inCombat = true }) })
      assert.is_nil(snapshot.build(ctx()).target.meleeIn)
    end)
  end)

  describe("range hysteresis", function()
    local known = { [top("stormstrike")] = true, [top("earthShock")] = true, [top("lightningBolt")] = true }
    local MELEE = { Stormstrike = 1, ["Earth Shock"] = 1, ["Lightning Bolt"] = 1 }
    local TWENTY = { Stormstrike = 0, ["Earth Shock"] = 1, ["Lightning Bolt"] = 1 }
    local FAR = { Stormstrike = 0, ["Earth Shock"] = 0, ["Lightning Bolt"] = 0 }
    local cfg, c
    local function at(now, inRange, guid)
      cfg.now, cfg.inRange = now, inRange
      if guid then cfg.target.guid = guid end
      return snapshot.build(c).target.range
    end
    before_each(function()
      cfg = install({ known = known, inRange = MELEE })
      c = ctx()
    end)

    it("a short melee -> 20 -> melee flicker stays melee", function()
      assert.are.equal("melee", at(100.0, MELEE))
      assert.are.equal("melee", at(100.1, TWENTY))
      assert.are.equal("melee", at(100.3, TWENTY))
      assert.are.equal("melee", at(100.4, MELEE))
      -- the hold starts over after a melee reading
      assert.are.equal("melee", at(100.5, TWENTY))
      assert.are.equal("melee", at(100.8, FAR))
    end)

    it("leaves melee once a non-melee reading has lasted RANGE_HOLD", function()
      assert.are.equal("melee", at(100.0, MELEE))
      assert.are.equal("melee", at(100.1, TWENTY))
      assert.are.equal("20", at(100.11 + snapshot.RANGE_HOLD, TWENTY))
      assert.are.equal("far", at(100.6, FAR))
      assert.are.equal("20", at(100.7, TWENTY))
      -- getting closer is instant
      assert.are.equal("melee", at(100.8, MELEE))
    end)

    it("a new target takes its first reading at once", function()
      assert.are.equal("melee", at(100.0, MELEE, "Creature-7"))
      assert.are.equal("far", at(100.1, FAR, "Creature-8"))
      assert.are.equal("melee", at(100.2, MELEE, "Creature-9"))
      assert.are.equal("20", at(100.3, TWENTY, "Creature-7"))
    end)

    it("counts the held melee target as a melee enemy", function()
      at(100.0, MELEE)
      cfg.now, cfg.inRange = 100.2, TWENTY
      assert.are.equal(1, snapshot.build(c).enemies.melee)
    end)
  end)

  describe("movement hysteresis", function()
    local cfg, c
    local function at(now, moving)
      cfg.now, cfg.moving = now, moving
      return snapshot.build(c).player.moving
    end
    before_each(function()
      cfg = install({})
      c = ctx()
    end)

    it("a short shuffle is not movement", function()
      assert.is_false(at(100.0, false))
      assert.is_false(at(100.1, true))
      assert.is_false(at(100.3, true))
      assert.is_false(at(100.35, false))
      assert.is_false(at(100.5, true))
      assert.is_false(at(100.7, true))
    end)

    it("reports movement after MOVE_HOLD of continuous movement and stops at once", function()
      assert.is_false(at(100.0, true))
      assert.is_false(at(100.2, true))
      assert.is_true(at(100.01 + snapshot.MOVE_HOLD, true))
      assert.is_true(at(101.0, true))
      assert.is_false(at(101.1, false))
    end)
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

  describe("time-to-die prior", function()
    local value = require("value")
    local damage = require("damage")
    local realCombat

    -- a stub ttd that records the prior snapshot passes
    local function seen()
      local rec = {}
      rec.ttd = { add = function() end,
                  smoothed = function(_, _, _, prior) rec.prior = prior; return 42, prior and "blend" or "regression" end }
      return rec
    end
    local function mob(extra)
      local cfg = { level = 53, target = { level = 52, hp = 2437, hpMax = 2769, guid = "Creature-8" } }
      for k, v in pairs(extra or {}) do cfg[k] = v end
      install(cfg)
      realCombat = _G.UnitAffectingCombat
    end
    local function targetCombat(on)
      _G.UnitAffectingCombat = function(u)
        if u == "target" then return on and 1 or nil end
        return realCombat(u)
      end
    end

    it("solo, fighting us: our health / damage per second goes to ttd", function()
      mob()
      local rec = seen()
      local S = snapshot.build(ctx({ ttd = rec.ttd }))
      assert.are.near(S.target.hp / value.dpsEstimate(S), rec.prior, 1e-9)
      assert.are.equal(42, S.target.ttd)
      assert.are.equal("blend", S.target.ttdSource)
    end)

    it("counts the Flame Shock and fire totem already on the mob", function()
      mob({ auras = { target = { HARMFUL = { { name = "Flame Shock", expires = 115, caster = "player" } } } },
            totems = { [1] = { "Searing Totem VII", 95, 60 } },
            known = { [ranks("flameShock")[5]] = true, [ranks("searingTotem")[6]] = true } })
      local rec = seen()
      local S = snapshot.build(ctx({ ttd = rec.ttd }))
      local r = damage.rates(S)
      local dps = value.dpsEstimate(S) + r.flameShock + r.searingTotem
      assert.is_true(r.flameShock > 0 and r.searingTotem > 0)
      assert.are.near(S.target.hp / dps, rec.prior, 1e-9)
    end)

    it("none in a group or raid: others hit the mob too", function()
      for _, extra in ipairs({ { party = 2 }, { raid = 10 } }) do
        mob(extra)
        local rec = seen()
        snapshot.build(ctx({ ttd = rec.ttd }))
        assert.is_nil(rec.prior)
      end
    end)

    it("none before the pull", function()
      mob({ inCombat = false })
      local rec = seen()
      snapshot.build(ctx({ ttd = rec.ttd }))
      assert.is_nil(rec.prior)
    end)

    it("none while the mob is not fighting, unless our Flame Shock is on it", function()
      mob()
      targetCombat(false)
      local rec = seen()
      snapshot.build(ctx({ ttd = rec.ttd }))
      assert.is_nil(rec.prior)
      mob({ auras = { target = { HARMFUL = { { name = "Flame Shock", expires = 115, caster = "player" } } } } })
      targetCombat(false)
      rec = seen()
      snapshot.build(ctx({ ttd = rec.ttd }))
      assert.is_not_nil(rec.prior)
      _G.UnitAffectingCombat = realCombat
    end)

    it("S.target.inCombat, when the snapshot has it, decides", function()
      mob()
      local S = snapshot.build(ctx())
      assert.is_not_nil(snapshot.ttdPrior(S))
      S.target.inCombat = false
      assert.is_nil(snapshot.ttdPrior(S))
    end)

    -- recorded: the first snapshot of a fight said 128 s at 88%; the mob died about 6 s later
    it("with the real estimator the first snapshot in a fight has a finite ttd", function()
      local ttd = require("ttd")
      mob({ now = 100 })
      local c = ctx({ ttd = ttd.new() })
      local S = snapshot.build(c)
      assert.are.equal("prior", S.target.ttdSource)
      assert.is_true(S.target.ttd > 0 and S.target.ttd < 30, tostring(S.target.ttd))
      -- a whole percent in 2 s: the regression alone would say minutes, the estimate stays near the prior
      G.cfg.target.hp, G.cfg.now = 2437 - 28, 101
      snapshot.build(c)
      G.cfg.target.hp, G.cfg.now = 2437 - 28, 102
      S = snapshot.build(c)
      assert.are.equal("blend", S.target.ttdSource)
      assert.is_true(c.ttd:estimate(102, "Creature-8") > 100)
      assert.is_true(S.target.ttd < 30, tostring(S.target.ttd))
    end)
  end)
end)
