local Sc = require("scenario")

local WAIT = { waitSwing = true, wait = true }

-- A mob in the middle of the fight: the fire totem was dropped on the pull and Shamanistic Rage
-- was used on an earlier mob (60 s cooldown), so the case is about the rotation itself.
local function midFight(level)
  local S = Sc.state(level)
  if S.spells.searingTotem then S.totems.fire = { kind = "searing", remains = 40 } end
  if S.spells.shamanisticRage then S.spells.shamanisticRage.cd = 40 end
  return S
end

-- first action, or an alternative with the reason why it is right as well
local function check(S, expect, alt)
  local key = Sc.first(S)
  assert.is_true(key == expect or (alt ~= nil and alt[key] ~= nil), ("expected %s, got %s"):format(expect, tostring(key)))
end

local function situations(level)
  local fresh = Sc.state(level)
  local busy = Sc.state(level)
  busy.target.fs = 9
  busy.totems.fire = { kind = "searing", remains = 30 }
  for key in pairs(busy.spells) do busy.spells[key].cd = 3 end
  local stacked = Sc.state(level, { buffs = { mw = { stacks = 5, remains = 20 } } })
  local dying = Sc.state(level)
  dying.target.hp, dying.target.hpPct, dying.target.ttd = dying.target.hpMax * 0.05, 0.05, 2
  return { fresh = fresh, busy = busy, stacked = stacked, dying = dying }
end

describe("leveling #integration", function()
  for level = 1, 80 do
    it("level " .. level .. " never suggests an unknown spell", function()
      for name, S in pairs(situations(level)) do
        for _, st in ipairs(Sc.best(S).steps) do
          assert.is_true(S.spells[st.key] ~= nil or WAIT[st.key] == true, ("level %d %s: %s is not known"):format(level, name, st.key))
        end
      end
    end)
  end

  it("level 10: Flame Shock on a fresh mob", function()
    check(Sc.state(10), "flameShock", {
      searingTotem = "Searing Totem 1 costs 12 mana, shoots for 60 s and over a 20 s fight deals more than " ..
                     "Flame Shock 1; leveling guides drop it on the pull as well" })
  end)

  it("level 10 knows no Stormstrike, Lava Lash or Maelstrom", function()
    local S = Sc.state(10)
    assert.is_nil(S.spells.stormstrike)
    assert.is_nil(S.spells.lavaLash)
    assert.is_nil(S.weapons.oh)
  end)

  -- recorded in game (level 53, solo, 8-25% mana, Rage on cooldown): the planner idled in melee
  -- with Stormstrike and Lava Lash ready. Each costs 2-4% of the bar, half a second of drinking;
  -- Stormstrike (+20% to the shocks after it), Earth Shock and Lava Lash are the core buttons.
  it("level 53, low mana, Rage on cooldown: still a melee button, not idling", function()
    local S = midFight(53)
    S.target.fs = 10
    S.player.mana = S.player.manaMax * 0.08
    local key = Sc.first(S)
    assert.is_true(key == "stormstrike" or key == "lavaLash" or key == "earthShock", "got " .. tostring(key))
  end)

  -- Shamanistic Rage returns 15% of AP as mana on every landed melee attack, Stormstrike (two
  -- hits) and Lava Lash included: at level 70 two Stormstrike hits bring back more than its cost.
  -- At 8% mana under Rage the plan must not stop after Feral Spirit and Fire Elemental.
  it("level 70, low mana under Rage: Stormstrike still in the plan, it pays for itself", function()
    local S = midFight(70)
    S.target.fs = 10
    S.buffs.rage = 12
    S.player.mana = math.floor(S.player.manaMax * 0.08)
    local keys = {}
    for _, st in ipairs(Sc.best(S).steps) do keys[st.key] = true end
    assert.is_true(keys.stormstrike == true, "no Stormstrike in the plan")
  end)

  -- recorded in game (level 54, solo): Flame Shock and Lightning Bolts on the pull at 20-30 yd
  -- spent the bar, and in melee Stormstrike, Earth Shock and Lava Lash could not be paid. The
  -- mana for one press of each is kept while the mob is on its way; a Bolt that keeps the bar
  -- above it is still fine. Mana: the reserve + one Bolt + a little, so a second Bolt dips below.
  it("level 54 solo at 20 yd: no Lightning Bolt that leaves too little mana for Stormstrike", function()
    local S = midFight(54)
    S.target.range = "20"
    assert.is_not_nil(S.spells.stormstrike)
    local reserve = S.spells.stormstrike.cost + S.spells.earthShock.cost + S.spells.lavaLash.cost
    S.player.mana = reserve + S.spells.lightningBolt.cost + 10
    local mana, bolts = S.player.mana, 0
    for _, st in ipairs(Sc.best(S).steps) do
      local sp = S.spells[st.key]
      mana = mana - (sp and sp.cost or 0)
      if st.key == "lightningBolt" or st.key == "chainLightning" then
        bolts = bolts + 1
        assert.is_true(mana >= reserve, ("%s at %.1f s leaves %d mana, reserve %d"):format(st.key, st.at, mana, reserve))
      end
    end
    assert.is_true(bolts >= 1, "the Bolt the mana above the reserve pays for is still cast")
  end)

  it("level 25: Earth Shock while Flame Shock ticks", function()
    local S = midFight(25)
    S.target.fs = 10
    assert.are.equal("earthShock", (Sc.first(S)))
  end)

  it("level 35: a fire totem when shocks are on cooldown", function()
    local S = Sc.state(35)
    S.target.fs = 10
    Sc.cd(S, { shock = 4 })
    local key = Sc.first(S)
    assert.is_true(key == "searingTotem" or key == "magmaTotem", tostring(key))
  end)

  it("level 54 pull: no Searing Totem for a target out of its 20 yards", function()
    -- the totem stands at the shaman's feet: a mob at 30 yards or farther is not shot
    for _, range in ipairs({ "30", "far" }) do
      local S = Sc.state(54)
      S.mode = "solo"
      S.target.range, S.target.fs = range, 0
      S.enemies = { melee = 0, nearby = 1 }
      S.player.inCombat = false
      assert.are_not.equal("searingTotem", (Sc.first(S)), range)
    end
  end)

  it("level 42: Stormstrike once learned", function()
    local S = midFight(42)
    S.target.fs = 10
    assert.are.equal("stormstrike", (Sc.first(S)))
  end)

  it("level 50: Lava Lash as filler", function()
    local S = midFight(50)
    S.target.fs = 10
    Sc.cd(S, { stormstrike = 4, shock = 3, fireNova = 4 })
    assert.are.equal("lavaLash", (Sc.first(S)))
  end)

  it("level 58: 5 Maelstrom stacks go into Lightning Bolt", function()
    local S = midFight(58)
    S.target.fs = 10
    S.buffs.mw = { stacks = 5, remains = 20 }
    Sc.cd(S, { stormstrike = 4, shock = 3 })
    assert.are.equal("lightningBolt", (Sc.first(S)))
  end)

  it("level 53 solo: no hard-cast Lightning Bolt into a mob that dies before it lands", function()
    local S = midFight(53)
    S.target.fs = 10
    S.target.hp, S.target.hpPct, S.target.ttd = S.target.hpMax * 0.2, 0.2, 1.5
    Sc.cd(S, { stormstrike = 4, shock = 4, lavaLash = 4 })
    for _, st in ipairs(Sc.best(S).steps) do
      assert.is_true(st.key ~= "lightningBolt" and st.key ~= "chainLightning", st.key)
    end
  end)

  it("solo: no mana on a mob that auto attacks finish anyway", function()
    local S = Sc.state(30)
    S.target.hp, S.target.hpPct, S.target.ttd = S.target.hpMax * 0.05, 0.05, 2
    S.swing.mh.next = 0.3
    local key = Sc.first(S)
    assert.is_true(key == nil or (S.spells[key].cost or 0) == 0, tostring(key))
  end)

  it("solo: no Flame Shock on a mob about to die", function()
    local S = Sc.state(30)
    S.target.hp, S.target.hpPct, S.target.ttd = S.target.hpMax * 0.1, 0.1, 3
    assert.are_not.equal("flameShock", (Sc.first(S)))
  end)
end)
