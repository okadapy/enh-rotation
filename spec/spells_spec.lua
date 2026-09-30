local spells = require("spells")

describe("spells catalog", function()
  it("contains exactly the 15 contract action keys", function()
    local expected = { "stormstrike", "lavaLash", "earthShock", "flameShock", "frostShock", "lightningBolt",
      "chainLightning", "searingTotem", "magmaTotem", "fireNova", "fireElemental", "callOfElements",
      "lightningShield", "shamanisticRage", "feralSpirit" }
    assert.are.equal(#expected, #spells.CATALOG)
    for _, k in ipairs(expected) do assert.is_not_nil(spells.byKey[k], k) end
    assert.are.same(expected, spells.KEYS)
  end)

  it("builds rank id lists from generated data", function()
    local lb = spells.byKey.lightningBolt
    assert.are.equal(403, lb.ranks[1])
    assert.are.equal(49238, lb.ranks[#lb.ranks])
    assert.are.equal(49238, spells.rank("lightningBolt", 49238).id)
    assert.is_nil(spells.rank("lightningBolt", 12345))
  end)

  it("marks shocks as sharing one cooldown and weapon strikes by hand", function()
    for _, k in ipairs({ "earthShock", "flameShock", "frostShock" }) do
      assert.are.equal("shock", spells.byKey[k].sharedCd, k)
      assert.are.equal(6, spells.byKey[k].cd, k)
    end
    assert.are.equal("both", spells.byKey.stormstrike.hands)
    assert.are.equal("oh", spells.byKey.lavaLash.hands)
    assert.is_true(spells.byKey.stormstrike.weapon)
    assert.is_nil(spells.byKey.earthShock.weapon)
  end)

  it("takes gcd and cooldown from the client data", function()
    assert.are.equal(1.0, spells.byKey.magmaTotem.gcd)
    assert.are.equal(1.0, spells.byKey.searingTotem.gcd)
    assert.are.equal(1.5, spells.byKey.shamanisticRage.gcd)
    assert.are.equal(8, spells.byKey.stormstrike.cd)
    assert.are.equal(10, spells.byKey.fireNova.cd)
    assert.are.equal(0, spells.byKey.lightningBolt.cd)
    assert.are.equal(2.5, spells.byKey.lightningBolt.castBase)
    assert.are.equal(2.0, spells.byKey.chainLightning.castBase)
  end)

  it("describes totems, dots and shields for the model", function()
    assert.are.equal("fire", spells.byKey.magmaTotem.totem)
    assert.are.same({ 20, 2 }, { spells.byKey.magmaTotem.duration, spells.byKey.magmaTotem.period })
    assert.are.same({ 18, 3 }, { spells.byKey.flameShock.duration, spells.byKey.flameShock.period })
    local fsTop = spells.rank("flameShock", 49233)
    assert.are.equal(spells.byKey.flameShock.duration, fsTop.ticks * fsTop.period)
    assert.are.same({ 12, 4, 20 }, { spells.byKey.stormstrike.duration, spells.byKey.stormstrike.charges, spells.byKey.stormstrike.bonus })
    assert.are.equal(3, spells.byKey.lightningShield.charges)
    assert.is_true(spells.byKey.fireNova.requiresFireTotem)
    assert.are.equal(3, spells.byKey.chainLightning.maxTargets)
  end)

  it("uses 3.3.5 icon paths only", function()
    for _, s in ipairs(spells.CATALOG) do
      assert.is_truthy(s.icon:match("^Interface\\Icons\\[%w_]+$"), s.key)
    end
  end)
end)
