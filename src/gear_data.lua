-- Enhancement equipment the model knows (WotLK 3.3.5a). Item ids: wowsims assets/database/db.json
-- (setName); effects: wowsims sim/shaman/*.go; glyphs by the spell GetGlyphSocketInfo returns
-- (assets/db_inputs/glyph_id_map.json maps the glyph item to it). Every mod is an addition to the
-- number without the item: wowsims adds them into one DamageMultiplier. Stat procs of trinkets are
-- not here: while up they are in the character sheet already (relics on a button: PROCS).
-- Addon only (tools/build.lua B.ADDON_SRC).
local M = {}

M.SETS = {
  -- Earthshatter Battlegear
  t7 = { 39597, 39601, 39602, 39603, 39604, 40520, 40521, 40522, 40523, 40524 },
  -- Worldbreaker Battlegear
  t8 = { 45412, 45413, 45414, 45415, 45416, 46200, 46203, 46205, 46208, 46212 },
  -- Nobundo's Battlegear (Alliance), Thrall's Battlegear (Horde): one set
  t9 = { 48341, 48342, 48343, 48344, 48345, 48346, 48347, 48348, 48349, 48350, 48351, 48352, 48353, 48354, 48355,
         48356, 48357, 48358, 48359, 48360, 48361, 48362, 48363, 48364, 48365, 48366, 48367, 48368, 48369, 48370 },
  -- Frost Witch's Battlegear: its bonuses are a TODO in wowsims, nothing to check them against
  t10 = { 50830, 50831, 50832, 50833, 50834, 51195, 51196, 51197, 51198, 51199, 51240, 51241, 51242, 51243, 51244 },
}

-- set, pieces, mod, amount. T7 4 (Flurry) is left out: the attack speed comes from UnitAttackSpeed.
M.BONUS = {
  { "t7", 2, "lsMult", 0.10 },       -- Lightning Shield +10%
  { "t8", 2, "ssMult", 0.20 },       -- Stormstrike +20%
  { "t8", 2, "llMult", 0.20 },       -- Lava Lash +20%
  { "t8", 4, "mwPpm", 0.20 },        -- Maelstrom Weapon 2.4 PPM per rank instead of 2.0
  { "t9", 2, "staticChance", 0.03 }, -- Static Shock +3%
  { "t9", 4, "shockMult", 0.25 },    -- shocks +25%
}

-- ranged slot: relics with a constant bonus
M.RELICS = {
  [45169] = { ssFlat = 155 }, -- Totem of the Dancing Flame: +155 to each Stormstrike hit
  [40710] = { wfAp = 212 },   -- Totem of Splintering: Windfury +212 attack power
  [27815] = { wfAp = 80 },    -- Totem of the Astral Winds
  [38367] = { llFlat = 25 },  -- Venture Co. Flame Slicer: Lava Lash +25
}

-- ranged slot: relics whose proc a button triggers (wowsims items_wotlk.go, items.go,
-- stormstrike.go, lavalash.go). The proc's stats are in the character sheet while it is up; the
-- model carries the buff (S.buffs.relic) for what a press keeps up after the plan. key = the
-- button ("shock": any shock); stat = "ap" | "haste" (rating, melee and spell) per stack; chance
-- per press; icd in s; aura = the proc's buff on the player. Not here: Bizuri's Totem of
-- Shattered Ice (procs from Flame Shock's ticks), Skycall Totem (spell haste only).
M.PROCS = {
  [40322] = { key = "stormstrike", stat = "haste", amount = 60, stacks = 1, duration = 6, chance = 1, icd = 0, aura = 60766 },     -- Totem of Dueling
  [50463] = { key = "stormstrike", stat = "ap", amount = 146, stacks = 3, duration = 15, chance = 1, icd = 0, aura = 71216 },      -- Totem of the Avalanche
  [42607] = { key = "lavaLash", stat = "ap", amount = 120, stacks = 1, duration = 10, chance = 1, icd = 0, aura = 60549 },         -- Deadly Gladiator's Totem of Indomitability
  [42608] = { key = "lavaLash", stat = "ap", amount = 144, stacks = 1, duration = 10, chance = 1, icd = 0, aura = 60551 },         -- Furious
  [42609] = { key = "lavaLash", stat = "ap", amount = 172, stacks = 1, duration = 10, chance = 1, icd = 0, aura = 60553 },         -- Relentless
  [51507] = { key = "lavaLash", stat = "ap", amount = 204, stacks = 1, duration = 10, chance = 1, icd = 0, aura = 60555 },         -- Wrathful
  [47667] = { key = "lavaLash", stat = "ap", amount = 400, stacks = 1, duration = 18, chance = 0.8, icd = 9, aura = 67391 },       -- Totem of Quaking Earth
  [47666] = { key = "lightningBolt", stat = "haste", amount = 200, stacks = 1, duration = 12, chance = 0.7, icd = 6, aura = 67385 },  -- Totem of Electrifying Wind
  [40708] = { key = "lightningBolt", stat = "haste", amount = 196, stacks = 1, duration = 10, chance = 0.15, icd = 30, aura = 60771 }, -- Totem of the Elemental Plane
  [33507] = { key = "shock", stat = "ap", amount = 110, stacks = 1, duration = 10, chance = 0.5, icd = 10, aura = 43749 },         -- Stonebreaker's Totem
}

-- glyph spell -> mods
M.GLYPHS = {
  [55446] = { ssNature = 0.08 },  -- Stormstrike: +28% nature instead of +20%
  [55444] = { llFt = 0.10 },      -- Lava Lash: +35% with Flametongue instead of +25%
  [55448] = { lsMult = 0.20 },    -- Lightning Shield +20%
  [55453] = { lbMult = 0.04 },    -- Lightning Bolt +4%
  [55447] = { fsCrit = 0.60 },    -- Flame Shock: critical damage bonus +60%
  [63271] = { wolvesAp = 0.30 },  -- Feral Spirit: wolves get 61% of attack power instead of 31%
  [55445] = { wfChance = 0.02 },  -- Windfury Weapon: +2% proc chance
  [55449] = { clTargets = 1 },    -- Chain Lightning: 4 targets
  [55450] = { fireNovaCd = 3 },   -- Fire Nova: cooldown -3 s
  [55442] = { shockGcd = 1 },     -- Shocking: shocks trigger a 1 s GCD (wotlkdb tooltip; not in wowsims)
}

return M
