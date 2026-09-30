local util = require("util")

local F = {}

-- level-80 defaults for S.spells (id = top rank, cost in mana, cast in seconds, cd remaining)
F.SPELLS80 = {
  stormstrike     = { id = 17364, rank = 1,  cd = 0, cost = 351, cast = 0 },
  lavaLash        = { id = 60103, rank = 1,  cd = 0, cost = 176, cast = 0 },
  earthShock      = { id = 49231, rank = 10, cd = 0, cost = 791, cast = 0 },
  flameShock      = { id = 49233, rank = 9,  cd = 0, cost = 747, cast = 0 },
  frostShock      = { id = 49236, rank = 7,  cd = 0, cost = 791, cast = 0 },
  lightningBolt   = { id = 49238, rank = 14, cd = 0, cost = 440, cast = 2.5 },
  chainLightning  = { id = 49271, rank = 8,  cd = 0, cost = 1143, cast = 2.0 },
  searingTotem    = { id = 58704, rank = 10, cd = 0, cost = 308, cast = 0 },
  magmaTotem      = { id = 58734, rank = 7,  cd = 0, cost = 1187, cast = 0 },
  fireNova        = { id = 61657, rank = 9,  cd = 0, cost = 967, cast = 0 },
  fireElemental   = { id = 2894,  rank = 1,  cd = 0, cost = 1011, cast = 0 },
  callOfElements  = { id = 66842, rank = 1,  cd = 0, cost = 0,   cast = 0 },
  lightningShield = { id = 49281, rank = 11, cd = 0, cost = 0,   cast = 0 },
  shamanisticRage = { id = 30823, rank = 1,  cd = 0, cost = 0,   cast = 0 },
  feralSpirit     = { id = 51533, rank = 1,  cd = 0, cost = 527, cast = 0 },
}

-- deep copy / deep merge shared with src (see src/util.lua)
F.copy = util.copy
F.merge = util.merge

-- Level-80 enhancement shaman (WF main hand, FT off hand) in a group on a single boss.
-- Optional fields that are nil by default: weapons.mh.twoHand, target.dead, target.armor.
-- totems.fire.kind = false (or nil) means "no fire totem"; deep merge cannot set nil, use false.
function F.state(patch)
  local S = {
    now = 100.0, gcdRemains = 0, castRemains = 0, gcd = 1.5, latency = 0.15, mode = "group",
    player = {
      level = 80, mana = 8000, manaMax = 10000, baseMana = 4396, hpPct = 1.0,
      ap = 4000, spNature = 1200, spFire = 1200, meleeCrit = 0.30, spellCrit = 0.20,
      meleeHit = 0.08, spellHit = 0.10, spellHaste = 1.10, meleeHaste = 1.25,
      moving = false, inCombat = true,
    },
    weapons = {
      mh = { speed = 2.6, min = 600, max = 900, enchant = "wf" },
      oh = { speed = 2.6, min = 600, max = 900, enchant = "ft" },
    },
    talents = {
      convection = 5, concussion = 5, callOfFlame = 3, elementalDevastation = 3,
      enhancingTotems = 3, ancestralKnowledge = 2, thunderingStrikes = 5, improvedShields = 3,
      elementalWeapons = 3, shamanisticFocus = 1, flurry = 5, weaponMastery = 3,
      dualWieldSpecialization = 3, dualWield = 1, stormstrike = 1, staticShock = 3,
      lavaLash = 1, improvedStormstrike = 2, mentalQuickness = 3, mentalDexterity = 3,
      unleashedRage = 2, shamanisticRage = 1, maelstromWeapon = 5, feralSpirit = 1,
      spiritWeapons = 1, improvedFireNova = 0, reverberation = 0, elementalFury = 0,
      elementalFocus = 0, elementalPrecision = 0, stormEarthAndFire = 0,
    },
    spells = F.copy(F.SPELLS80),
    buffs = {
      mw = { stacks = 0, remains = 0 }, ls = { charges = 3, remains = 600 },
      flurry = { charges = 0, remains = 0 }, rage = 0, lust = 0, em = 0,
    },
    target = {
      exists = true, enemy = true, level = 83, hp = 1e6, hpMax = 1e6, hpPct = 1.0, ttd = 60,
      range = "melee", fs = 10, ss = { charges = 0, remains = 0 }, guessed = false,
    },
    totems = { fire = { kind = "magma", remains = 15 }, water = { remains = 200 } },
    swing = {
      attacking = true,
      mh = { next = 1.2, speed = 2.6 }, oh = { next = 0.4, speed = 2.6 },
      resetByInstant = {},
    },
    enemies = { melee = 1, nearby = 1 },
    inflight = {},
    pets = { wolves = 0 },
  }
  return F.merge(S, patch or {})
end

-- keep only the listed spell keys in S.spells (for leveling scenarios)
function F.only(S, ...)
  local keep = {}
  for _, k in ipairs({ ... }) do keep[k] = S.spells[k] or F.copy(F.SPELLS80[k]) end
  S.spells = keep
  return S
end

return F
