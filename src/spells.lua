local data = require("spells_data")

local M = {}

local I = "Interface\\Icons\\"

-- Static facts the client data does not carry. Numbers from the 3.3.5a tooltips
-- (Flame Shock 18 s = DurationIndex 85 in Spell.dbc, 6 ticks every 3 s).
M.CATALOG = {
  { key = "stormstrike", name = "Stormstrike", school = "physical", weapon = true, hands = "both",
    duration = 12, charges = 4, bonus = 20, icon = I .. "Ability_Shaman_Stormstrike" },
  { key = "lavaLash", name = "Lava Lash", school = "fire", weapon = true, hands = "oh",
    icon = I .. "Ability_Shaman_Lavalash" },
  { key = "earthShock", name = "Earth Shock", school = "nature", sharedCd = "shock",
    icon = I .. "Spell_Nature_EarthShock" },
  { key = "flameShock", name = "Flame Shock", school = "fire", sharedCd = "shock", duration = 18, period = 3,
    icon = I .. "Spell_Fire_FlameShock" },
  { key = "frostShock", name = "Frost Shock", school = "frost", sharedCd = "shock",
    icon = I .. "Spell_Frost_FrostShock" },
  { key = "lightningBolt", name = "Lightning Bolt", school = "nature", castBase = 2.5,
    icon = I .. "Spell_Nature_Lightning" },
  { key = "chainLightning", name = "Chain Lightning", school = "nature", castBase = 2.0, maxTargets = 3,
    icon = I .. "Spell_Nature_ChainLightning" },
  { key = "searingTotem", name = "Searing Totem", school = "fire", totem = "fire", duration = 60, period = 2.5,
    icon = I .. "Spell_Fire_SearingTotem" },
  { key = "magmaTotem", name = "Magma Totem", school = "fire", totem = "fire", duration = 20, period = 2,
    maxTargets = 20, icon = I .. "Spell_Fire_SelfDestruct" },
  { key = "fireNova", name = "Fire Nova", school = "fire", requiresFireTotem = true, maxTargets = 20,
    icon = I .. "Spell_Fire_SealOfFire" },
  { key = "fireElemental", name = "Fire Elemental Totem", school = "fire", totem = "fire", duration = 120,
    icon = I .. "Spell_Fire_Elemental_Totem" },
  { key = "callOfElements", name = "Call of the Elements", school = "nature",
    icon = I .. "Spell_Shaman_DropAll_01" },
  { key = "lightningShield", name = "Lightning Shield", school = "nature", duration = 600, charges = 3,
    icon = I .. "Spell_Nature_LightningShield" },
  { key = "shamanisticRage", name = "Shamanistic Rage", school = "physical", duration = 15,
    icon = I .. "Spell_Nature_ShamanRage" },
  { key = "feralSpirit", name = "Feral Spirit", school = "physical", duration = 45,
    icon = I .. "Spell_Shaman_FeralSpirit" },
}

M.byKey = {}
M.KEYS = {}

for i, s in ipairs(M.CATALOG) do
  local ranks = assert(data[s.key], "no spells_data for " .. s.key)
  local top = ranks[#ranks]
  s.ranks = {}
  for j, r in ipairs(ranks) do s.ranks[j] = r.id end
  s.gcd = top.gcdMs / 1000
  s.cd = top.cdMs / 1000
  s.castBase = s.castBase or 0
  M.byKey[s.key] = s
  M.KEYS[i] = s.key
end

function M.rank(key, id)
  for _, r in ipairs(data[key] or {}) do
    if r.id == id then return r end
  end
  return nil
end

return M
