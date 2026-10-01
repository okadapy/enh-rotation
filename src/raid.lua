-- Raid debuffs on the target and what the group already gives (WotLK 3.3.5a) -> S.mods.
-- Categories and numbers: wowsims sim/core/debuffs.go. Within one category only the strongest
-- counts (two major armor debuffs do not add up); categories multiply. Matched by name: snapshot
-- turns these ids into the client's names (GetSpellInfo), so an id must give the name of the aura
-- on the unit, not the talent's (Ebon Plaguebringer puts "Ebon Plague" on the target). The talent
-- ranks behind a debuff are not in the aura: a raid takes them maxed, the maximum is assumed.
-- Improved Faerie Fire (+3% spell hit) cannot be told from plain Faerie Fire: armor only.
-- Buffs on the player (Strength of Earth, Horn of Winter, Totem of Wrath's spell power) are
-- already in the snapshot's stats: only what they do for value.SUPPORT is read here.
-- Addon only (tools/build.lua B.ADDON_SRC).
local M = {}

-- target debuffs, any caster: spell id -> key
M.DEBUFFS = {
  [7386] = "sunder", [8647] = "expose", [55749] = "acidSpit",
  [770] = "faerieFire", [16857] = "faerieFireFeral", [56631] = "sting", [702] = "curseOfWeakness",
  [53598] = "sporeCloud",
  [1490] = "elements", [51726] = "ebonPlague", [60431] = "earthAndMoon",
  [30708] = "totemOfWrath", [21183] = "heartOfTheCrusader", [58410] = "masterPoisoner",
  [30069] = "bloodFrenzy", [58683] = "savageCombat",
  [22959] = "improvedScorch", [12579] = "wintersChill", [17800] = "shadowMastery",
  [33198] = "misery",
}
-- key -> { category, amount, stacks: amount per stack up to this many (nil: flat) }
M.EFFECT = {
  sunder = { "armorMajor", 0.04, 5 }, expose = { "armorMajor", 0.20 }, acidSpit = { "armorMajor", 0.10, 2 },
  faerieFire = { "armorMinor", 0.05 }, faerieFireFeral = { "armorMinor", 0.05 }, sting = { "armorMinor", 0.05 },
  curseOfWeakness = { "armorMinor", 0.05 }, sporeCloud = { "armorMinor", 0.03 },
  elements = { "spell", 0.13 }, ebonPlague = { "spell", 0.13 }, earthAndMoon = { "spell", 0.13 },
  totemOfWrath = { "crit", 0.03 }, heartOfTheCrusader = { "crit", 0.03 }, masterPoisoner = { "crit", 0.03 },
  bloodFrenzy = { "phys", 0.04 }, savageCombat = { "phys", 0.04 },
  improvedScorch = { "spellCrit", 0.05 }, wintersChill = { "spellCrit", 0.01, 5 }, shadowMastery = { "spellCrit", 0.05 },
  misery = { "spellHit", 0.03 },
}
-- buffs on the player that do what our own support totems do (any caster)
M.BUFFS = { [57330] = "hornOfWinter", [8076] = "strengthOfEarth", [8512] = "windfuryTotem", [55610] = "icyTalons" }
-- our own earth and air totems (GetTotemInfo names): while ours stands, its buff on us is ours
M.OWN_TOTEMS = { [8075] = "strength", [8512] = "haste" }
-- value.SUPPORT (0.06 of auto-attack damage) split by what each totem gives: Windfury Totem's 20%
-- melee haste is ~16.7% more auto-attack damage, Strength of Earth's 155 strength and agility
-- ~310 AP and ~1.9% crit, about 8-9% at 4000 AP: about 2 : 1
M.SUPPORT = { haste = 0.04, strength = 0.02 }

-- an aura without a count (UnitDebuff gives 0 for unstacked ones) is one stack
local function stacks(a, max)
  local n = a.count or 0
  if n < 1 then n = 1 end
  if n > max then n = max end
  return n
end

-- found: the target's debuffs (snapshot.auras: key -> { count, remains }); buffs: the player's;
-- own: { earth = kind, air = kind } of our own totems (M.OWN_TOTEMS kinds, "other" or nil);
-- gearMods: gear.effects, copied in. nil when nothing applies: the engine runs as without it.
function M.effects(found, buffs, own, gearMods)
  local best = {}
  for key, a in pairs(found or {}) do
    local e = M.EFFECT[key]
    if e then
      local v = e[3] and e[2] * stacks(a, e[3]) or e[2]
      if v > (best[e[1]] or 0) then best[e[1]] = v end
    end
  end
  local mods
  local function set(k, v)
    mods = mods or {}
    mods[k] = v
  end
  if best.armorMajor or best.armorMinor then set("armor", (1 - (best.armorMajor or 0)) * (1 - (best.armorMinor or 0))) end
  if best.spell then set("spellTaken", 1 + best.spell) end
  if best.phys then set("physTaken", 1 + best.phys) end
  if best.crit then set("critTaken", best.crit) end
  if best.spellCrit then set("spellCritTaken", best.spellCrit) end
  if best.spellHit then set("spellHitTaken", best.spellHit) end
  buffs, own = buffs or {}, own or {}
  -- another shaman's totem buff is the same aura as ours: it covers ours only while ours is not up
  local haste = buffs.icyTalons ~= nil or (buffs.windfuryTotem ~= nil and own.air ~= "haste")
  local strength = buffs.hornOfWinter ~= nil or (buffs.strengthOfEarth ~= nil and own.earth ~= "strength")
  if haste or strength then set("support", (haste and 0 or M.SUPPORT.haste) + (strength and 0 or M.SUPPORT.strength)) end
  for k, v in pairs(gearMods or {}) do set(k, v) end
  return mods
end

return M
