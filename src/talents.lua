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

return M
