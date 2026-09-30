local Sc = require("scenario")

-- every case: level 80 raid boss, MH Windfury / OH Flametongue unless patched.
-- wowsims drops the totems before the pull and then only refreshes them, so the base state has
-- Magma Totem up (15 s left); cases about a missing fire totem remove it explicitly.
-- setup(S) mutates the base state; expect = first action; alt = allowed alternatives with a written reason.

local function base()
  local S = Sc.state(80)
  S.totems.fire = { kind = "magma", remains = 15 }
  return S
end
local CASES = {
  { name = "pull: Feral Spirit before everything",
    setup = function(S) Sc.cd(S, { feralSpirit = 0 }) end,
    expect = "feralSpirit",
    alt = { fireElemental = "APL: both are 'autocast' cooldowns at pull, order between them does not matter",
            -- value.readyValue: a cooldown is worth the share of it already recovered
            flameShock = "one GCD of delay costs Feral Spirit 1.3/180 of a use (~60 damage) but the 6 s shock " ..
                         "cooldown 1.3/6 of an Earth Shock (~300); wowsims casts cooldowns first by rule" } },
  { name = "5 Maelstrom: instant Lightning Bolt",
    setup = function(S) S.buffs.mw = { stacks = 5, remains = 20 }; S.target.fs = 10; Sc.cd(S, { stormstrike = 4, shock = 3, lavaLash = 3 }) end,
    expect = "lightningBolt",
    alt = { chainLightning = "3.3.5a ranks: Chain Lightning 8 (973-1111, coef 0.571) hits one target harder than " ..
                             "Lightning Bolt 14 (715-815, coef 0.714) at 1200 spell power; both are instant at 5 stacks" } },
  { name = "5 Maelstrom beats a ready Stormstrike",
    setup = function(S) S.buffs.mw = { stacks = 5, remains = 20 }; S.target.fs = 10; Sc.cd(S, { shock = 3 }) end,
    expect = "lightningBolt",
    alt = { chainLightning = "same as above: at 5 stacks Chain Lightning is the bigger instant on one target",
            stormstrike = "Stormstrike first puts its +20% nature debuff under the Bolt (~+350) for about half a " ..
                          "Maelstrom stack lost to the cap during one GCD (~-90); wowsims orders by a fixed list" } },
  { name = "Stormstrike first when ready and Flame Shock is up",
    setup = function(S) S.target.fs = 10 end,
    expect = "stormstrike" },
  { name = "Flame Shock when it has dropped",
    setup = function(S) Sc.cd(S, { stormstrike = 4 }) end,
    expect = "flameShock" },
  { name = "Earth Shock while Flame Shock ticks",
    setup = function(S) S.target.fs = 9; Sc.cd(S, { stormstrike = 4 }) end,
    expect = "earthShock",
    alt = { lavaLash = "Lava Lash first gives a Maelstrom stack and fits a 1-stack Chain Lightning into the gap " ..
                       "before the next swing (no clip), then Earth Shock; without that weave Earth Shock goes first. " ..
                       "wowsims weaves only at 3+ stacks" } },
  { name = "Magma Totem when no fire totem is down",
    setup = function(S) S.totems.fire = { kind = false, remains = 0 }; S.target.fs = 9; Sc.cd(S, { stormstrike = 4, shock = 3 }) end,
    expect = "magmaTotem",
    alt = { callOfElements = "Call of the Elements drops Magma Totem too; same fire slot result" } },
  { name = "Fire Nova with Magma Totem down",
    setup = function(S) S.target.fs = 9; S.totems.fire = { kind = "magma", remains = 15 }; Sc.cd(S, { stormstrike = 4, shock = 3 }) end,
    expect = "fireNova",
    alt = { lavaLash = "same weave as in 'Earth Shock while Flame Shock ticks': Lava Lash, 1-stack Chain Lightning " ..
                       "between swings, then the shocks" } },
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
    expect = "magmaTotem",
    alt = { callOfElements = "Call of the Elements drops Magma Totem too" } },
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
    alt = { flameShock = "Phase 3 preset puts Flame Shock (fight >= 8 s) above 5-stack LB; Default WF does the opposite" } },
  { name = "Call of the Elements when the water totem is expiring",
    setup = function(S)
      S.totems.water.remains = 5; S.target.fs = 9; S.totems.fire = { kind = "magma", remains = 3 }
      Sc.cd(S, { stormstrike = 4, shock = 3, fireNova = 4, lavaLash = 3 })
    end,
    expect = "callOfElements",
    alt = { magmaTotem = "Magma expires in 3 s as well; replacing it first loses only the water refresh" } },
}

local function instant(key, at)
  return at <= 0.1
end

describe("wowsims APL agreement at level 80 #integration", function()
  for _, c in ipairs(CASES) do
    it(c.name, function()
      local S = base()
      c.setup(S)
      local key, at = Sc.first(S)
      local ok = key == c.expect or (c.alt and c.alt[key] ~= nil)
      assert.is_true(ok, ("expected %s, got %s"):format(c.expect, tostring(key)))
      assert.is_true(instant(key, at), ("%s should be pressed now, planned at %s"):format(tostring(key), tostring(at)))
    end)
  end

  it("does not start a Bolt right before a swing at 3 stacks", function()
    local S = base()
    S.buffs.mw = { stacks = 3, remains = 20 }; S.target.fs = 9; S.totems.fire = { kind = "magma", remains = 15 }
    S.swing.mh.next, S.swing.oh.next = 0.4, 1.7
    Sc.cd(S, { stormstrike = 3, shock = 3, fireNova = 4, lavaLash = 3 })
    local key, at = Sc.first(S)
    assert.is_false(key == "lightningBolt" and at < 0.35, "Bolt would delay the swing in 0.4 s")
  end)

  it("never hard-casts a 0-stack Bolt in melee", function()
    local S = base()
    S.target.fs = 9; S.totems.fire = { kind = "magma", remains = 15 }
    S.swing.mh.next, S.swing.oh.next = 0.5, 1.8
    Sc.cd(S, { stormstrike = 3, shock = 3, fireNova = 4, lavaLash = 3 })
    local key = Sc.first(S)
    assert.are_not.equal("lightningBolt", key)
  end)

  it("does not put Magma Totem over an active Fire Elemental", function()
    local S = base()
    S.target.fs = 9; S.totems.fire = { kind = "fireElemental", remains = 90 }
    Sc.cd(S, { stormstrike = 4, shock = 3 })
    for _, st in ipairs(Sc.best(S).steps) do assert.are_not.equal("magmaTotem", st.key) end
  end)
end)
