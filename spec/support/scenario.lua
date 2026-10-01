local spells = require("spells")
local data = require("spells_data")
local talents = require("talents")

local Sc = {}

-- уровни, на которых становятся доступны заклинания без рангов в spells_data
Sc.LEVEL = { stormstrike = 40, lavaLash = 45, shamanisticRage = 50, feralSpirit = 60, callOfElements = 30, fireElemental = 68 }
Sc.COST_PCT = { lightningBolt = 10, chainLightning = 26, earthShock = 18, flameShock = 17, frostShock = 18, lavaLash = 4,
                stormstrike = 8, fireNova = 22, magmaTotem = 27, searingTotem = 7, fireElemental = 23, feralSpirit = 12,
                callOfElements = 30, lightningShield = 0, shamanisticRage = 0 }
Sc.BASE_MANA = { { 1, 55 }, { 10, 185 }, { 20, 410 }, { 30, 635 }, { 40, 860 }, { 50, 1085 }, { 60, 1520 }, { 70, 2678 }, { 80, 4396 } }
Sc.HP = { { 1, 42 }, { 10, 200 }, { 20, 600 }, { 30, 1200 }, { 40, 2000 }, { 50, 3500 }, { 60, 4500 }, { 70, 7000 }, { 80, 12000 } }
-- typical gear by level (level 80 = the wowsims reference: 4000 AP, 1200 SP, 440-640 base 1H)
Sc.AP = { { 1, 20 }, { 10, 70 }, { 20, 180 }, { 30, 350 }, { 40, 600 }, { 50, 900 }, { 60, 1300 }, { 70, 2300 }, { 80, 4000 } }
Sc.SP = { { 1, 0 }, { 40, 30 }, { 50, 250 }, { 60, 420 }, { 70, 750 }, { 80, 1200 } } -- Mental Quickness from ~50
Sc.WEAPON_2H = { { 1, 6 }, { 10, 18 }, { 20, 40 }, { 30, 70 }, { 39, 100 } }            -- average base damage, 3.5 s
Sc.WEAPON_1H = { { 40, 50 }, { 50, 75 }, { 60, 110 }, { 70, 230 }, { 80, 540 } }         -- average base damage, 2.6 s
Sc.OPTS = {} -- the in-game search settings (search.BEAM, NODE_CAP, ...)

local function interp(t, x)
  if x <= t[1][1] then return t[1][2] end
  for i = 2, #t do
    if x <= t[i][1] then
      local a, b = t[i - 1], t[i]
      return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1])
    end
  end
  return t[#t][2]
end

function Sc.merge(dst, patch)
  for k, v in pairs(patch or {}) do
    if type(v) == "table" and type(dst[k]) == "table" then Sc.merge(dst[k], v) else dst[k] = v end
  end
  return dst
end

local function rankIndex(meta, id)
  for i, x in ipairs(meta.ranks) do if x == id then return i end end
  return 1
end

function Sc.knownAt(level)
  local out = {}
  for _, meta in ipairs(spells.CATALOG) do
    local ranks = data[meta.key]
    if Sc.LEVEL[meta.key] then
      if level >= Sc.LEVEL[meta.key] then out[meta.key] = { id = meta.ranks[1], rank = 1 } end
    elseif ranks then
      for i = #ranks, 1, -1 do
        if ranks[i].level <= level then
          out[meta.key] = { id = ranks[i].id, rank = rankIndex(meta, ranks[i].id) }
          break
        end
      end
    end
  end
  return out
end

local function castOf(key, rank)
  if key == "lightningBolt" then return ({ 1.5, 2.0 })[rank] or 2.5 end
  if key == "chainLightning" then return 2.0 end
  return 0
end

-- level 80: raid boss, WF/FT, big cooldowns on cd; below 80: solo trash mob of the same level
function Sc.state(level, patch)
  local baseMana = interp(Sc.BASE_MANA, level)
  local dual = level >= 40
  local mobHp = interp(Sc.HP, level)
  local S = {
    now = 100, gcdRemains = 0, castRemains = 0, latency = 0.15,
    gcd = level >= 80 and 1.5 / 1.15 or 1.5,
    mode = level >= 80 and "raid" or "solo",
    player = {
      level = level, mana = baseMana * 3.5 * 0.8, manaMax = baseMana * 3.5, baseMana = baseMana, hpPct = 1,
      ap = interp(Sc.AP, level), spNature = interp(Sc.SP, level), spFire = interp(Sc.SP, level),
      meleeCrit = 0.05 + level * 0.003, spellCrit = 0.05 + level * 0.002,
      meleeHit = level >= 80 and 0.08 or 0, spellHit = level >= 80 and 0.10 or 0,
      spellHaste = level >= 80 and 1.15 or 1.0, meleeHaste = level >= 80 and 1.2 or 1.0,
      moving = false, inCombat = true,
    },
    weapons = {},
    talents = (talents.standard and talents.standard(level)) or {},
    spells = {},
    buffs = { mw = { stacks = 0, remains = 0 }, ls = { charges = 0, remains = 0 }, flurry = { charges = 0, remains = 0 }, rage = 0, lust = 0, em = 0 },
    target = level >= 80
      and { exists = true, enemy = true, level = 83, isBoss = true, hp = 1e7, hpMax = 1e7, hpPct = 1, ttd = 180, range = "melee", fs = 0, ss = { charges = 0, remains = 0 }, guessed = false }
      or { exists = true, enemy = true, level = level, hp = mobHp, hpMax = mobHp, hpPct = 1, ttd = 20, range = "melee", fs = 0, ss = { charges = 0, remains = 0 }, guessed = false },
    totems = { fire = { kind = nil, remains = 0 }, water = { remains = 120 } },
    -- swing speeds are hasted (UnitAttackSpeed), weapon speeds are the base ones (UnitDamage, Windfury)
    swing = { attacking = true, mh = { next = 1.0, speed = (dual and 2.6 or 3.5) / (level >= 80 and 1.2 or 1.0) }, resetByInstant = {} },
    enemies = { melee = 1, nearby = 1 },
    inflight = {},
  }
  -- weapon min/max as UnitDamage returns them: base damage + AP/14 * speed, off hand halved
  local ap = S.player.ap / 14
  if dual then
    local w = interp(Sc.WEAPON_1H, level)
    local lo, hi = w * 0.815 + ap * 2.6, w * 1.185 + ap * 2.6
    S.weapons.mh = { speed = 2.6, min = lo, max = hi, enchant = "wf" }
    S.weapons.oh = { speed = 2.6, min = lo / 2, max = hi / 2, enchant = "ft" }
    S.swing.oh = { next = 0.5, speed = S.swing.mh.speed }
  else
    local w = interp(Sc.WEAPON_2H, level)
    S.weapons.mh = { speed = 3.5, twoHand = true, min = w * 0.815 + ap * 3.5, max = w * 1.185 + ap * 3.5,
                     enchant = level >= 30 and "wf" or (level >= 10 and "ft" or "rb") }
  end
  for key, k in pairs(Sc.knownAt(level)) do
    S.spells[key] = { id = k.id, rank = k.rank, cd = 0, cost = math.floor((Sc.COST_PCT[key] or 0) / 100 * baseMana), cast = castOf(key, k.rank) }
  end
  if S.spells.lightningShield then S.buffs.ls = { charges = 3, remains = 600 } end
  if level >= 80 then
    Sc.cd(S, { feralSpirit = 120, fireElemental = 300, shamanisticRage = 30 })
  end
  return Sc.merge(S, patch)
end

-- map: key -> cd; key "shock" sets the shared cooldown of all shocks
function Sc.cd(S, map)
  for key, v in pairs(map) do
    local keys = key == "shock" and { "earthShock", "flameShock", "frostShock" } or { key }
    for _, k in ipairs(keys) do
      if S.spells[k] then S.spells[k].cd = v end
    end
  end
  return S
end

local function lcg(seed)
  local s = seed
  return function() s = (s * 1103515245 + 12345) % 2147483648; return s / 2147483648 end
end
Sc.lcg = lcg

-- n random but realistic level-80 raid states (cooldowns, Flame Shock, Maelstrom stacks, swings,
-- GCD, sometimes 3 targets); the same seed gives the same states
function Sc.randomStates(n, seed)
  local rng = lcg(seed or 42)
  local out = {}
  for _ = 1, n do
    local S = Sc.state(80)
    S.totems.fire = { kind = rng() < 0.8 and "magma" or false, remains = rng() * 20 }
    S.target.fs = rng() < 0.7 and rng() * 18 or 0
    S.buffs.mw = { stacks = math.floor(rng() * 6), remains = 20 }
    for _, k in ipairs({ "stormstrike", "lavaLash", "fireNova" }) do S.spells[k].cd = rng() < 0.4 and 0 or rng() * 8 end
    Sc.cd(S, { shock = rng() < 0.4 and 0 or rng() * 6 })
    S.swing.mh.next = rng() * S.swing.mh.speed
    S.swing.oh.next = rng() * S.swing.oh.speed
    S.gcdRemains = rng() < 0.5 and 0 or rng() * 1.3
    if rng() < 0.3 then S.enemies = { melee = 3, nearby = 3 } end
    out[#out + 1] = S
  end
  return out
end

function Sc.best(S)
  -- lazy: search is only needed by the verification specs, not by the runtime spec
  return require("search").best(S, Sc.OPTS)
end

function Sc.first(S)
  local plan = Sc.best(S)
  local st = plan.steps[1]
  return st and st.key, st and st.at, plan
end

return Sc
