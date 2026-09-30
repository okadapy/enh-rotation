-- Expected (average) damage of enhancement shaman actions against one target.
-- Weapon min/max are UnitDamage values: attack power, off-hand penalty and percent
-- modifiers are already inside, so talents like Weapon Mastery are not applied again.
local spells = require("spells")
local util = require("util")

local M = {}

M.BOSS_ARMOR = 10643
M.ARMOR_POINTS = { { 1, 20 }, { 20, 600 }, { 40, 1600 }, { 60, 3200 }, { 70, 6000 }, { 80, 9700 }, { 83, 10643 } }
-- Windfury Weapon rank (by learn level) -> attack power bonus
M.WF_AP = { { 80, 1250 }, { 76, 1090 }, { 71, 835 }, { 68, 445 }, { 60, 333 }, { 50, 249 }, { 40, 119 }, { 30, 46 } }
-- approx: Flametongue fire damage per 1.0 weapon speed, by rank learn level
M.FT_PER_SPEED = { { 80, 52 }, { 76, 45 }, { 71, 40 }, { 64, 35.5 }, { 56, 24 }, { 46, 17 }, { 36, 11 }, { 26, 7 }, { 18, 4.5 }, { 10, 2.5 } }
M.EW_WF = { 0.13, 0.27, 0.40 }
M.EW_FT = { 0.10, 0.20, 0.30 }
M.WF_CHANCE, M.WF_ICD = 0.2, 3
M.CL_FALLOFF = { 1, 0.7, 0.49 }
M.MAGMA_PERIOD = spells.byKey.magmaTotem.period or 2
M.SEARING_PERIOD = spells.byKey.searingTotem.period or 2.5 -- approx
M.FE_BASE_DPS, M.FE_SP = 200, 0.5 -- approx
M.WOLF_BASE, M.WOLF_AP, M.WOLF_SPEED = 120, 0.31, 1.5 -- approx

local SCHOOL = {
  earthShock = "nature", lightningBolt = "nature", chainLightning = "nature", lightningShield = "nature",
  flameShock = "fire", fireNova = "fire", magmaTotem = "fire", searingTotem = "fire", frostShock = "frost",
}
local CONCUSSION = { earthShock = true, flameShock = true, frostShock = true, lightningBolt = true, chainLightning = true }
local CALL_OF_FLAME = { searingTotem = true, magmaTotem = true, fireNova = true, fireElemental = true }
local NATURE_SS = { earthShock = true, lightningBolt = true, chainLightning = true, lightningShield = true }
local DIRECT = { earthShock = true, frostShock = true, lightningBolt = true, flameShock = true }

local function talent(S, k) return (S.talents and S.talents[k]) or 0 end

-- unknown level (-1, bosses) counts as +3
local function lvlDiff(S)
  local tl = S.target and S.target.level
  if not tl or tl < 0 then tl = S.player.level + 3 end
  return tl - S.player.level
end

local function byLevel(tbl, level)
  for _, p in ipairs(tbl) do
    if level >= p[1] then return p[2] end
  end
  return 0
end

function M.row(S, key)
  local sp = S.spells and S.spells[key]
  if not sp then return nil end
  return spells.rank(key, sp.id)
end

function M.spellHit(S)
  local d = lvlDiff(S)
  local miss
  if d >= 3 then miss = 0.17
  elseif d <= 0 then miss = math.max(0.01, 0.04 + 0.01 * d)
  else miss = 0.04 + 0.01 * d end
  return 1 - math.max(0, miss - (S.player.spellHit or 0))
end

function M.spellCritFactor(S)
  local mult = 1.5 + 0.1 * talent(S, "elementalFury")
  return 1 + util.clamp(S.player.spellCrit or 0, 0, 1) * (mult - 1)
end

function M.spellMult(S, key)
  local m = 1
  if CONCUSSION[key] then m = m * (1 + 0.01 * talent(S, "concussion")) end
  if CALL_OF_FLAME[key] then m = m * (1 + 0.05 * talent(S, "callOfFlame")) end
  if key == "fireNova" then m = m * (1 + 0.1 * talent(S, "improvedFireNova")) end
  if key == "lightningShield" then m = m * (1 + 0.05 * talent(S, "improvedShields")) end
  local ss = S.target and S.target.ss
  if NATURE_SS[key] and ss and (ss.charges or 0) > 0 then m = m * 1.2 end
  return m
end

local function spellPower(S, school)
  if school == "nature" then return S.player.spNature or 0 end
  return S.player.spFire or 0
end

local function spellDamage(S, key, row)
  if not row then return 0 end
  local base = (row.min + row.max) / 2 + (row.coef or 0) * spellPower(S, SCHOOL[key])
  return base * M.spellMult(S, key) * M.spellHit(S) * M.spellCritFactor(S)
end

function M.targetArmor(level)
  if not level or level < 0 or level >= 83 then return M.BOSS_ARMOR end
  local pts = M.ARMOR_POINTS
  if level <= pts[1][1] then return pts[1][2] end
  for i = 2, #pts do
    local a, b = pts[i - 1], pts[i]
    if level <= b[1] then
      return a[2] + (b[2] - a[2]) * (level - a[1]) / (b[1] - a[1])
    end
  end
  return M.BOSS_ARMOR
end

function M.armorMult(S)
  local armor = S.target.armor or M.targetArmor(S.target.level)
  local L = S.player.level
  local k
  if L >= 60 then k = 400 + 85 * (L + 4.5 * (L - 59)) else k = 400 + 85 * L end
  return 1 - armor / (armor + k)
end

-- level difference -> glancing chance, glancing damage reduction
local GLANCE = { [0] = { 0.10, 0.05 }, { 0.15, 0.05 }, { 0.20, 0.15 }, { 0.24, 0.25 } }

function M.meleeTable(S, white)
  local d = lvlDiff(S)
  local dp = math.max(d, 0)
  local miss = d >= 3 and 0.08 or (0.05 + 0.005 * dp)
  if white and S.weapons.oh then miss = miss + 0.19 end
  miss = math.max(0, miss - (S.player.meleeHit or 0))
  local dodge = 0.05 + 0.005 * dp
  local glance, glanceRed = 0, 0
  if white then
    local g = GLANCE[math.min(dp, 3)]
    glance, glanceRed = g[1], g[2]
  end
  local crit = math.max(0, (S.player.meleeCrit or 0) - (d >= 3 and 0.048 or 0.002 * dp))
  crit = math.min(crit, math.max(0, 1 - miss - dodge - glance))
  local hit = 1 - miss - dodge - glance - crit
  return { miss = miss, dodge = dodge, glance = glance, crit = crit,
           factor = hit + glance * (1 - glanceRed) + crit * 2, landed = 1 - miss - dodge }
end

local function avg(w) return (w.min + w.max) / 2 end

function M.white(S, hand)
  local w = S.weapons[hand]
  if not w then return 0 end
  return avg(w) * M.meleeTable(S, true).factor * M.armorMult(S)
end

-- UnitDamage already holds AP * speed / 14 (halved for the off hand); swap speed for 2.4 / 3.3
function M.normalized(S, hand)
  local w = S.weapons[hand]
  if not w then return 0 end
  local ap = (S.player.ap or 0) / 14
  local mult = hand == "oh" and 0.5 or 1
  local norm = w.twoHand and 3.3 or 2.4
  return avg(w) - ap * w.speed * mult + ap * norm * mult
end

function M.wf(S)
  local w = S.weapons.mh
  if not w or w.enchant ~= "wf" then return 0, 0 end
  local ew = talent(S, "elementalWeapons")
  local bonus = byLevel(M.WF_AP, S.player.level) * (1 + (M.EW_WF[ew] or 0))
  local procs = M.WF_CHANCE / (1 + M.WF_CHANCE * math.floor(M.WF_ICD / w.speed))
  local attack = (avg(w) + bonus / 14 * w.speed) * M.meleeTable(S, false).factor * M.armorMult(S)
  return procs * 2 * attack, procs
end

function M.ftHit(S, hand)
  local w = S.weapons[hand]
  if not w or w.enchant ~= "ft" then return 0 end
  local ew = talent(S, "elementalWeapons")
  local base = byLevel(M.FT_PER_SPEED, S.player.level) * w.speed * (1 + (M.EW_FT[ew] or 0))
  local dmg = base + 0.1 * w.speed / 2.6 * (S.player.spFire or 0)
  return dmg * M.spellHit(S) * M.spellCritFactor(S)
end

function M.staticHit(S)
  local r = talent(S, "staticShock")
  local ls = S.buffs and S.buffs.ls
  if r == 0 or not ls or (ls.charges or 0) <= 0 then return 0 end
  return 0.02 * r * spellDamage(S, "lightningShield", M.row(S, "lightningShield"))
end

local function procsPerHit(S, hand) return M.ftHit(S, hand) + M.staticHit(S) end

function M.auto(S, hand)
  local w = S.weapons[hand]
  if not w then return 0 end
  local white = M.meleeTable(S, true)
  local dmg = M.white(S, hand) + procsPerHit(S, hand) * white.landed
  if hand == "mh" then
    local wfDmg, procs = M.wf(S)
    dmg = dmg + wfDmg + procs * 2 * procsPerHit(S, "mh") * M.meleeTable(S, false).landed
  end
  return dmg
end

-- Maelstrom Weapon: 2 PPM per talent rank
local function mwChance(S, hand)
  local r = talent(S, "maelstromWeapon")
  local w = S.weapons[hand]
  if r == 0 or not w then return 0 end
  return math.min(1, 2 * r * w.speed / 60)
end

function M.mwPerHit(S, hand)
  return mwChance(S, hand) * M.meleeTable(S, false).landed
end

function M.mwPerSwing(S, hand)
  local c = mwChance(S, hand)
  if c == 0 then return 0 end
  local stacks = c * M.meleeTable(S, true).landed
  if hand == "mh" then
    local _, procs = M.wf(S)
    stacks = stacks + procs * 2 * c * M.meleeTable(S, false).landed
  end
  return stacks
end

-- Fire Nova and Magma Totem hit around the fire totem (10 and 8 yards), and totems are dropped
-- at the shaman's feet. The combat log gives no positions, only who fights whom (enemies.lua):
-- * target in melee: the fight is around the shaman, so every enemy in the fight counts (nearby;
--   in a group the pack is on the tank, not hitting the shaman, so `melee` would miss it);
-- * target not in melee: the fight is at range, only enemies hitting the shaman in melee (within
--   5 yards) stand in reach; 0 = the totem hits nothing.
-- Depends only on target range and enemy counts, which stay the same inside one search (memo).
function M.totemTargets(S)
  local e, t = S.enemies, S.target
  if t and t.exists and t.enemy and t.range == "melee" then
    local n = e and e.nearby or 1
    return n > 1 and n or 1
  end
  return e and e.melee or 0
end

function M.targets(S, key)
  if key == "fireNova" or key == "magmaTotem" then return M.totemTargets(S) end
  local n = math.max(1, (S.enemies and S.enemies.nearby) or 1)
  if key == "chainLightning" then return math.min(n, 3) end
  return 1
end

-- perPulse (one target), pulses, period. Flame Shock ticks cannot miss once applied.
function M.dot(S, key)
  local row = M.row(S, key)
  if key == "flameShock" then
    if not row or not row.tick then return 0, 0, 1 end
    local per = (row.tick + (row.tickCoef or 0) * spellPower(S, SCHOOL[key])) * M.spellMult(S, key) * M.spellCritFactor(S)
    return per, row.ticks or 0, row.period or 3
  elseif key == "magmaTotem" or key == "searingTotem" then
    if not row then return 0, 0, 1 end
    local period = key == "magmaTotem" and M.MAGMA_PERIOD or M.SEARING_PERIOD
    local duration = spells.byKey[key].duration or 0
    return spellDamage(S, key, row), math.floor(duration / period + 1e-9), period
  end
  return 0, 0, 1
end

function M.periodic(S, source)
  if source == "flameShock" or source == "searingTotem" then
    local per, _, period = M.dot(S, source)
    return per / period
  elseif source == "magmaTotem" then
    local per, _, period = M.dot(S, source)
    return per * M.targets(S, "magmaTotem") / period
  elseif source == "fireElemental" then
    return (M.FE_BASE_DPS + M.FE_SP * (S.player.spFire or 0)) * (1 + 0.05 * talent(S, "callOfFlame"))
  elseif source == "feralSpirit" then
    local perHit = M.WOLF_BASE + M.WOLF_AP * (S.player.ap or 0) / 14 * M.WOLF_SPEED
    return 2 * perHit / M.WOLF_SPEED * M.armorMult(S)
  end
  return 0
end

-- instant part only; ticks, totem pulses and pets are added by model.advance
function M.action(S, key)
  if not (S.spells and S.spells[key]) then return 0 end
  if DIRECT[key] then return spellDamage(S, key, M.row(S, key)) end
  if key == "chainLightning" then
    local single = spellDamage(S, key, M.row(S, key))
    local total = 0
    for i = 1, M.targets(S, key) do total = total + single * M.CL_FALLOFF[i] end
    return total
  end
  if key == "fireNova" then
    return spellDamage(S, key, M.row(S, key)) * M.targets(S, key)
  end
  if key == "stormstrike" then
    local y = M.meleeTable(S, false)
    local w = M.normalized(S, "mh") + M.normalized(S, "oh")
    local procs = procsPerHit(S, "mh") * y.landed
    if S.weapons.oh then procs = procs + procsPerHit(S, "oh") * y.landed end
    return w * y.factor * M.armorMult(S) + procs
  end
  if key == "lavaLash" then
    local oh = S.weapons.oh
    if not oh then return 0 end
    local y = M.meleeTable(S, false)
    local bonus = oh.enchant == "ft" and 1.25 or 1
    return M.normalized(S, "oh") * bonus * y.factor + procsPerHit(S, "oh") * y.landed
  end
  return 0
end

-- Per-search memo. search.best puts a fresh S.memo on its root state; model.clone shares it
-- along the whole tree. Inside one search player stats, weapons, talents, target level and
-- enemy counts never change, so these results depend only on their argument and on whether
-- Lightning Shield charges (Static Shock) and Stormstrike charges (+20% nature) are up.
-- Without S.memo (direct calls, tests) everything is computed as before.
-- memo[name][arg] for results that depend only on the argument
local function memoize(name)
  local raw = M[name]
  M[name] = function(S, a)
    local m = S.memo
    if not m then return raw(S, a) end
    local slot = m[name]
    if not slot then slot = {}; m[name] = slot end
    local k = a
    if k == nil then k = 0 end
    local v = slot[k]
    if v == nil then v = raw(S, a); slot[k] = v end
    return v
  end
end

-- memo[name][flags][arg]: flags = Lightning Shield charges up (+1), Stormstrike charges up (+2)
local function memoizeFlags(name)
  local raw = M[name]
  M[name] = function(S, a)
    local m = S.memo
    if not m then return raw(S, a) end
    local f = 1
    local ls, ss = S.buffs.ls, S.target.ss
    if ls and ls.charges and ls.charges > 0 then f = 2 end
    if ss and ss.charges and ss.charges > 0 then f = f + 2 end
    local slot = m[name]
    if not slot then slot = {}; m[name] = slot end
    local sub = slot[f]
    if not sub then sub = {}; slot[f] = sub end
    local v = sub[a]
    if v == nil then v = raw(S, a); sub[a] = v end
    return v
  end
end

-- the per-buff table memoizeFlags("action") fills, for callers that look up several actions
function M.actionTable(S)
  local m = S.memo
  if not m then return nil end
  local f = 1
  local ls, ss = S.buffs.ls, S.target.ss
  if ls and ls.charges and ls.charges > 0 then f = 2 end
  if ss and ss.charges and ss.charges > 0 then f = f + 2 end
  local slot = m.action
  if not slot then slot = {}; m.action = slot end
  local sub = slot[f]
  if not sub then sub = {}; slot[f] = sub end
  return sub
end

memoize("armorMult")
memoize("meleeTable")
memoize("mwPerHit")
memoize("mwPerSwing")
memoize("periodic")
memoizeFlags("auto")
memoizeFlags("action")

-- continuous dps of every periodic source at once (model.advance needs several per step)
M.PERIODIC = { "flameShock", "searingTotem", "magmaTotem", "fireElemental", "feralSpirit" }
function M.rates(S)
  local m = S.memo
  local r = m and m.rates
  if r then return r end
  r = {}
  for _, src in ipairs(M.PERIODIC) do r[src] = M.periodic(S, src) end
  if m then m.rates = r end
  return r
end

-- expected damage and Maelstrom stacks of one auto attack per hand, for S's buffs
function M.swingStats(S)
  local m = S.memo
  local f = 1
  if m then
    local ls, ss = S.buffs.ls, S.target.ss
    if ls and ls.charges and ls.charges > 0 then f = 2 end
    if ss and ss.charges and ss.charges > 0 then f = f + 2 end
    local slot = m.swingStats
    local r = slot and slot[f]
    if r then return r end
  end
  local r = { mh = M.auto(S, "mh"), oh = M.auto(S, "oh"), mwmh = M.mwPerSwing(S, "mh"), mwoh = M.mwPerSwing(S, "oh") }
  if m then
    m.swingStats = m.swingStats or {}
    m.swingStats[f] = r
  end
  return r
end

local rawWf = M.wf
function M.wf(S)
  local m = S.memo
  if not m then return rawWf(S) end
  local v = m.wf
  if not v then v = { rawWf(S) }; m.wf = v end
  return v[1], v[2]
end

return M
