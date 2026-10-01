local gear = require("gear")
local data = require("gear_data")

describe("gear", function()
  it("nothing the model knows: no mods", function()
    assert.is_nil(gear.effects({}, {}))
    assert.is_nil(gear.effects(nil, nil))
    assert.is_nil(gear.effects({ 12345, 40322 }, { 99999 })) -- Totem of Dueling: a proc, not a constant (task 10)
  end)

  it("relics with a constant bonus", function()
    assert.are.same({ ssFlat = 155 }, gear.effects({ 45169 }, {}))
    assert.are.same({ wfAp = 212 }, gear.effects({ 40710 }, {}))
    assert.are.same({ wfAp = 80 }, gear.effects({ 27815 }, {}))
    assert.are.same({ llFlat = 25 }, gear.effects({ 38367 }, {}))
  end)

  it("set bonuses count the pieces of one set across its 10 / 25 and item level versions", function()
    assert.is_nil(gear.effects({ 45412 }, {}))
    assert.are.same({ ssMult = 0.20, llMult = 0.20 }, gear.effects({ 45412, 46200 }, {}))
    assert.are.same({ ssMult = 0.20, llMult = 0.20, mwPpm = 0.20 }, gear.effects({ 45412, 45413, 46203, 46205 }, {}))
  end)

  it("T9: Thrall's (Horde) and Nobundo's (Alliance) pieces are one set", function()
    assert.are.same({ staticChance = 0.03 }, gear.effects({ 48356, 48341 }, {}))
    assert.are.same({ staticChance = 0.03, shockMult = 0.25 }, gear.effects({ 48356, 48357, 48342, 48343 }, {}))
  end)

  it("T7 2 and T10 give what the model counts: Lightning Shield +10%; T10 nothing (no wowsims reference)", function()
    assert.are.same({ lsMult = 0.10 }, gear.effects({ 39597, 40520 }, {}))
    assert.is_nil(gear.effects({ 50830, 50831, 51195, 51240 }, {}))
  end)

  it("the same mod from two sources adds up: T7 2 + Glyph of Lightning Shield = +30%", function()
    assert.are.near(0.30, gear.effects({ 39597, 39601 }, { 55448 }).lsMult, 1e-12)
  end)

  it("glyphs by the spell GetGlyphSocketInfo gives", function()
    assert.are.same({ ssNature = 0.08 }, gear.effects({}, { 55446 }))
    assert.are.same({ llFt = 0.10 }, gear.effects({}, { 55444 }))
    assert.are.same({ wolvesAp = 0.30, clTargets = 1 }, gear.effects({}, { 63271, 55449 }))
    assert.are.same({ fireNovaCd = 3 }, gear.effects({}, { 55450 }))
    assert.are.same({ lbMult = 0.04, fsCrit = 0.60, wfChance = 0.02, shockGcd = 1 },
      gear.effects({}, { 55453, 55447, 55445, 55442 }))
  end)

  it("relic, set and glyphs together", function()
    assert.are.same({ ssFlat = 155, ssMult = 0.20, llMult = 0.20, ssNature = 0.08 },
      gear.effects({ 45169, 45412, 45414 }, { 55446 }))
  end)

  it("every set has distinct pieces; every bonus names a known set", function()
    local seen = {}
    for set, ids in pairs(data.SETS) do
      assert.is_true(#ids == 10 or #ids == 15 or #ids == 30, set)
      for _, id in ipairs(ids) do
        assert.is_nil(seen[id], tostring(id))
        seen[id] = set
      end
    end
    for _, b in ipairs(data.BONUS) do assert.is_table(data.SETS[b[1]], b[1]) end
  end)

  it("set sizes as in wowsims db.json: T7 and T8 10, T9 30 (both factions), T10 15", function()
    assert.are.equal(10, #data.SETS.t7)
    assert.are.equal(10, #data.SETS.t8)
    assert.are.equal(30, #data.SETS.t9)
    assert.are.equal(15, #data.SETS.t10)
  end)
end)
