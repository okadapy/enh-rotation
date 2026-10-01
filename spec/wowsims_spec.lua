local Sc = require("scenario")

-- every case: level 80 raid boss, MH Windfury / OH Flametongue unless patched.
-- wowsims drops the totems before the pull and then only refreshes them, so the base state has
-- Magma Totem up (15 s left); cases about a missing fire totem remove it explicitly.
-- setup(S) mutates the base state; expect = first action; alt = allowed alternatives with a written reason;
-- raidAlt = the same, for the run under the raid's debuffs only.

local function base()
  local S = Sc.state(80)
  S.totems.fire = { kind = "magma", remains = 15 }
  return S
end
local CASES = {
  { name = "pull: Feral Spirit before everything",
    setup = function(S) Sc.cd(S, { feralSpirit = 0 }) end,
    expect = "feralSpirit",
    -- under the raid's debuffs the search starts with Flame Shock (the alt below): fire takes 13%
    -- more and 8% more spell crit, the wolves only the armor and 4%. With either forced first and
    -- the rest searched: 25097 against 25041 (without debuffs 20999 against 20991)
    alt = { -- value.readyValue: a cooldown is worth the share of it already recovered
            flameShock = "one GCD of delay costs Feral Spirit 1.3/180 of a use (~60 damage) but the 6 s shock " ..
                         "cooldown 1.3/6 of an Earth Shock (~300); wowsims casts cooldowns first by rule" } },
  { name = "5 Maelstrom: instant Lightning Bolt",
    setup = function(S) S.buffs.mw = { stacks = 5, remains = 20 }; S.target.fs = 10; Sc.cd(S, { stormstrike = 4, shock = 3, lavaLash = 3 }) end,
    expect = "lightningBolt",
    alt = { chainLightning = "3.3.5a ranks: Chain Lightning 8 (973-1111, coef 0.571) hits one target harder than " ..
                             "Lightning Bolt 14 (715-815, coef 0.714) at 1200 spell power; both are instant at 5 stacks" } },
  { name = "5 Maelstrom beats a ready Stormstrike",
    setup = function(S) S.buffs.mw = { stacks = 5, remains = 20 }; S.target.fs = 10; Sc.cd(S, { shock = 3 }) end,
    expect = "lightningBolt" },
  { name = "Stormstrike first when ready and Flame Shock is up",
    setup = function(S) S.target.fs = 10 end,
    expect = "stormstrike" },
  { name = "Flame Shock when it has dropped",
    setup = function(S) Sc.cd(S, { stormstrike = 4 }) end,
    expect = "flameShock" },
  { name = "Earth Shock while Flame Shock ticks",
    setup = function(S) S.target.fs = 9; Sc.cd(S, { stormstrike = 4 }) end,
    expect = "earthShock" },
  { name = "Magma Totem when no fire totem is down",
    setup = function(S) S.totems.fire = { kind = false, remains = 0 }; S.target.fs = 9; Sc.cd(S, { stormstrike = 4, shock = 3 }) end,
    expect = "magmaTotem" },
  -- our Flametongue Totem under an elemental's Totem of Wrath: theirs gives the spell power, ours
  -- is a foreign kind (snapshot: "other") worth no damage, so a damage totem goes over it
  { name = "a foreign fire totem (our Flametongue under an elemental's Totem of Wrath): Magma Totem",
    setup = function(S)
      S.totems.fire = { kind = "other", remains = 100 }; S.target.fs = 9
      Sc.cd(S, { stormstrike = 4, shock = 3, fireNova = 4 })
    end,
    expect = "magmaTotem" },
  { name = "Fire Nova with Magma Totem down",
    setup = function(S) S.target.fs = 9; S.totems.fire = { kind = "magma", remains = 15 }; Sc.cd(S, { stormstrike = 4, shock = 3 }) end,
    expect = "fireNova",
    alt = { lavaLash = "Lava Lash first gives a Maelstrom stack and fits a 1-stack Chain Lightning into the gap " ..
                       "before the next swing (no clip), then the shocks: 18417 against 17929 for Fire Nova first " ..
                       "(search with Fire Nova forced first). wowsims weaves only at 3+ stacks" } },
  { name = "Lightning Shield when it has dropped",
    setup = function(S)
      S.target.fs = 9; S.totems.fire = { kind = "magma", remains = 15 }; S.buffs.ls = { charges = 0, remains = 0 }
      Sc.cd(S, { stormstrike = 4, shock = 3, fireNova = 4, lavaLash = 3 })
    end,
    expect = "lightningShield" },
  { name = "Lava Lash as the last filler",
    setup = function(S) S.target.fs = 9; S.totems.fire = { kind = "magma", remains = 15 }; Sc.cd(S, { stormstrike = 4, shock = 3, fireNova = 4 }) end,
    expect = "lavaLash" },
  { name = "WF weave: 3 stacks and a long gap before the next swing",
    setup = function(S)
      S.buffs.mw = { stacks = 3, remains = 20 }; S.target.fs = 9; S.totems.fire = { kind = "magma", remains = 15 }
      S.swing.mh.next, S.swing.oh.next = 2.0, 2.2
      Sc.cd(S, { stormstrike = 3, shock = 3, fireNova = 4, lavaLash = 3 })
    end,
    expect = "lightningBolt" },
  -- the weaving option at its default (S.weaveMin = 3): wowsims weaves only at 3+ stacks
  { name = "weave 3+: 3 stacks and a long gap before the next swing",
    setup = function(S)
      S.weaveMin = 3
      S.buffs.mw = { stacks = 3, remains = 20 }; S.target.fs = 9; S.totems.fire = { kind = "magma", remains = 15 }
      S.swing.mh.next, S.swing.oh.next = 2.0, 2.2
      Sc.cd(S, { stormstrike = 3, shock = 3, fireNova = 4, lavaLash = 3 })
    end,
    expect = "lightningBolt",
    alt = { chainLightning = "3.3.5a ranks: Chain Lightning 8 hits one target harder than Lightning Bolt 14; without " ..
                             "the option the Bolt keeps Chain Lightning for a 1-2 stack cast at 4.4 s, which 3+ forbids" } },
  { name = "weave 3+: 2 stacks and a long gap: Lava Lash, not a 2-stack Bolt",
    setup = function(S)
      S.weaveMin = 3
      S.buffs.mw = { stacks = 2, remains = 20 }; S.target.fs = 9; S.totems.fire = { kind = "magma", remains = 15 }
      S.swing.mh.next, S.swing.oh.next = 2.0, 2.2
      Sc.cd(S, { stormstrike = 3, shock = 3, fireNova = 4 })
    end,
    expect = "lavaLash" },
  { name = "Shamanistic Rage at low mana",
    setup = function(S)
      S.player.mana = S.player.manaMax * 0.1; S.target.fs = 9; S.totems.fire = { kind = "magma", remains = 15 }
      Sc.cd(S, { shamanisticRage = 0, stormstrike = 4, shock = 3, fireNova = 4, lavaLash = 3 })
    end,
    expect = "shamanisticRage" },
  { name = "AoE: Chain Lightning at 5 stacks",
    setup = function(S)
      S.enemies = { melee = 4, nearby = 4 }; S.buffs.mw = { stacks = 5, remains = 20 }; S.target.fs = 9
      S.totems.fire = { kind = "magma", remains = 15 }; Sc.cd(S, { stormstrike = 4, shock = 3, fireNova = 4 })
    end,
    expect = "chainLightning" },
  { name = "AoE: Magma Totem when no fire totem",
    setup = function(S)
      S.totems.fire = { kind = false, remains = 0 }; S.enemies = { melee = 4, nearby = 4 }; S.target.fs = 9
      Sc.cd(S, { stormstrike = 4, shock = 3 })
    end,
    expect = "magmaTotem" },
  { name = "AoE: Fire Nova with Magma down",
    setup = function(S)
      S.enemies = { melee = 4, nearby = 4 }; S.target.fs = 9; S.totems.fire = { kind = "magma", remains = 15 }
      Sc.cd(S, { stormstrike = 4, shock = 3 })
    end,
    expect = "fireNova" },
  { name = "FT build: Stormstrike when ready",
    setup = function(S) S.weapons.mh.enchant = "ft"; S.target.fs = 10 end,
    expect = "stormstrike" },
  { name = "Phase 3: Flame Shock missing with 5 stacks",
    setup = function(S) S.buffs.mw = { stacks = 5, remains = 20 }; Sc.cd(S, { stormstrike = 4 }) end,
    expect = "lightningBolt",
    alt = { flameShock = "wowsims Phase 3 preset puts Flame Shock (fight >= 8 s) above the 5-stack Bolt, Default WF " ..
                         "the other way round. The model agrees with Phase 3 by a small margin: Flame Shock, then " ..
                         "Chain Lightning 16128 against 15978 the other way (6 s horizon); with a 7 s horizon it " ..
                         "would be Chain Lightning first (17201 against 17182)" } },
  -- Flame Shock refresh (value.shockOption): a recast overwrites the DoT, the ticks left are lost.
  -- Everything but the shocks on cooldown, as in the review that found the clip.
  { name = "Earth Shock, not a Flame Shock refresh, with 4.5 s of it left",
    setup = function(S) S.target.fs = 4.5; Sc.cd(S, { stormstrike = 7, lavaLash = 5.5, fireNova = 7 }) end,
    expect = "earthShock" },
  { name = "Earth Shock, not a Flame Shock refresh, with 3 s of it left",
    setup = function(S) S.target.fs = 3; Sc.cd(S, { stormstrike = 7, lavaLash = 5.5, fireNova = 7 }) end,
    expect = "earthShock",
    alt = { flameShock = "6 s shared shock cooldown, 18 s DoT: kept up it takes one of 3 shocks, a shock is worth " ..
                         "g = (817 + 18 x 100 + 2 x 1441) / 3 = 1834 on average. Earth Shock now keeps the 3 s of " ..
                         "ticks a refresh clips (+300) but moves the recast to the next shock, sliding the whole " ..
                         "rotation by one press (-(g - Earth Shock) = -393): the refresh is 93 better, and so below " ..
                         "393 / 100 = 3.9 s left. Search 16357 against 16273; wowsims recasts only a dropped DoT" } },
  { name = "Earth Shock, not a Flame Shock refresh, with 1.5 s of it left",
    setup = function(S) S.target.fs = 1.5; Sc.cd(S, { stormstrike = 7, lavaLash = 5.5, fireNova = 7 }) end,
    expect = "earthShock",
    alt = { flameShock = "as with 3 s left: the refresh clips 150 of ticks, Earth Shock now slides the rotation by " ..
                         "one press (-393): the refresh is 243 better. Search 16357 against 16123" } },
  { name = "Flame Shock when it has run out and everything else is on cooldown",
    setup = function(S) S.target.fs = 0; Sc.cd(S, { stormstrike = 7, lavaLash = 5.5, fireNova = 7 }) end,
    expect = "flameShock" },
  { name = "Call of the Elements when the water totem is expiring",
    setup = function(S)
      S.totems.water.remains = 5; S.target.fs = 9; S.totems.fire = { kind = "magma", remains = 3 }
      Sc.cd(S, { stormstrike = 4, shock = 3, fireNova = 4, lavaLash = 3 })
    end,
    expect = "callOfElements" },
}

local function instant(key, at)
  return at <= 0.1
end

-- every case twice: on a target without debuffs, and under the wowsims raid's (FullDebuffs, the
-- set their enhancement APL runs with). raidAlt: alternatives for the second one only, with a reason
local VARIANTS = { { suffix = "", mods = nil }, { suffix = " (raid debuffs)", mods = Sc.raidMods } }

describe("wowsims APL agreement at level 80 #integration", function()
  for _, var in ipairs(VARIANTS) do
    for _, c in ipairs(CASES) do
      it(c.name .. var.suffix, function()
        local S = base()
        S.mods = var.mods and var.mods() or nil
        c.setup(S)
        local key, at = Sc.first(S)
        local ok = key == c.expect or (c.alt and c.alt[key] ~= nil)
          or (var.mods and c.raidAlt and c.raidAlt[key] ~= nil)
        assert.is_true(ok, ("expected %s, got %s"):format(c.expect, tostring(key)))
        assert.is_true(instant(key, at), ("%s should be pressed now, planned at %s"):format(tostring(key), tostring(at)))
      end)
    end
  end

  -- wowsims weaves a 3-stack Bolt only when it does not delay a swing. The model may start it now:
  -- both lines then hard-cast a 1-stack Chain Lightning at 4.3 s, which holds the main-hand swing
  -- until 5.84 s in both, so inside the 6 s horizon the Bolt's delay of the 0.4 s swing costs
  -- nothing, and the Bolt now keeps the Maelstrom stack that swing brings (0.46 vs 0.32 stacks
  -- after it). With a 5, 6.5 or 7 s horizon the model waits for the swing instead; in the simulated
  -- fight (spec/support/fight.lua, 30 x 60 s) a strict "no delayed swing" rule gives the same DPS
  -- (2135 vs 2139). So it is allowed, but only as a small difference.
  it("a Bolt right before a swing at 3 stacks only when it is worth at most 2% more than after it", function()
    local S = base()
    S.buffs.mw = { stacks = 3, remains = 20 }; S.target.fs = 9; S.totems.fire = { kind = "magma", remains = 15 }
    S.swing.mh.next, S.swing.oh.next = 0.4, 1.7
    Sc.cd(S, { stormstrike = 3, shock = 3, fireNova = 4, lavaLash = 3 })
    local key, at, plan = Sc.first(S)
    if key == "lightningBolt" and at < 0.35 then
      local after = { { key = "lightningBolt", at = 0.41, reason = "", afterSwing = true } }
      for i = 2, #plan.steps do after[i] = plan.steps[i] end
      local v = require("search").evaluate(S, after)
      assert.is_true(v and plan.value <= v * 1.02, ("now %.0f, after the swing %s"):format(plan.value, tostring(v)))
    end
  end)

  it("never hard-casts a 0-stack Bolt in melee", function()
    local S = base()
    S.target.fs = 9; S.totems.fire = { kind = "magma", remains = 15 }
    S.swing.mh.next, S.swing.oh.next = 0.5, 1.8
    Sc.cd(S, { stormstrike = 3, shock = 3, fireNova = 4, lavaLash = 3 })
    local key = Sc.first(S)
    assert.are_not.equal("lightningBolt", key)
  end)

  -- the review of the level-80 opener: Flame Shock down, everything else ready. Without the option
  -- the model may weave a 1-2 stack cast (it rests on the unverified swing rule: a 1-4 stack cast
  -- holds the swing, a 0-stack one resets it); with the default 3+ Stormstrike and Flame Shock
  -- come first and no Bolt / Chain Lightning below 3 stacks anywhere in the plan
  it("weave 3+ (the default): the opener starts with Stormstrike and Flame Shock, no cast below 3 stacks", function()
    local model = require("model")
    local S = base()
    S.weaveMin = 3
    local plan = Sc.best(S)
    local first = { plan.steps[1].key, plan.steps[2].key }
    table.sort(first)
    assert.are.same({ "flameShock", "stormstrike" }, first)
    local cur = S
    for _, st in ipairs(plan.steps) do
      local w = st.at - (cur.now - S.now)
      if w > 1e-9 then cur = model.wait(cur, w) end
      if st.key == "lightningBolt" or st.key == "chainLightning" then
        assert.is_true(cur.buffs.mw.stacks >= 3, ("%s at %.2f with %.2f stacks"):format(st.key, st.at, cur.buffs.mw.stacks))
      end
      cur = model.apply(cur, st.key)
    end
  end)

  it("does not put Magma Totem over an active Fire Elemental", function()
    local S = base()
    S.target.fs = 9; S.totems.fire = { kind = "fireElemental", remains = 90 }
    Sc.cd(S, { stormstrike = 4, shock = 3 })
    for _, st in ipairs(Sc.best(S).steps) do assert.are_not.equal("magmaTotem", st.key) end
  end)

  -- the multipliers at 1 and the additions at 0 must give the very same plans: S.mods may only
  -- ever change a result through a field that is set (AGENTS.md "bit for bit"). shockGcd is not
  -- in the set: any value above 0 turns the glyph on
  it("neutral S.mods: the same plans as without, bit for bit", function()
    local neutral = { armor = 1, spellTaken = 1, physTaken = 1, critTaken = 0, spellCritTaken = 0, spellHitTaken = 0,
                      ssFlat = 0, llFlat = 0, wfAp = 0, ssMult = 0, llMult = 0, lsMult = 0, shockMult = 0, lbMult = 0,
                      staticChance = 0, mwPpm = 0, ssNature = 0, llFt = 0, fsCrit = 0, wolvesAp = 0, wfChance = 0,
                      clTargets = 0, fireNovaCd = 0 }
    for i, S in ipairs(Sc.randomStates(30, 11)) do
      local plain = Sc.best(S)
      S.mods = neutral
      local with = Sc.best(S)
      assert.are.equal(plain.value, with.value, "state " .. i)
      assert.are.equal(plain.nodes, with.nodes, "state " .. i)
      assert.are.equal(#plain.steps, #with.steps, "state " .. i)
      for k, st in ipairs(plain.steps) do
        assert.are.equal(st.key, with.steps[k].key, "state " .. i)
        assert.are.equal(st.at, with.steps[k].at, "state " .. i)
      end
    end
  end)
end)
