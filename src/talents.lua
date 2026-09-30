local M = {}

-- Talents that change enhancement damage, costs or cooldowns. Matched by English name,
-- so tab and position do not matter (the client is enGB).
M.KEYS = {
  { key = "convection", name = "Convection" },
  { key = "concussion", name = "Concussion" },
  { key = "callOfFlame", name = "Call of Flame" },
  { key = "elementalDevastation", name = "Elemental Devastation" },
  { key = "reverberation", name = "Reverberation" },
  { key = "elementalFocus", name = "Elemental Focus" },
  { key = "elementalFury", name = "Elemental Fury" },
  { key = "improvedFireNova", name = "Improved Fire Nova" },
  { key = "elementalPrecision", name = "Elemental Precision" },
  { key = "stormEarthAndFire", name = "Storm, Earth and Fire" },
  { key = "enhancingTotems", name = "Enhancing Totems" },
  { key = "ancestralKnowledge", name = "Ancestral Knowledge" },
  { key = "thunderingStrikes", name = "Thundering Strikes" },
  { key = "improvedShields", name = "Improved Shields" },
  { key = "elementalWeapons", name = "Elemental Weapons" },
  { key = "shamanisticFocus", name = "Shamanistic Focus" },
  { key = "flurry", name = "Flurry" },
  { key = "weaponMastery", name = "Weapon Mastery" },
  { key = "dualWieldSpecialization", name = "Dual Wield Specialization" },
  { key = "dualWield", name = "Dual Wield" },
  { key = "stormstrike", name = "Stormstrike" },
  { key = "staticShock", name = "Static Shock" },
  { key = "lavaLash", name = "Lava Lash" },
  { key = "improvedStormstrike", name = "Improved Stormstrike" },
  { key = "mentalQuickness", name = "Mental Quickness" },
  { key = "mentalDexterity", name = "Mental Dexterity" },
  { key = "unleashedRage", name = "Unleashed Rage" },
  { key = "shamanisticRage", name = "Shamanistic Rage" },
  { key = "maelstromWeapon", name = "Maelstrom Weapon" },
  { key = "feralSpirit", name = "Feral Spirit" },
  { key = "spiritWeapons", name = "Spirit Weapons" },
}

local byName = {}
for _, k in ipairs(M.KEYS) do byName[k.name] = k.key end

function M.read(numTabs, numTalents, info)
  local out = {}
  for _, k in ipairs(M.KEYS) do out[k.key] = 0 end
  for tab = 1, numTabs() or 0 do
    for i = 1, numTalents(tab) or 0 do
      local name, _, _, _, rank = info(tab, i)
      local key = name and byName[name]
      if key then out[key] = rank or 0 end
    end
  end
  return out
end

-- A typical leveling enhancement path (3.3.5a), one point per level from 10: key and ranks
-- in the order they are taken; "_" = a point in a talent the model does not read.
-- Enhancement tiers unlock every 5 points: Stormstrike is the 31st point (level 40), Dual Wield
-- level 41, Lava Lash 45, Shamanistic Rage 50, Maelstrom Weapon 5/5 at 59, Feral Spirit 60.
M.STANDARD = {
  { "enhancingTotems", 3 }, { "ancestralKnowledge", 2 },
  { "thunderingStrikes", 5 },
  { "elementalWeapons", 3 }, { "shamanisticFocus", 1 }, { "improvedShields", 1 },
  { "flurry", 5 },
  { "spiritWeapons", 1 }, { "improvedShields", 2 }, { "_", 2 },
  { "weaponMastery", 3 }, { "unleashedRage", 2 },
  { "stormstrike", 1 }, { "dualWield", 1 }, { "dualWieldSpecialization", 3 },
  { "lavaLash", 1 }, { "staticShock", 3 }, { "improvedStormstrike", 1 },
  { "shamanisticRage", 1 }, { "mentalQuickness", 3 }, { "improvedStormstrike", 1 },
  { "maelstromWeapon", 5 },
  { "feralSpirit", 1 },
  { "concussion", 5 }, { "callOfFlame", 3 }, { "convection", 5 }, { "elementalDevastation", 3 },
  { "mentalDexterity", 3 }, { "_", 2 },
}

function M.standard(level)
  local out = {}
  for _, k in ipairs(M.KEYS) do out[k.key] = 0 end
  local points = math.max(0, math.min(71, (level or 0) - 9))
  for _, pick in ipairs(M.STANDARD) do
    local key, ranks = pick[1], pick[2]
    for _ = 1, ranks do
      if points <= 0 then return out end
      points = points - 1
      if key ~= "_" then out[key] = out[key] + 1 end
    end
  end
  return out
end

return M
