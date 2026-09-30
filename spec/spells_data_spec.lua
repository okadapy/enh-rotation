local data = require("spells_data")

local function byId(key, id)
  for _, r in ipairs(data[key]) do if r.id == id then return r end end
  return nil
end

describe("spells_data (generated from client Spell.dbc)", function()
  it("has Lightning Bolt ranks 1 and 14 with real numbers", function()
    local r1 = byId("lightningBolt", 403)
    assert.are.same({ 1, 1500, 13, 15, 0.125 }, { r1.level, r1.castMs, r1.min, r1.max, r1.coef })
    local r14 = byId("lightningBolt", 49238)
    assert.are.same({ 79, 2500, 715, 815, 0.714, 1500 }, { r14.level, r14.castMs, r14.min, r14.max, r14.coef, r14.gcdMs })
    assert.are.equal(14, #data.lightningBolt)
  end)

  it("has shocks with the shared 6 s category cooldown", function()
    local es = byId("earthShock", 49231)
    assert.are.same({ 79, 849, 895, 0.386, 6000 }, { es.level, es.min, es.max, es.coef, es.cdMs })
    local fs = byId("flameShock", 49233)
    -- DurationIndex 85 = 18 s: 6 ticks of 139 every 3 s (834 over 18 sec, as in the 3.3.5 tooltip)
    assert.are.same({ 80, 500, 500, 0.214, 139, 0.1, 6, 3 },
      { fs.level, fs.min, fs.max, fs.coef, fs.tick, fs.tickCoef, fs.ticks, fs.period })
    local frs = byId("frostShock", 49236)
    assert.are.same({ 78, 802, 848 }, { frs.level, frs.min, frs.max })
  end)

  it("takes totem and Fire Nova damage from the child spells", function()
    local mt = byId("magmaTotem", 58734)
    assert.are.same({ 78, 371, 371, 0.1, 1000 }, { mt.level, mt.min, mt.max, mt.coef, mt.gcdMs })
    local st = byId("searingTotem", 58704)
    assert.are.same({ 80, 90, 120, 0.167 }, { st.level, st.min, st.max, st.coef })
    local fn = byId("fireNova", 61657)
    assert.are.same({ 80, 893, 997, 0.214, 10000 }, { fn.level, fn.min, fn.max, fn.coef, fn.cdMs })
    local ls = byId("lightningShield", 49281)
    assert.are.same({ 80, 380, 380, 0.267 }, { ls.level, ls.min, ls.max, ls.coef })
    assert.are.same({ 58735, 58702, 61654, 49279 }, { mt.dmgId, st.dmgId, fn.dmgId, ls.dmgId })
  end)

  it("has weapon strikes and single-rank talents", function()
    local ll = byId("lavaLash", 60103)
    assert.are.same({ 41, 100, 6000 }, { ll.level, ll.weaponPct, ll.cdMs })
    local ss = byId("stormstrike", 17364)
    assert.are.same({ 40, 100, 8000 }, { ss.level, ss.weaponPct, ss.cdMs })
    assert.are.equal(60000, byId("shamanisticRage", 30823).cdMs)
    assert.are.equal(180000, byId("feralSpirit", 51533).cdMs)
    assert.are.equal(600000, byId("fireElemental", 2894).cdMs)
    assert.are.equal(30, byId("callOfElements", 66842).level)
    assert.are.equal(8, #data.chainLightning)
  end)

  it("keys each rank by the learned spell id and keeps the damage id apart", function()
    assert.are.same({ 49238, 49238 }, { byId("lightningBolt", 49238).id, byId("lightningBolt", 49238).dmgId })
    assert.is_nil(byId("magmaTotem", 58735))
    assert.is_nil(data.lightningBolt[1].period)
  end)

  it("sorts ranks by level and fills absent numbers with 0", function()
    for key, ranks in pairs(data) do
      for i = 2, #ranks do assert.is_true(ranks[i - 1].level <= ranks[i].level, key) end
      for _, r in ipairs(ranks) do
        for _, f in ipairs({ "id", "dmgId", "level", "castMs", "gcdMs", "cdMs", "min", "max", "coef", "weaponPct" }) do
          assert.are.equal("number", type(r[f]), key .. "." .. f)
        end
      end
    end
  end)
end)
