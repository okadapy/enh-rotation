local M = {}

-- Talents that change enhancement damage, costs or cooldowns. Matched by name, so tab and
-- position do not matter. `id` is the talent's rank-1 spell (3.3.5a): GetTalentInfo takes the
-- talent's name from that spell, so GetSpellInfo(id) gives the same text in the client's
-- language (see M.localNames). The English `name` is always matched too, as a fallback.
M.KEYS = {
  { key = "convection", id = 16039, name = "Convection" },
  { key = "concussion", id = 16035, name = "Concussion" },
  { key = "callOfFlame", id = 16038, name = "Call of Flame" },
  { key = "elementalDevastation", id = 30160, name = "Elemental Devastation" },
  { key = "reverberation", id = 16040, name = "Reverberation" },
  { key = "elementalFocus", id = 16164, name = "Elemental Focus" },
  { key = "elementalFury", id = 16089, name = "Elemental Fury" },
  { key = "improvedFireNova", id = 16086, name = "Improved Fire Nova" },
  { key = "elementalPrecision", id = 30672, name = "Elemental Precision" },
  { key = "stormEarthAndFire", id = 51483, name = "Storm, Earth and Fire" },
  { key = "enhancingTotems", id = 16259, name = "Enhancing Totems" },
  { key = "ancestralKnowledge", id = 17485, name = "Ancestral Knowledge" },
  { key = "thunderingStrikes", id = 16255, name = "Thundering Strikes" },
  { key = "improvedShields", id = 16261, name = "Improved Shields" },
  { key = "elementalWeapons", id = 16266, name = "Elemental Weapons" },
  { key = "shamanisticFocus", id = 43338, name = "Shamanistic Focus" },
  { key = "flurry", id = 16256, name = "Flurry" },
  { key = "weaponMastery", id = 29082, name = "Weapon Mastery" },
  { key = "dualWieldSpecialization", id = 30816, name = "Dual Wield Specialization" },
  { key = "dualWield", id = 30798, name = "Dual Wield" },
  { key = "stormstrike", id = 17364, name = "Stormstrike" },
  { key = "staticShock", id = 51525, name = "Static Shock" },
  { key = "lavaLash", id = 60103, name = "Lava Lash" },
  { key = "improvedStormstrike", id = 51521, name = "Improved Stormstrike" },
  { key = "mentalQuickness", id = 30812, name = "Mental Quickness" },
  { key = "mentalDexterity", id = 51883, name = "Mental Dexterity" },
  { key = "unleashedRage", id = 30802, name = "Unleashed Rage" },
  { key = "shamanisticRage", id = 30823, name = "Shamanistic Rage" },
  { key = "maelstromWeapon", id = 51528, name = "Maelstrom Weapon" },
  { key = "feralSpirit", id = 51533, name = "Feral Spirit" },
  { key = "spiritWeapons", id = 16268, name = "Spirit Weapons" },
}

local byName = {}
for _, k in ipairs(M.KEYS) do byName[k.name] = k.key end

-- localized name -> key, from a GetSpellInfo-like function (the caller passes the game's one)
function M.localNames(spellInfo)
  local out = {}
  for _, k in ipairs(M.KEYS) do
    local name = spellInfo(k.id)
    if name then out[name] = k.key end
  end
  return out
end

-- names: optional localized name -> key (M.localNames); the English names are the fallback
function M.read(numTabs, numTalents, info, names)
  local out = {}
  for _, k in ipairs(M.KEYS) do out[k.key] = 0 end
  for tab = 1, numTabs() or 0 do
    for i = 1, numTalents(tab) or 0 do
      local name, _, _, _, rank = info(tab, i)
      local key = name and (names and names[name] or byName[name])
      if key then out[key] = rank or 0 end
    end
  end
  return out
end

-- Points spent in all talents, known to M.KEYS or not, and how many talents the client listed
-- (0 while the talent data has not loaded yet).
function M.spent(numTabs, numTalents, info)
  local points, listed = 0, 0
  for tab = 1, numTabs() or 0 do
    for i = 1, numTalents(tab) or 0 do
      listed = listed + 1
      local _, _, _, _, rank = info(tab, i)
      points = points + (rank or 0)
    end
  end
  return points, listed
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
