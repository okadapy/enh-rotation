-- State transition model: what pressing an action or waiting does to S.
-- Pure: never mutates the input S (works on util.copy).
local spells = require("spells")
local damage = require("damage")
local util = require("util")

local M = {}

local function duration(key, default) return (spells.byKey[key] and spells.byKey[key].duration) or default end

M.HORIZON = 6.0
M.MW_DURATION = 30
M.SS_CHARGES = (spells.byKey.stormstrike and spells.byKey.stormstrike.charges) or 4
M.SS_DURATION = duration("stormstrike", 12)
M.TOTEM_KIND = { searingTotem = "searing", magmaTotem = "magma", fireElemental = "fireElemental" }
M.TOTEM_DURATION = {
  searingTotem = duration("searingTotem", 60),
  magmaTotem = duration("magmaTotem", 20),
  fireElemental = duration("fireElemental", 120),
}
-- totems.fire.kind -> damage.periodic source ("other" = foreign totem, no damage counted)
M.FIRE_SOURCE = { searing = "searingTotem", magma = "magmaTotem", fireElemental = "fireElemental" }
local FIRE_SOURCE = M.FIRE_SOURCE
M.WATER_DURATION = 300
M.WOLVES_DURATION = duration("feralSpirit", 45)
M.RAGE_DURATION = duration("shamanisticRage", 15)
M.RAGE_MANA_AP = damage.RAGE_MANA_AP
-- Long cooldowns the player gates in the options (S.cooldowns[key]; nil = "always", the old
-- behaviour). "auto" allows one on a boss, or on a target expected to live at least this long:
-- half of what the cooldown summons or buffs (wolves 45 s, Fire Elemental 120 s, Rage 15 s).
-- A mob that dies sooner gets less than half of it, and a 3 or 10 minute cooldown spent there is
-- missing on the next pull or the boss. Unknown ttd off a boss: not allowed (a trash pull in a
-- group has none until it has taken damage for a while). The number of enemies does not count:
-- a trash pack dies together, so more mobs do not make the fight longer.
M.COOLDOWN_TTD = {
  feralSpirit = M.WOLVES_DURATION / 2,
  fireElemental = M.TOTEM_DURATION.fireElemental / 2,
  shamanisticRage = M.RAGE_DURATION / 2,
}
-- "auto" is decided once per snapshot (snapshot.cooldownGate -> S.cdAllowed), with a latch per
-- target: allowed at ttd >= need, it stays allowed on that target until ttd < need x RELEASE. A
-- noisy estimate around the line (24, 21, 23, ...) flipped the first button on every update, and
-- a gate read along the plan (ttd counts down) allowed a cooldown early in the plan only.
M.COOLDOWN_RELEASE = 0.75
M.LS_DURATION = duration("lightningShield", 600)
M.INFLIGHT = 1.0
M.TOTEM_REDROP = 12 -- = value.TAIL: remaining totem time past this is not valued
M.COE_WATER = 20 -- wowsims: Call of the Elements when the water totem has less than 20 s
M.WAIT_SWING_PAD = 0.01
M.CAST_SPELLS = { lightningBolt = true, chainLightning = true }
M.NATURE_CONSUME = { earthShock = true, lightningBolt = true, chainLightning = true }
M.NEEDS_TARGET = { stormstrike = true, lavaLash = true, earthShock = true, flameShock = true,
                   frostShock = true, lightningBolt = true, chainLightning = true }
M.MELEE_ONLY = { stormstrike = true, lavaLash = true }
M.SHOCK_RANGE = { earthShock = true, flameShock = true, frostShock = true }
M.HANDS = { "mh", "oh" }
-- A hostile NPC at "20"/"30" that fights the shaman runs to him (S.target.meleeIn: seconds until
-- melee, counted down by advance; nil = the range stays as it is). The snapshot sets it for a
-- target already in combat; pressing a spell on a target at range pulls it (applyOn).
M.BAND20_ETA = util.approachEta("20") -- a target running in from "30" is within 20 yards this long before melee

-- hot-path locals (the tables are the module's own, never replaced)
local byKey = spells.byKey
local NEEDS_TARGET, MELEE_ONLY, SHOCK_RANGE = M.NEEDS_TARGET, M.MELEE_ONLY, M.SHOCK_RANGE
local TOTEM_KIND, CAST_SPELLS, HORIZON = M.TOTEM_KIND, M.CAST_SPELLS, M.HORIZON

M.copy = util.copy

local function shallow(t)
  if not t then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = v end
  return r
end

-- Working copy for one transition, built with table constructors (no rehashing).
-- Shared, read-only in model: player (copy-on-write, see setMana), weapons, talents, enemies,
-- swing.resetByInstant, the per-search memo. S.spells entries are copy-on-write (setCd).
-- Only contract fields are carried over; the copy lives inside model/search only.
local function hand(h) return h and { next = h.next, speed = h.speed } end

-- one constructor for every spells.CATALOG key (a test checks the list stays complete)
local function spellMap(sp)
  return {
    stormstrike = sp.stormstrike, lavaLash = sp.lavaLash, earthShock = sp.earthShock, flameShock = sp.flameShock,
    frostShock = sp.frostShock, lightningBolt = sp.lightningBolt, chainLightning = sp.chainLightning,
    searingTotem = sp.searingTotem, magmaTotem = sp.magmaTotem, fireNova = sp.fireNova,
    fireElemental = sp.fireElemental, callOfElements = sp.callOfElements, lightningShield = sp.lightningShield,
    shamanisticRage = sp.shamanisticRage, feralSpirit = sp.feralSpirit,
  }
end
M.spellMap = spellMap
local spells_keys = spells.KEYS

-- keys of S.spells as an array; model never adds or removes spells, so one list per search
local function spellKeys(S)
  local m = S.memo
  local keys = m and m.spellKeys
  if keys then return keys end
  keys = {}
  for _, key in ipairs(spells_keys) do
    if S.spells[key] then keys[#keys + 1] = key end
  end
  if m then m.spellKeys = keys end
  return keys
end
M.spellKeys = spellKeys

-- Arena (search: S.memo.arena, model.newArena / model.release): the real states of one search,
-- their spell entries and their player tables are taken from free lists instead of allocated,
-- and all of them go back when the search ends. Nothing a search returns holds them, and a
-- scratch buffer re-reads everything when the memo changes (fillScratch: fresh). Without an
-- arena (direct calls, tests, search.evaluate) everything is allocated as before.
local FREE_STATE, FREE_ENTRY, FREE_PLAYER, FREE_ARENA = {}, {}, {}, {}
local nFreeState, nFreeEntry, nFreePlayer, nFreeArena = 0, 0, 0, 0

function M.newArena()
  if nFreeArena > 0 then
    local a = FREE_ARENA[nFreeArena]
    FREE_ARENA[nFreeArena] = nil
    nFreeArena = nFreeArena - 1
    return a
  end
  return { states = {}, nStates = 0, entries = {}, nEntries = 0, players = {}, nPlayers = 0 }
end

-- every table the arena handed out goes back to the free lists (the search that took them is over)
function M.release(a)
  if not a then return end
  local list = a.states
  for i = 1, a.nStates do nFreeState = nFreeState + 1; FREE_STATE[nFreeState] = list[i]; list[i] = nil end
  list = a.entries
  for i = 1, a.nEntries do nFreeEntry = nFreeEntry + 1; FREE_ENTRY[nFreeEntry] = list[i]; list[i] = nil end
  list = a.players
  for i = 1, a.nPlayers do nFreePlayer = nFreePlayer + 1; FREE_PLAYER[nFreePlayer] = list[i]; list[i] = nil end
  a.nStates, a.nEntries, a.nPlayers = 0, 0, 0
  nFreeArena = nFreeArena + 1
  FREE_ARENA[nFreeArena] = a
end

-- a spell entry: from the arena of S's search, or a new table
local function newEntry(memo, sp, cd)
  local a = memo and memo.arena
  if not a then return { id = sp.id, rank = sp.rank, cd = cd, cost = sp.cost, cast = sp.cast } end
  local e
  if nFreeEntry > 0 then
    e = FREE_ENTRY[nFreeEntry]
    FREE_ENTRY[nFreeEntry] = nil
    nFreeEntry = nFreeEntry - 1
  else
    e = {}
  end
  e.id, e.rank, e.cd, e.cost, e.cast = sp.id, sp.rank, cd, sp.cost, sp.cast
  local k = a.nEntries + 1
  a.entries[k], a.nEntries = e, k
  return e
end

-- cooldowns after dt seconds: entries still on cooldown are replaced, the rest stay shared
local function tickSpells(S, map, dt)
  local keys = spellKeys(S)
  local memo = S.memo
  local a = memo and memo.arena
  for i = 1, #keys do
    local key = keys[i]
    local sp = map[key]
    local cd = sp.cd
    if cd and cd > 0 then
      cd = cd - dt
      if cd < 0 then cd = 0 end
      if a and nFreeEntry > 0 then -- newEntry(memo, sp, cd), inlined for a free entry (hot)
        local e = FREE_ENTRY[nFreeEntry]
        FREE_ENTRY[nFreeEntry] = nil
        nFreeEntry = nFreeEntry - 1
        e.id, e.rank, e.cd, e.cost, e.cast = sp.id, sp.rank, cd, sp.cost, sp.cast
        local k = a.nEntries + 1
        a.entries[k], a.nEntries = e, k
        map[key] = e
      else
        map[key] = newEntry(memo, sp, cd)
      end
    end
  end
  return map
end

local fillState
function M.clone(S, dt)
  local memo = S.memo
  local a = memo and memo.arena
  local n
  if a then
    if nFreeState > 0 then
      n = FREE_STATE[nFreeState]
      FREE_STATE[nFreeState] = nil
      nFreeState = nFreeState - 1
    else
      n = { spells = {}, inflight = {}, buffs = { mw = {}, ls = {} }, target = {}, totems = {}, swing = {},
            pool = { flurry = {}, ss = {}, fire = {}, water = {}, mh = {}, oh = {}, pets = {} } }
    end
    local k = a.nStates + 1
    a.states[k], a.nStates = n, k
    fillState(n, S)
  else
    n = M.cloneState(S)
  end
  if dt then tickSpells(S, n.spells, dt) end
  return n
end

function M.cloneState(S)
  local b, t, tot, sw = S.buffs, S.target, S.totems, S.swing
  local fire, water, ss, pets = tot.fire, tot.water, t.ss, S.pets
  return {
    now = S.now, gcdRemains = S.gcdRemains, castRemains = S.castRemains, gcd = S.gcd, latency = S.latency,
    mode = S.mode, shieldPref = S.shieldPref, player = S.player, weapons = S.weapons, talents = S.talents, enemies = S.enemies,
    cooldowns = S.cooldowns, cdAllowed = S.cdAllowed, weaveMin = S.weaveMin, memo = S.memo, spells = spellMap(S.spells), inflight = next(S.inflight or {}) and shallow(S.inflight) or {},
    buffs = { mw = { stacks = b.mw.stacks, remains = b.mw.remains },
              ls = { charges = b.ls.charges, remains = b.ls.remains },
              flurry = b.flurry and { charges = b.flurry.charges, remains = b.flurry.remains },
              rage = b.rage, lust = b.lust, em = b.em },
    target = { exists = t.exists, enemy = t.enemy, level = t.level, hp = t.hp, hpMax = t.hpMax, hpPct = t.hpPct,
               ttd = t.ttd, range = t.range, fs = t.fs, guessed = t.guessed, dead = t.dead, armor = t.armor,
               inCombat = t.inCombat, isPlayer = t.isPlayer, meleeIn = t.meleeIn, isBoss = t.isBoss,
               ss = ss and { charges = ss.charges, remains = ss.remains } },
    totems = { fire = fire and { kind = fire.kind, remains = fire.remains },
               water = water and { remains = water.remains } },
    swing = { attacking = sw.attacking, resetByInstant = sw.resetByInstant, mh = hand(sw.mh), oh = hand(sw.oh) },
    pets = pets and { wolves = pets.wolves },
  }
end

-- cloneState(S) written into an arena state n (M.clone): the same fields, n's own tables. A
-- field that can be missing takes n.pool's table when present (applyOn / advance use it too).
-- Keep it field for field with cloneState (spec/model_spec.lua compares them).
local function fillPair(d, s, a, b) d[a], d[b] = s[a], s[b]; return d end
function fillState(n, S)
  local b, t, tot, sw = S.buffs, S.target, S.totems, S.swing
  local fire, water, ss, pets = tot.fire, tot.water, t.ss, S.pets
  local pool = n.pool
  n.now, n.gcdRemains, n.castRemains, n.gcd, n.latency = S.now, S.gcdRemains, S.castRemains, S.gcd, S.latency
  n.mode, n.shieldPref, n.player, n.weapons, n.talents, n.enemies = S.mode, S.shieldPref, S.player, S.weapons, S.talents, S.enemies
  n.cooldowns, n.cdAllowed, n.weaveMin, n.memo = S.cooldowns, S.cdAllowed, S.weaveMin, S.memo
  local map, sp = n.spells, S.spells
  map.stormstrike, map.lavaLash, map.earthShock, map.flameShock = sp.stormstrike, sp.lavaLash, sp.earthShock, sp.flameShock
  map.frostShock, map.lightningBolt, map.chainLightning = sp.frostShock, sp.lightningBolt, sp.chainLightning
  map.searingTotem, map.magmaTotem, map.fireNova = sp.searingTotem, sp.magmaTotem, sp.fireNova
  map.fireElemental, map.callOfElements, map.lightningShield = sp.fireElemental, sp.callOfElements, sp.lightningShield
  map.shamanisticRage, map.feralSpirit = sp.shamanisticRage, sp.feralSpirit
  local inf = n.inflight
  if next(inf) then for k in pairs(inf) do inf[k] = nil end end
  local sinf = S.inflight
  if sinf then for k, v in pairs(sinf) do inf[k] = v end end
  local nb = n.buffs
  fillPair(nb.mw, b.mw, "stacks", "remains")
  fillPair(nb.ls, b.ls, "charges", "remains")
  nb.flurry = b.flurry and fillPair(pool.flurry, b.flurry, "charges", "remains") or nil
  nb.rage, nb.lust, nb.em = b.rage, b.lust, b.em
  local nt = n.target
  nt.exists, nt.enemy, nt.level, nt.hp, nt.hpMax, nt.hpPct = t.exists, t.enemy, t.level, t.hp, t.hpMax, t.hpPct
  nt.ttd, nt.range, nt.fs, nt.guessed, nt.dead, nt.armor = t.ttd, t.range, t.fs, t.guessed, t.dead, t.armor
  nt.inCombat, nt.isPlayer, nt.meleeIn, nt.isBoss = t.inCombat, t.isPlayer, t.meleeIn, t.isBoss
  nt.ss = ss and fillPair(pool.ss, ss, "charges", "remains") or nil
  local ntot = n.totems
  ntot.fire = fire and fillPair(pool.fire, fire, "kind", "remains") or nil
  if water then local w = pool.water; w.remains = water.remains; ntot.water = w else ntot.water = nil end
  local nsw = n.swing
  nsw.attacking, nsw.resetByInstant = sw.attacking, sw.resetByInstant
  nsw.mh = sw.mh and fillPair(pool.mh, sw.mh, "next", "speed") or nil
  nsw.oh = sw.oh and fillPair(pool.oh, sw.oh, "next", "speed") or nil
  if pets then local p = pool.pets; p.wolves = pets.wolves; n.pets = p else n.pets = nil end
  return n
end

local SPARE_PLAYER = {} -- the scratch buffers' own player tables (newScratch)

-- n.player is shared with the parent state: replace it before changing mana
local function setMana(n, mana)
  local p = n.player
  if p.mana == mana then return end
  if n.ownSpells then
    -- scratch state: its own player table, no allocation
    local o = n.playerOwn
    if not o then
      -- a scratch source may hold this buffer's own player (a chain of peeks back into this
      -- buffer): then the other one, so the source keeps its mana
      local spare = n.spare
      o = spare.player
      if o == p then o = spare.player2 end
      local from = n.playerFrom
      if from[o] ~= p then
        o.level, o.manaMax, o.baseMana, o.hpPct, o.ap = p.level, p.manaMax, p.baseMana, p.hpPct, p.ap
        o.spNature, o.spFire, o.meleeCrit, o.spellCrit = p.spNature, p.spFire, p.meleeCrit, p.spellCrit
        o.meleeHit, o.spellHit, o.spellHaste, o.meleeHaste = p.meleeHit, p.spellHit, p.spellHaste, p.meleeHaste
        o.moving, o.inCombat, o.shield = p.moving, p.inCombat, p.shield
        -- a search node's player is never modified (copy-on-write): the next copy of the same one
        -- (fillScratch forgets it with the search) only needs the mana; a scratch one is modified
        from[o] = not SPARE_PLAYER[p] and p or nil
      end
      n.player, n.playerOwn = o, o
    end
    o.mana = mana
    return
  end
  local memo = n.memo
  local a = memo and memo.arena
  if not a then
    n.player = {
      level = p.level, mana = mana, manaMax = p.manaMax, baseMana = p.baseMana, hpPct = p.hpPct, ap = p.ap,
      spNature = p.spNature, spFire = p.spFire, meleeCrit = p.meleeCrit, spellCrit = p.spellCrit,
      meleeHit = p.meleeHit, spellHit = p.spellHit, spellHaste = p.spellHaste, meleeHaste = p.meleeHaste,
      moving = p.moving, inCombat = p.inCombat, shield = p.shield,
    }
    return
  end
  -- the same fields as the constructor above, in a table of the search's arena
  local o
  if nFreePlayer > 0 then
    o = FREE_PLAYER[nFreePlayer]
    FREE_PLAYER[nFreePlayer] = nil
    nFreePlayer = nFreePlayer - 1
  else
    o = {}
  end
  o.level, o.mana, o.manaMax, o.baseMana, o.hpPct, o.ap = p.level, mana, p.manaMax, p.baseMana, p.hpPct, p.ap
  o.spNature, o.spFire, o.meleeCrit, o.spellCrit = p.spNature, p.spFire, p.meleeCrit, p.spellCrit
  o.meleeHit, o.spellHit, o.spellHaste, o.meleeHaste = p.meleeHit, p.spellHit, p.spellHaste, p.meleeHaste
  o.moving, o.inCombat, o.shield = p.moving, p.inCombat, p.shield
  local k = a.nPlayers + 1
  a.players[k], a.nPlayers = o, k
  n.player = o
end

-- replace n.spells[key] by a copy with the new cooldown (the old table may be shared)
local function setCd(n, key, cd)
  local sp = n.spells[key]
  if sp.cd == cd then return end
  if n.ownSpells then
    -- scratch state: its own entry for this key, filled from the (maybe shared) current one
    local e = n.spare.spells[key]
    if not e then e = {}; n.spare.spells[key] = e end
    if e ~= sp then
      e.id, e.rank, e.cost, e.cast = sp.id, sp.rank, sp.cost, sp.cast
      n.spells[key] = e
      local d = n.nDirty + 1 -- fillScratch puts the shared entry back
      n.dirty[d], n.nDirty = key, d
    end
    e.cd = cd
    return
  end
  n.spells[key] = newEntry(n.memo, sp, cd)
end

local function talent(S, k) return (S.talents and S.talents[k]) or 0 end
local function dec(x, dt)
  x = (x or 0) - dt
  if x < 0 then return 0 end
  return x
end

local function alive(S)
  local t = S.target
  return t and t.exists and t.enemy and not t.dead and true or false
end

-- Solo only: in a group a pulled mob runs to whoever holds its aggro (the tank), not to us.
-- Players are never taken to come: they kite and keep their distance.
function M.canApproach(S)
  local t = S.target
  return S.mode == "solo" and alive(S) and not t.isPlayer and util.approachEta(t.range) ~= nil
end

-- a fire totem stands (kind false/nil = none; "other" = someone else's or unknown totem)
local function fireUp(S)
  local fire = S.totems and S.totems.fire
  return fire and fire.kind and (fire.remains or 0) > 0 and true or false
end

function M.cooldownFor(S, key)
  local meta = spells.byKey[key]
  if meta.sharedCd == "shock" then return 6 - 0.2 * talent(S, "reverberation") end
  if key == "fireNova" then return 10 - 2 * talent(S, "improvedFireNova") end
  return meta.cd or 0
end

function M.gcdFor(S, key)
  local g = byKey[key].gcd or 0
  if g <= 0 then return 0 end
  if g < 1.5 then return 1.0 end
  g = S.gcd or 1.5
  if g < 1.0 then return 1.0 end -- = math.max(1.0, g), inlined (hot)
  return g
end

-- Static Shock gives Lightning Shield 2 extra charges
function M.lsMaxCharges(S)
  return 3 + (talent(S, "staticShock") > 0 and 2 or 0)
end

function M.castTime(S, key)
  local meta = byKey[key]
  if not meta or (meta.castBase or 0) <= 0 then return 0 end
  local mw = ((S.buffs and S.buffs.mw and S.buffs.mw.stacks) or 0) + 1e-9
  mw = mw - mw % 1 -- = floor(mw), without the call (hot)
  if mw >= 5 then return 0 end
  return meta.castBase * (1 - 0.2 * mw) / (S.player.spellHaste or 1)
end

-- per-spell conditions besides cooldown, mana and range (nil = allowed)
local SPECIAL = {
  lavaLash = function(S) return S.weapons.oh ~= nil end,
  -- Fire Nova and Magma Totem hit only around the totem at the shaman's feet (damage.totemTargets)
  fireNova = function(S) return fireUp(S) and damage.totemTargets(S) >= 1 end,
  searingTotem = function(S, fire) return not (fire.kind == "fireElemental" and (fire.remains or 0) > 0) end,
  magmaTotem = function(S, fire)
    if fire.kind == "fireElemental" and (fire.remains or 0) > 0 then return false end
    return damage.totemTargets(S) >= 1
  end,
  -- spec 5.1: Frost Shock only where it pays, i.e. without Earth Shock (same cooldown, no Stormstrike bonus)
  frostShock = function(S) return not S.spells.earthShock end,
  callOfElements = function(S, fire)
    if fire.kind == "fireElemental" and (fire.remains or 0) > 0 then return false end
    if fireUp(S) then
      local water = S.totems.water
      if not water or (water.remains or 0) >= M.COE_WATER then return false end
    end
    return true
  end,
  lightningShield = function(S)
    if not util.wantsLightningShield(S) then return false end -- Water Shield kept up instead
    local ls = S.buffs.ls
    if (ls.charges or 0) >= M.lsMaxCharges(S) then return false end
    -- charges are not spent in the model: a refresh only matters when the shield is gone or ending
    return not ((ls.charges or 0) > 0 and (ls.remains or 0) >= M.HORIZON)
  end,
}

-- false: the search must not suggest key now (the player's option for that cooldown). Pure,
-- no allocation; keys without an option are always allowed.
-- latched: "auto" already allowed key on this target (snapshot's latch); it then holds down to
-- need x COOLDOWN_RELEASE. An unknown ttd releases nothing (the estimate restarting says nothing
-- new about the mob).
function M.cooldownDecide(S, key, latched)
  local cds = S.cooldowns
  local mode = cds and cds[key]
  if mode == nil or mode == "always" then return true end
  if mode == "never" then return false end
  local t = S.target
  if t and t.isBoss then return true end
  if mode ~= "auto" then return false end -- "boss"
  local need, ttd = M.COOLDOWN_TTD[key], t and t.ttd
  if need == nil then return false end
  if latched then return ttd == nil or ttd >= need * M.COOLDOWN_RELEASE end
  return ttd ~= nil and ttd >= need
end

-- the snapshot's decision (S.cdAllowed, carried unchanged along the plan) when there is one;
-- a state without it (tests, old recordings) decides from its own target
function M.cooldownAllowed(S, key)
  local a = S.cdAllowed
  if a then return a[key] ~= false end
  return M.cooldownDecide(S, key, false)
end

-- The player's weaving option (S.weaveMin: 3 / 5 stacks, 0 or nil = the model decides): no
-- Lightning Bolt / Chain Lightning below that many Maelstrom stacks. Only in melee: at range (the
-- pull, a ranged target) a cast is the only damage there is; and only with Maelstrom Weapon: below
-- the talent (leveling) the stacks never come, and a hard cast is the normal rotation. Pure, no
-- allocation.
function M.weaveAllowed(S)
  local wm = S.weaveMin
  if not wm or wm <= 0 then return true end
  local t = S.target
  if not (t and t.range == "melee") or talent(S, "maelstromWeapon") <= 0 then return true end
  local mw = S.buffs and S.buffs.mw
  local n = ((mw and mw.stacks) or 0) + 1e-9
  return n - n % 1 >= wm
end

function M.readyIn(S, key)
  local meta, sp = byKey[key], S.spells and S.spells[key]
  if not meta or not sp then return nil end
  if S.cooldowns and not M.cooldownAllowed(S, key) then return nil end
  -- cheapest tests first: most buttons are simply on cooldown
  local r = sp.cd or 0
  local c, g = S.castRemains or 0, S.gcdRemains or 0
  if c > r then r = c end
  if g > r then r = g end
  if r >= HORIZON then return nil end
  local p = S.player
  if (sp.cost or 0) > (p.mana or 0) then return nil end
  local t = S.target
  if NEEDS_TARGET[key] then
    -- alive(S), inlined
    if not (t and t.exists and t.enemy and not t.dead) or t.range == "far" then return nil end
    -- a target on its way in: melee buttons once it arrives, shocks once it is within 20 yards
    local range = t.range
    if range ~= "melee" then
      local mi = t.meleeIn
      if MELEE_ONLY[key] then
        if not mi then return nil end
        if mi > r then r = mi end
      end
      if SHOCK_RANGE[key] and range ~= "20" then
        if not mi then return nil end
        if mi - M.BAND20_ETA > r then r = mi - M.BAND20_ETA end
      end
      if r >= HORIZON then return nil end
    end
  end
  local fire = S.totems.fire
  local special = SPECIAL[key]
  if special and not special(S, fire) then return nil end
  -- the same fire totem again changes nothing while it still stands longer than value.TAIL counts
  local kind = TOTEM_KIND[key]
  if kind and kind == fire.kind and (fire.remains or 0) >= M.TOTEM_REDROP then return nil end
  if CAST_SPELLS[key] then
    if p.moving and M.castTime(S, key) > 0 then return nil end
    if S.weaveMin and not M.weaveAllowed(S) then return nil end
  end
  return r
end

local function addMw(n, x)
  if x <= 0 then return end
  local mw = n.buffs.mw
  x = (mw.stacks or 0) + x
  mw.stacks = x < 5 and x or 5 -- = math.min(5, x)
  mw.remains = M.MW_DURATION
end
M.addMw = addMw

function M.resetSwings(n)
  for _, h in ipairs(M.HANDS) do
    local s = n.swing[h]
    if s then s.next = s.speed end
  end
end

-- Shamanistic Rage: a landed melee attack (auto, Windfury extra, Stormstrike, Lava Lash) returns
-- RAGE_MANA_AP x AP as mana with the proc chance of its weapon (damage.rageChance, 10 PPM);
-- `hits` = expected procs, up to manaMax
local function rageMana(n, hits)
  local p = n.player
  local cap, mana = p.manaMax or math.huge, p.mana + hits * M.RAGE_MANA_AP * (p.ap or 0)
  setMana(n, mana < cap and mana or cap) -- = math.min(cap, mana)
end

-- swings of one hand landing within dt; only those before `life` (time to die) deal damage.
-- st: damage.swingStats(n) if the caller already has it -> damage, swingStats (nil = not looked up)
local function runHand(n, hand, dt, cast, life, st)
  local s = n.swing[hand]
  if not s or (s.speed or 0) <= 0 then return 0, st end
  local dmg, speed = 0, s.speed
  local at = s.next or 0
  if cast then
    if cast.reset then
      at = cast.ends + speed
    elseif at < cast.ends then
      at = cast.ends
    end
  end
  -- per-swing numbers do not change inside one advance (buffs only expire at its end)
  local perSwing, mwPer, hits
  local dtEnd, lifeEnd = dt + 1e-9, life + 1e-9
  while at <= dtEnd do
    if at <= lifeEnd then
      if not perSwing then
        st = st or damage.swingStats(n)
        if hand == "mh" then perSwing, mwPer = st.mh, st.mwmh else perSwing, mwPer = st.oh, st.mwoh end
      end
      dmg = dmg + perSwing
      if mwPer > 0 then -- addMw(n, mwPer), inlined (hot)
        local mw = n.buffs.mw
        local x = (mw.stacks or 0) + mwPer
        mw.stacks = x < 5 and x or 5
        mw.remains = M.MW_DURATION
      end
      if (n.buffs.rage or 0) > at then
        hits = hits or damage.rageProcsPerSwing(n, hand)
        rageMana(n, hits)
      end
    end
    at = at + speed
  end
  s.next = at - dt
  return dmg, st
end

-- true: advance cannot change S's mana. Only Shamanistic Rage returns mana while waiting, on a
-- swing before it runs out (runHand: rage > the swing's time, which is never negative after an
-- advance); search skips pricing the mana of such a tail
function M.waitKeepsMana(S)
  if (S.buffs.rage or 0) > 0 then return false end
  local sw = S.swing
  local mh, oh = sw.mh, sw.oh
  return not ((mh and (mh.next or 0) < 0) or (oh and (oh.next or 0) < 0))
end

local spareOf -- below
local CAST2 = {} -- the rest of a cast after the target arrives inside one advance (reused)

-- scratch state: a spell can be on cooldown only in its own entry, i.e. one on cooldown in the
-- source (onCd) or one setCd has switched since the fill (dirty); lowered in place
local function lowerOwnCds(n, dt)
  local map, list = n.spells, n.onCd
  for i = 1, n.nOnCd do
    local sp = map[list[i]]
    local cd = sp.cd
    if cd and cd > 0 then sp.cd = cd > dt and cd - dt or 0 end
  end
  list = n.dirty
  for i = 1, n.nDirty do
    local sp = map[list[i]]
    local cd = sp.cd
    if cd and cd > 0 then sp.cd = cd > dt and cd - dt or 0 end
  end
end

-- in place, no copy. cast = { ends = sec, reset = bool } | nil
-- cdsDone: the caller already lowered spell cooldowns by dt (clone(S, dt))
function M.advance(n, dt, cast, cdsDone)
  local t, sw = n.target, n.swing
  local mi = t.meleeIn
  if mi and mi > 0 and mi < dt then
    -- the target reaches melee inside this step: up to then without swings, from then on with
    local c1, c2 = cast, nil
    if cast and cast.ends > mi then
      CAST2.ends, CAST2.reset = cast.ends - mi, cast.reset
      c1, c2 = nil, CAST2
    end
    local d1 = M.advance(n, mi, c1, cdsDone)
    return d1 + M.advance(n, dt - mi, c2, cdsDone)
  end
  local live = t and t.exists and t.enemy and not t.dead
  local life = dt
  local ttd = t.ttd
  if live and ttd then
    if ttd < 0 then life = 0 elseif ttd < life then life = ttd end
  end
  local dmg = 0
  local mh, oh = sw.mh, sw.oh
  if sw.attacking and live and t.range == "melee" then
    -- with the memo both hands read the same swingStats table (its slot depends on Lightning
    -- Shield / Stormstrike charges and range, which a swing does not change): looked up once
    local dmh, st = runHand(n, "mh", dt, cast, life)
    dmg = dmh + (runHand(n, "oh", dt, cast, life, n.memo and st or nil))
  else
    if mh then local x = (mh.next or 0) - dt; mh.next = x > 0 and x or 0 end
    if oh then local x = (oh.next or 0) - dt; oh.next = x > 0 and x or 0 end
    if mi and cast and cast.reset and cast.ends <= dt then
      -- a target on its way in meets swings a cast has reset (a static range never sees them)
      for i = 1, 2 do
        local s = sw[M.HANDS[i]]
        if s and (s.speed or 0) > 0 then local x = cast.ends + s.speed - dt; s.next = x > 0 and x or 0 end
      end
    end
  end
  local tot = n.totems
  local fire = tot.fire
  local pets = n.pets
  if not pets then pets = spareOf(n, "pets"); pets.wolves = 0; n.pets = pets end
  local fs, fireLeft, wolves = t.fs or 0, fire.remains or 0, pets.wolves or 0
  if live then
    local src = fire.kind and FIRE_SOURCE[fire.kind]
    if fs > 0 or wolves > 0 or (src and fireLeft > 0) then
      local r = damage.rates(n)
      if fs > 0 then dmg = dmg + r.flameShock * (fs < life and fs or life) end
      if src and fireLeft > 0 then
        local span = fireLeft < life and fireLeft or life
        -- only Searing Totem can be out of reach (damage.fireUptime is the identity for the rest)
        if src == "searingTotem" then span = damage.fireUptime(n, src, span) end
        dmg = dmg + r[src] * span
      end
      if wolves > 0 then dmg = dmg + r.feralSpirit * (wolves < life and wolves or life) end
    end
  end
  if not cdsDone then
    if n.ownSpells then
      lowerOwnCds(n, dt)
    else
      local keys, map = spellKeys(n), n.spells
      for i = 1, #keys do
        local key = keys[i]
        local cd = map[key].cd
        if cd and cd > 0 then setCd(n, key, cd > dt and cd - dt or 0) end
      end
    end
  end
  -- timers count down to 0; one already at 0 stays as it is (the most common case: skipped)
  local x = n.gcdRemains
  if x ~= 0 then x = (x or 0) - dt; n.gcdRemains = x > 0 and x or 0 end
  x = n.castRemains
  if x ~= 0 then x = (x or 0) - dt; n.castRemains = x > 0 and x or 0 end
  local b = n.buffs
  local mw, ls, fl = b.mw, b.ls, b.flurry
  x = (mw.remains or 0) - dt
  if x > 0 then mw.remains = x else mw.remains = 0; mw.stacks = 0 end
  x = (ls.remains or 0) - dt
  if x > 0 then ls.remains = x else ls.remains = 0; ls.charges = 0 end
  x = (fl.remains or 0) - dt
  if x > 0 then fl.remains = x else fl.remains = 0; fl.charges = 0 end
  x = b.rage
  if x ~= 0 then x = (x or 0) - dt; b.rage = x > 0 and x or 0 end
  x = b.lust
  if x ~= 0 then x = (x or 0) - dt; b.lust = x > 0 and x or 0 end
  x = b.em
  if x ~= 0 then x = (x or 0) - dt; b.em = x > 0 and x or 0 end
  if t.fs ~= 0 then x = fs - dt; t.fs = x > 0 and x or 0 end
  local ss = t.ss
  if ss then
    x = (ss.remains or 0) - dt
    if x > 0 then ss.remains = x else ss.remains = 0; ss.charges = 0 end
  end
  if fireLeft ~= 0 or fire.remains ~= 0 or fire.kind ~= nil then
    x = fireLeft - dt
    if x > 0 then fire.remains = x else fire.remains = 0; fire.kind = nil end
  end
  local water = tot.water
  if water then x = (water.remains or 0) - dt; water.remains = x > 0 and x or 0 end
  if pets.wolves ~= 0 then x = wolves - dt; pets.wolves = x > 0 and x or 0 end
  if not n.ownSpells then -- a scratch state keeps no spells in flight (applyOn)
    local inf = n.inflight
    if not inf then inf = {}; n.inflight = inf end
    if next(inf) then
      for k, v in pairs(inf) do
        local left = v - dt
        if left <= 0 then inf[k] = nil else inf[k] = left end
      end
    end
  end
  n.now = n.now + dt
  if mi then
    x = mi - dt
    if x <= 1e-9 then
      t.meleeIn, t.range = nil, "melee"
    else
      t.meleeIn = x
      if t.range == "30" and x <= M.BAND20_ETA then t.range = "20" end
    end
  end
  if live then
    local hp = (t.hp or 0) - dmg
    if hp < 0 then hp = 0 end
    t.hp = hp
    if ttd then ttd = ttd - dt; t.ttd = ttd end
    if hp <= 0 or (ttd and ttd <= 0) then t.dead = true end
  end
  return dmg
end

-- Scratch states for look-ahead the search throws away right after (a candidate step, the tail
-- to the horizon). Filled field by field instead of allocated; two buffers, so a scratch state
-- can be the input of the next peek. Spell entries on cooldown are the buffer's own (n.ownSpells:
-- setCd edits them in place), ready ones are shared until changed; player stays shared and
-- copy-on-write; inflight stays empty (spells in flight matter to the display only).
-- A scratch result is valid only until the next peek call that writes the same buffer.
local function newScratch()
  return {
    ownSpells = true, spells = {}, inflight = {},
    buffs = { mw = {}, ls = {} },
    target = {}, totems = {}, swing = {}, pets = {},
    spare = { ss = {}, fire = {}, water = {}, mh = {}, oh = {}, flurry = {}, spells = {}, player = {}, player2 = {} },
    playerFrom = {}, -- spare player -> the node's player whose stats it holds (setMana)
    filled = {}, -- key -> the spare spell entry already holds id/rank/cost/cast of this search (memo)
    onCd = {}, nOnCd = 0, -- keys whose entry is the buffer's own after the fill (on cooldown in n.src)
    dirty = {}, nDirty = 0, -- keys setCd switched from the shared entry to the own one since the fill
  }
end
local SCR1, SCR2 = newScratch(), newScratch()
for _, n in ipairs({ SCR1, SCR2 }) do SPARE_PLAYER[n.spare.player], SPARE_PLAYER[n.spare.player2] = true, true end

-- copy S into a scratch buffer (not the one S itself lives in), cooldowns lowered by dt
local function fillScratch(S, dt)
  local n = S == SCR1 and SCR2 or SCR1
  local sp = n.spare
  local memo = S.memo
  local fresh = n.memo ~= memo or not memo
  if fresh then
    -- another search (or none): the spell key set and the spells' ranks may differ
    for k in pairs(n.spells) do n.spells[k] = nil end
    local filled = n.filled
    for k in pairs(filled) do filled[k] = nil end
    local from = n.playerFrom
    for k in pairs(from) do from[k] = nil end
  end
  local inf = n.inflight
  if next(inf) then for k in pairs(inf) do inf[k] = nil end end
  -- fields the model never changes: copied only when the source state changes
  -- (sources are search nodes, which are never modified; a scratch source always recopies)
  local t, st = n.target, S.target
  local same = not fresh and n.src == S and S ~= SCR1 and S ~= SCR2
  n.src = S
  if not same then
    n.gcd, n.latency = S.gcd, S.latency
    n.mode, n.weapons, n.talents, n.enemies, n.memo = S.mode, S.weapons, S.talents, S.enemies, S.memo
    n.shieldPref = S.shieldPref
    n.cooldowns, n.cdAllowed = S.cooldowns, S.cdAllowed
    n.weaveMin = S.weaveMin
    t.exists, t.enemy, t.level, t.hpMax, t.hpPct = st.exists, st.enemy, st.level, st.hpMax, st.hpPct
    t.guessed, t.armor, t.inCombat, t.isPlayer, t.isBoss = st.guessed, st.armor, st.inCombat, st.isPlayer, st.isBoss
    n.swing.resetByInstant = S.swing.resetByInstant
  end
  n.swing.attacking = S.swing.attacking -- Stormstrike / Lava Lash turn it on (applyOn)
  n.now, n.gcdRemains, n.castRemains = S.now, S.gcdRemains, S.castRemains
  n.player, n.playerOwn = S.player, nil
  local spells, own, from, filled = n.spells, sp.spells, S.spells, n.filled
  local onCd = n.onCd
  if same then
    -- the same (never modified) source as the last fill: every ready spell still points at its
    -- shared entry except those setCd switched to the own one (dirty); the ones on cooldown get
    -- their own entry's cd again (its id/rank/cost/cast are already this search's: filled)
    local dirty = n.dirty
    for i = 1, n.nDirty do
      local key = dirty[i]
      spells[key] = from[key] -- on cooldown in the source: set again just below
    end
    for i = 1, n.nOnCd do
      local key = onCd[i]
      local e = own[key]
      local cd = from[key].cd - dt
      if cd < 0 then cd = 0 end
      e.cd = cd
      spells[key] = e
    end
  else
    local keys = spellKeys(S)
    local nOn = 0
    for i = 1, #keys do
      local key = keys[i]
      local src = from[key]
      local cd = src.cd
      if cd and cd > 0 then
        nOn = nOn + 1
        onCd[nOn] = key
        local e = own[key]
        if not e then e = {}; own[key] = e end
        cd = cd - dt
        if cd < 0 then cd = 0 end
        -- id, rank, cost and cast of a spell never change inside one search: copied once per memo
        if filled[key] then
          e.cd = cd
        else
          e.id, e.rank, e.cd, e.cost, e.cast = src.id, src.rank, cd, src.cost, src.cast
          if memo then filled[key] = true end
        end
        spells[key] = e
      else
        spells[key] = src -- ready: shared, setCd switches to the own entry before a change
        -- a scratch source can hand over this buffer's own entry (ready): setCd then changes
        -- it in place, without switching, so advance must find it among the own ones
        if src == own[key] then nOn = nOn + 1; onCd[nOn] = key end
      end
    end
    n.nOnCd = nOn
  end
  n.nDirty = 0
  local b, sb = n.buffs, S.buffs
  b.mw.stacks, b.mw.remains = sb.mw.stacks, sb.mw.remains
  b.ls.charges, b.ls.remains = sb.ls.charges, sb.ls.remains
  local fl = sb.flurry
  if fl then
    sp.flurry.charges, sp.flurry.remains = fl.charges, fl.remains
    b.flurry = sp.flurry
  else
    b.flurry = nil
  end
  b.rage, b.lust, b.em = sb.rage, sb.lust, sb.em
  t.hp, t.ttd, t.fs, t.dead = st.hp, st.ttd, st.fs, st.dead
  t.range, t.meleeIn = st.range, st.meleeIn -- advance changes them (the target comes in)
  local ss = st.ss
  if ss then
    sp.ss.charges, sp.ss.remains = ss.charges, ss.remains
    t.ss = sp.ss
  else
    t.ss = nil
  end
  local fire, water = S.totems.fire, S.totems.water
  if fire then
    sp.fire.kind, sp.fire.remains = fire.kind, fire.remains
    n.totems.fire = sp.fire
  else
    n.totems.fire = nil
  end
  if water then
    sp.water.remains = water.remains
    n.totems.water = sp.water
  else
    n.totems.water = nil
  end
  local sw, nsw = S.swing, n.swing
  local h = sw.mh
  if h then local d = sp.mh; d.next, d.speed = h.next, h.speed; nsw.mh = d else nsw.mh = nil end
  h = sw.oh
  if h then local d = sp.oh; d.next, d.speed = h.next, h.speed; nsw.oh = d else nsw.oh = nil end
  n.pets.wolves = S.pets and S.pets.wolves or 0
  return n
end

-- like wait(), but the result is a scratch state (see above)
function M.peekWait(S, dt)
  local n = fillScratch(S, dt)
  local dmg = M.advance(n, dt, nil, true)
  return n, dmg
end

function M.wait(S, dt)
  local n = M.clone(S, dt)
  local dmg = M.advance(n, dt, nil, true)
  return n, dmg
end

-- sharedCd group -> keys in it
M.SHARED = {}
for _, meta in ipairs(spells.CATALOG) do
  local g = meta.sharedCd
  if g then
    M.SHARED[g] = M.SHARED[g] or {}
    table.insert(M.SHARED[g], meta.key)
  end
end

local function fsDuration(n)
  local m = n.memo
  local d = m and m.fsDuration
  if not d then
    local _, ticks, period = damage.dot(n, "flameShock")
    d = ticks * period
    if m then m.fsDuration = d end
  end
  return d
end

-- a copy's buffs, target and totem tables are its own (cloneState, fillState, fillScratch): a
-- missing one comes from the copy's spare tables (scratch, arena) or is a new one
function spareOf(n, name)
  local s = n.ownSpells and n.spare or n.pool
  return s and s[name] or {}
end

local function setFire(n, kind, remains)
  local f = n.totems.fire or spareOf(n, "fire")
  f.kind, f.remains = kind, remains
  n.totems.fire = f
end

local CAST = {} -- apply's cast description for advance, reused (advance does not keep it)

-- apply() on a copy n of S whose cooldowns are already lowered by adv (<= dt): the state moves
-- adv seconds on; if adv < dt the rest of the GCD / cast stays in gcdRemains / castRemains
local function applyOn(n, key, ct, dt, adv)
  local meta = byKey[key]
  local sp = n.spells[key]
  -- a cast lands when the server ends it, castTime + latency after the press (as the swing clock
  -- below); a target dying before that takes nothing: no damage and no kill by it (the mana and
  -- the cooldown are still counted)
  local dmg = 0
  local t = n.target
  if t and t.exists and t.enemy and not t.dead then -- alive(n), inlined
    local ttd = t.ttd
    if not (ct > 0 and ttd and ttd < ct + (n.latency or 0)) then dmg = damage.action(n, key) end
  end
  local mwAtCast = (n.buffs.mw.stacks or 0) + 1e-9
  mwAtCast = mwAtCast - mwAtCast % 1 -- = floor
  -- the pull: a spell on a mob at range brings it in, from the moment the spell lands
  if NEEDS_TARGET[key] and not t.meleeIn and t.range ~= "melee" and M.canApproach(n) then
    t.meleeIn = (ct > 0 and ct + (n.latency or 0) or 0) + util.approachEta(t.range)
  end

  setMana(n, n.player.mana - (sp.cost or 0))
  local cd = M.cooldownFor(n, key) - adv
  if cd < 0 then cd = 0 end
  if meta.sharedCd then
    local group = M.SHARED[meta.sharedCd]
    for i = 1, #group do
      local k = group[i]
      if n.spells[k] then setCd(n, k, cd) end
    end
  else
    setCd(n, key, cd)
  end

  local ss = n.target.ss
  if ss and M.NATURE_CONSUME[key] and (ss.charges or 0) > 0 then
    ss.charges = ss.charges - 1
    if ss.charges <= 0 then ss.remains = 0 end
  end
  if CAST_SPELLS[key] then n.buffs.mw.stacks = 0; n.buffs.mw.remains = 0 end
  -- a melee attack starts auto attack (3.3.5a): the next swing comes as soon as its timer is up
  if MELEE_ONLY[key] then n.swing.attacking = true end
  if key == "stormstrike" then
    local nss = n.target.ss or spareOf(n, "ss") -- own in every copy: changed in place
    nss.charges, nss.remains = M.SS_CHARGES, M.SS_DURATION
    n.target.ss = nss
    addMw(n, damage.mwPerHit(n, "mh") + (n.weapons.oh and damage.mwPerHit(n, "oh") or 0))
    if (n.buffs.rage or 0) > 0 and alive(n) then
      rageMana(n, (damage.rageChance(n, "mh") + damage.rageChance(n, "oh")) * damage.meleeTable(n, false).landed)
    end
  elseif key == "lavaLash" then
    addMw(n, damage.mwPerHit(n, "oh"))
    if (n.buffs.rage or 0) > 0 and alive(n) then rageMana(n, damage.rageChance(n, "oh") * damage.meleeTable(n, false).landed) end
  elseif key == "flameShock" then
    n.target.fs = fsDuration(n)
  elseif M.TOTEM_KIND[key] then
    setFire(n, M.TOTEM_KIND[key], M.TOTEM_DURATION[key])
  elseif key == "callOfElements" then
    -- drops the whole totem set; its fire totem is taken as Magma (Searing before Magma is learned)
    if n.totems.water then n.totems.water.remains = M.WATER_DURATION end
    local fk = n.spells.magmaTotem and "magmaTotem" or "searingTotem"
    setFire(n, M.TOTEM_KIND[fk], M.TOTEM_DURATION[fk])
  elseif key == "lightningShield" then
    local ls = n.buffs.ls -- own in every copy
    ls.charges, ls.remains = M.lsMaxCharges(n), M.LS_DURATION
  elseif key == "shamanisticRage" then
    n.buffs.rage = M.RAGE_DURATION
  elseif key == "feralSpirit" then
    n.pets = n.pets or spareOf(n, "pets")
    n.pets.wolves = M.WOLVES_DURATION
  end
  if not n.ownSpells then -- a scratch state keeps none: nothing in the search reads them
    n.inflight = n.inflight or {}
    n.inflight[key] = M.INFLIGHT
  end
  if dmg > 0 then
    local hp = (t.hp or 0) - dmg
    hp = hp > 0 and hp or 0 -- = math.max(0, hp)
    t.hp = hp
    if hp <= 0 then t.dead = true end
  end

  local cast
  if ct > 0 then
    cast = CAST
    -- the swing clock goes on when the server ends the cast: castTime + latency after the press
    cast.ends, cast.reset = ct + (n.latency or 0), mwAtCast == 0
  elseif n.swing.resetByInstant and n.swing.resetByInstant[key] then
    M.resetSwings(n)
  end
  n.gcdRemains, n.castRemains = dt, ct
  local autoDmg = M.advance(n, adv, cast, true)
  return n, dmg + autoDmg, adv
end

-- limit (optional): move the state at most this far (search: not past its horizon)
function M.apply(S, key, limit)
  local ct = M.castTime(S, key)
  local g = M.gcdFor(S, key)
  local dt = ct > g and ct or g -- = math.max(g, ct)
  local adv = (limit and limit < dt) and limit or dt
  -- cooldowns are lowered by adv right in the copy; advance skips them
  return applyOn(M.clone(S, adv), key, ct, dt, adv)
end

-- like apply(), but the result is a scratch state (see peekWait)
-- ct (optional): castTime(S, key) when the caller already has it
function M.peekApply(S, key, limit, ct)
  ct = ct or M.castTime(S, key)
  local g = M.gcdFor(S, key)
  local dt = ct > g and ct or g -- = math.max(g, ct)
  local adv = (limit and limit < dt) and limit or dt
  return applyOn(fillScratch(S, adv), key, ct, dt, adv)
end

-- peekApply(n, ...) for a scratch state n, done in n itself instead of a copy in the other
-- buffer: the same numbers, one fill less. n is gone afterwards (search: the press after a
-- peekWait whose state nothing reads any more)
function M.peekApplyOver(n, key, limit, ct)
  ct = ct or M.castTime(n, key)
  local g = M.gcdFor(n, key)
  local dt = ct > g and ct or g -- = math.max(g, ct)
  local adv = (limit and limit < dt) and limit or dt
  lowerOwnCds(n, adv) -- what fillScratch(n, adv) does to the cooldowns
  local inf = n.inflight -- and what it does to the spells in flight (a wait leaves none)
  if next(inf) then for k in pairs(inf) do inf[k] = nil end end
  return applyOn(n, key, ct, dt, adv)
end

-- candidates in spells.CATALOG order, waitSwing last
local CATALOG = spells.CATALOG
function M.actions(S)
  local out, n = {}, 0
  local readyIn = M.readyIn
  for i = 1, #CATALOG do
    local key = CATALOG[i].key
    local r = readyIn(S, key)
    if r then n = n + 1; out[n] = { key = key, readyIn = r } end
  end
  local r = M.swingIn(S)
  if r and r < HORIZON then out[n + 1] = { key = "waitSwing", readyIn = r } end
  return out
end

-- time until just after the next own swing (what waitSwing waits); nil = no swings coming
function M.swingIn(S)
  local sw = S.swing
  if not (sw and sw.attacking and alive(S) and S.target.range == "melee") then return nil end
  local nxt = math.huge
  for _, h in ipairs(M.HANDS) do
    if sw[h] and sw[h].next then nxt = math.min(nxt, sw[h].next) end
  end
  if nxt == math.huge then return nil end
  return nxt + M.WAIT_SWING_PAD
end

return M
