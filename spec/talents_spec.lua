local W = require("wow_mock")
local talents = require("talents")

describe("talents", function()
  it("reads ranks by talent name from any tab and position", function()
    W.install({ talents = {
      [1] = { { name = "Convection", rank = 5 }, { name = "Concussion", rank = 5 }, { name = "Call of Flame", rank = 3 } },
      [2] = { { name = "Ancestral Knowledge", rank = 2 }, { name = "Maelstrom Weapon", rank = 5 }, { name = "Flurry", rank = 5 } },
      [3] = { { name = "Improved Healing Wave", rank = 5 } },
    } })
    local t = talents.read(GetNumTalentTabs, GetNumTalents, GetTalentInfo)
    assert.are.equal(5, t.concussion)
    assert.are.equal(3, t.callOfFlame)
    assert.are.equal(5, t.maelstromWeapon)
    assert.are.equal(5, t.flurry)
    assert.are.equal(0, t.stormstrike)
    assert.is_nil(t.improvedHealingWave)
  end)

  it("returns zero for every known key when nothing is learned", function()
    W.install({ talents = {} })
    local t = talents.read(GetNumTalentTabs, GetNumTalents, GetTalentInfo)
    for _, k in ipairs(talents.KEYS) do assert.are.equal(0, t[k.key], k.key) end
  end)

  it("exposes every key the damage model reads", function()
    local keys = {}
    for _, k in ipairs(talents.KEYS) do keys[k.key] = true end
    for _, k in ipairs({ "concussion", "callOfFlame", "elementalFury", "reverberation", "improvedFireNova",
                         "improvedShields", "elementalWeapons", "staticShock", "maelstromWeapon",
                         "dualWieldSpecialization" }) do
      assert.is_true(keys[k], k)
    end
  end)

  it("has unique keys and names", function()
    local keys, names = {}, {}
    for _, k in ipairs(talents.KEYS) do
      assert.is_nil(keys[k.key], k.key); keys[k.key] = true
      assert.is_nil(names[k.name], k.name); names[k.name] = true
    end
  end)
end)
