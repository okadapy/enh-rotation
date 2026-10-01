local raid = require("raid")

local function on(count) return { count = count or 0, remains = 20 } end

describe("raid", function()
  it("nothing found: no S.mods (the engine runs as without the addon)", function()
    assert.is_nil(raid.effects(nil, nil, nil, nil))
    assert.is_nil(raid.effects({}, {}, {}, nil))
    assert.is_nil(raid.effects({ unknown = on() }, { other = on() }, { earth = "other", air = "other" }, nil))
  end)

  -- wowsims FullDebuffs (sim/core/test_utils.go), the raid of their enhancement tests
  it("the wowsims full raid", function()
    local m = raid.effects({ sunder = on(5), expose = on(), faerieFire = on(), elements = on(), ebonPlague = on(),
                             earthAndMoon = on(), totemOfWrath = on(), heartOfTheCrusader = on(), bloodFrenzy = on(),
                             improvedScorch = on(), shadowMastery = on(), misery = on() }, {}, {}, nil)
    assert.are.near(0.8 * 0.95, m.armor, 1e-12)
    assert.are.near(1.13, m.spellTaken, 1e-12)
    assert.are.near(1.04, m.physTaken, 1e-12)
    assert.are.near(0.03, m.critTaken, 1e-12)
    assert.are.near(0.05, m.spellCritTaken, 1e-12)
    assert.are.near(0.03, m.spellHitTaken, 1e-12)
    assert.is_nil(m.support)
  end)

  it("Sunder Armor counts per stack up to 5; a debuff without a count is one stack", function()
    assert.are.near(1 - 0.12, raid.effects({ sunder = on(3) }).armor, 1e-12)
    assert.are.near(0.8, raid.effects({ sunder = on(9) }).armor, 1e-12)
    assert.are.near(0.96, raid.effects({ sunder = on(0) }).armor, 1e-12)
    assert.are.near(0.9, raid.effects({ acidSpit = on(1) }).armor, 1e-12)
  end)

  it("within a category the strongest only; categories multiply", function()
    assert.are.near(0.8, raid.effects({ sunder = on(2), expose = on() }).armor, 1e-12)
    assert.are.near(0.95, raid.effects({ sting = on(), faerieFire = on(), sporeCloud = on() }).armor, 1e-12)
    assert.are.near(0.92 * 0.95, raid.effects({ sunder = on(2), curseOfWeakness = on() }).armor, 1e-12)
    assert.are.near(0.03, raid.effects({ wintersChill = on(3) }).spellCritTaken, 1e-12)
    assert.are.near(0.05, raid.effects({ wintersChill = on(3), improvedScorch = on() }).spellCritTaken, 1e-12)
    assert.are.near(1.13, raid.effects({ elements = on(), ebonPlague = on(), earthAndMoon = on() }).spellTaken, 1e-12)
  end)

  it("support: Horn of Winter covers Strength of Earth, Improved Icy Talons covers Windfury Totem", function()
    assert.are.near(raid.SUPPORT.haste, raid.effects({}, { hornOfWinter = on() }, {}).support, 1e-12)
    assert.are.near(raid.SUPPORT.strength, raid.effects({}, { icyTalons = on() }, {}).support, 1e-12)
    assert.are.equal(0, raid.effects({}, { hornOfWinter = on(), icyTalons = on() }, {}).support)
  end)

  -- the buff of our own totem is on us too: someone else's counts only while ours is not the one up
  it("another shaman's totem covers ours only while ours of that element is not up", function()
    assert.is_nil(raid.effects({}, { windfuryTotem = on() }, { air = "haste" }))
    assert.are.near(raid.SUPPORT.strength, raid.effects({}, { windfuryTotem = on() }, { air = "other" }).support, 1e-12)
    assert.are.near(raid.SUPPORT.strength, raid.effects({}, { windfuryTotem = on() }, {}).support, 1e-12)
    assert.is_nil(raid.effects({}, { strengthOfEarth = on() }, { earth = "strength" }))
    assert.are.near(raid.SUPPORT.haste, raid.effects({}, { strengthOfEarth = on() }, { earth = "other" }).support, 1e-12)
  end)

  it("the gear's mods are carried over, alone or with the debuffs", function()
    assert.are.same({ ssFlat = 155 }, raid.effects({}, {}, {}, { ssFlat = 155 }))
    local m = raid.effects({ elements = on() }, {}, {}, { ssFlat = 155 })
    assert.are.equal(155, m.ssFlat)
    assert.are.near(1.13, m.spellTaken, 1e-12)
  end)

  it("every debuff id has an effect and every effect an id; the support split adds up to value.SUPPORT", function()
    local keys = {}
    for id, key in pairs(raid.DEBUFFS) do
      assert.is_number(id)
      assert.is_table(raid.EFFECT[key], key)
      keys[key] = true
    end
    for key in pairs(raid.EFFECT) do assert.is_true(keys[key] == true, key) end
    assert.are.near(require("value").SUPPORT, raid.SUPPORT.haste + raid.SUPPORT.strength, 1e-12)
  end)

  -- snapshot and the game mock look these ids up by name: they are a shared interface
  it("the ids are those agreed with snapshot and the game mock", function()
    assert.are.same({
      [7386] = "sunder", [8647] = "expose", [55749] = "acidSpit",
      [770] = "faerieFire", [16857] = "faerieFireFeral", [56631] = "sting", [702] = "curseOfWeakness",
      [53598] = "sporeCloud",
      [1490] = "elements", [51726] = "ebonPlague", [60431] = "earthAndMoon",
      [30708] = "totemOfWrath", [21183] = "heartOfTheCrusader", [58410] = "masterPoisoner",
      [30069] = "bloodFrenzy", [58683] = "savageCombat",
      [22959] = "improvedScorch", [12579] = "wintersChill", [17800] = "shadowMastery",
      [33198] = "misery",
    }, raid.DEBUFFS)
    assert.are.same({ [57330] = "hornOfWinter", [8076] = "strengthOfEarth", [8512] = "windfuryTotem",
                      [55610] = "icyTalons" }, raid.BUFFS)
    assert.are.same({ [8075] = "strength", [8512] = "haste" }, raid.OWN_TOTEMS)
    assert.are.same({ haste = 0.04, strength = 0.02 }, raid.SUPPORT)
  end)
end)
