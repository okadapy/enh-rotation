local advice = require("advice")

-- a clean fight's numbers; over replaces fields
local function fight(over)
  local f = { name = "Kobold", seconds = 60, presses = 50, suggested = 50, matched = 46, rate = 0.92, delay = 0.15,
              stale = 0, late = 0, lost = 0, unrated = 0, pairs = {}, dps = 1000,
              mw = { wasted = 0, idle = 0 }, gcdIdle = 0, swings = 0, fs = { seen = 0, up = 0 },
              prep = { shield = 0, totems = 0, enchants = 0, autoAttack = 0 } }
  for k, v in pairs(over or {}) do f[k] = v end
  return f
end

local function codes(tips)
  local out = {}
  for i, t in ipairs(tips) do out[i] = t.code end
  return table.concat(out, ",")
end

describe("addon fight advice", function()
  it("formats damage and shares", function()
    assert.are.equal("1.2k", advice.k(1234))
    assert.are.equal("56", advice.k(56.4))
    assert.are.equal("87%", advice.pct(0.873))
    assert.are.equal("-", advice.pct(nil))
  end)

  it("a clean fight says so", function()
    local tips = advice.tips(fight())
    assert.are.equal("clean", codes(tips))
    assert.are.equal("Clean fight - 92% matched, ~0.15s delay", tips[1].text)
  end)

  it("names the costly wrong pair from 15% of the loss", function()
    local pairs = { ["stormstrike>lightningBolt"] = { sug = "stormstrike", key = "lightningBolt", count = 4, lost = 4200 },
                    ["lavaLash>earthShock"] = { sug = "lavaLash", key = "earthShock", count = 1, lost = 100 } }
    local tips = advice.tips(fight({ lost = 4300, pairs = pairs }))
    assert.are.equal("wrong", tips[1].code)
    assert.are.equal(4200, tips[1].weight)
    assert.are.equal("Often pressed Lightning Bolt where Stormstrike was better (~4.2k damage)", tips[1].text)
    assert.are.equal("4 times; follow the big icon when the two differ", tips[1].detail)
    -- below 15% of the loss: no tip
    pairs["stormstrike>lightningBolt"].lost = 10
    assert.are.equal("clean", codes(advice.tips(fight({ lost = 1000, pairs = pairs }))))
  end)

  it("each rule fires at its threshold, not below", function()
    local cases = {
      { "delay", { delay = 0.31 }, { delay = 0.3 } },
      { "mw_wasted", { mw = { wasted = 2, idle = 0 } }, { mw = { wasted = 1, idle = 0 } } },
      { "mw_idle", { mw = { wasted = 0, idle = 3 } }, { mw = { wasted = 0, idle = 2.9 } } },
      { "gcd_idle", { gcdIdle = 3 }, { gcdIdle = 2.9 } }, -- 5% of 60 s
      { "swings", { swings = 3 }, { swings = 2 } },
      { "flame_shock", { fs = { seen = 30, up = 23 } }, { fs = { seen = 29, up = 0 } } },
      { "prep_shield", { prep = { shield = 5, totems = 0, enchants = 0, autoAttack = 0 } },
                       { prep = { shield = 4.9, totems = 0, enchants = 0, autoAttack = 0 } } },
      { "prep_totems", { prep = { shield = 0, totems = 5, enchants = 0, autoAttack = 0 } }, {} },
      { "prep_enchants", { prep = { shield = 0, totems = 0, enchants = 5, autoAttack = 0 } }, {} },
      { "prep_attack", { prep = { shield = 0, totems = 0, enchants = 0, autoAttack = 5 } }, {} },
    }
    for _, c in ipairs(cases) do
      assert.are.equal(c[1], codes(advice.tips(fight(c[2]))), c[1])
      assert.are.equal("clean", codes(advice.tips(fight(c[3]))), c[1] .. " below")
    end
  end)

  it("flame shock at 80% uptime is fine", function()
    assert.are.equal("clean", codes(advice.tips(fight({ fs = { seen = 100, up = 80 } }))))
  end)

  it("texts of the mechanics tips", function()
    local tips = advice.tips(fight({ delay = 0.42, mw = { wasted = 5, idle = 6.4 }, gcdIdle = 4.8, swings = 3,
                                     fs = { seen = 100, up = 62 },
                                     prep = { shield = 12, totems = 7, enchants = 9, autoAttack = 6 } }))
    assert.are.equal(5, #tips) -- 10 candidates, the 5 heaviest
    advice.MAX = 20
    local all = advice.tips(fight({ delay = 0.42, mw = { wasted = 5, idle = 6.4 }, gcdIdle = 4.8, swings = 3,
                                    fs = { seen = 100, up = 62 }, prep = { shield = 12, totems = 7, enchants = 9, autoAttack = 6 } }))
    advice.MAX = 5
    assert.are.equal(10, #all)
    local by = {}
    for _, t in ipairs(all) do by[t.code] = t.text end
    assert.are.equal("Presses come ~0.4s late - try queueing the next button earlier", by.delay)
    assert.are.equal("5 Maelstrom stacks wasted - cast at 5 right away", by.mw_wasted)
    assert.are.equal("Sat on 5 Maelstrom stacks for 6s", by.mw_idle)
    assert.are.equal("GCD idle 8% of the fight", by.gcd_idle)
    assert.are.equal("3 swings delayed by casts", by.swings)
    assert.are.equal("Flame Shock uptime 62%", by.flame_shock)
    assert.are.equal("No Lightning Shield for 12s", by.prep_shield)
    assert.are.equal("No fire totem for 7s", by.prep_totems)
    assert.are.equal("Weapon enchant missing for 9s", by.prep_enchants)
    assert.are.equal("Auto-attack off in melee for 6s", by.prep_attack)
  end)

  it("orders by weight: dps-based for the mechanics", function()
    -- gcd_idle 4 s x 1000 = 4000; mw_wasted 2 x 0.3 x 1000 = 600; swings 3 x 0.5 x 1000 = 1500
    local tips = advice.tips(fight({ gcdIdle = 4, mw = { wasted = 2, idle = 0 }, swings = 3 }))
    assert.are.equal("gcd_idle,swings,mw_wasted", codes(tips))
    assert.are.equal(4000, tips[1].weight)
  end)

  it("the chat line: name, share, loss, the first tip and the trend", function()
    local f = fight({ key = "Lich King 25 Player", name = "Lich King", rate = 0.87, lost = 3100,
                      mw = { wasted = 5, idle = 0 } })
    local tips = advice.tips(f)
    assert.are.equal("Lich King 25 Player - 87% matched, ~3.1k damage lost. Tip: 5 Maelstrom stacks wasted - cast at 5 right away. /dmr last",
      advice.summary(f, tips))
    assert.are.equal("Lich King 25 Player - 87% matched, ~3.1k damage lost, better than before. Tip: 5 Maelstrom stacks wasted - cast at 5 right away. /dmr last",
      advice.summary(f, tips, "better"))
    local clean = fight()
    assert.are.equal("Kobold - 92% matched, ~0 damage lost. Clean fight. /dmr last", advice.summary(clean, advice.tips(clean)))
  end)
end)
