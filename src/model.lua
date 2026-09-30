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
M.RAGE_MANA_AP = 0.15
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

-- cooldowns after dt seconds: entries still on cooldown are replaced, the rest stay shared
local function tickSpells(S, map, dt)
  local keys = spellKeys(S)
  for i = 1, #keys do
    local key = keys[i]
    local sp = map[key]
    local cd = sp.cd
    if cd and cd > 0 then
      cd = cd - dt
      if cd < 0 then cd = 0 end
      map[key] = { id = sp.id, rank = sp.rank, cd = cd, cost = sp.cost, cast = sp.cast }
    end
  end
  return map
end

function M.clone(S, dt)
  local n = M.cloneState(S)
  if dt then tickSpells(S, n.spells, dt) end
  return n
end

function M.cloneState(S)
  local b, t, tot, sw = S.buffs, S.target, S.totems, S.swing
  local fire, water, ss, pets = tot.fire, tot.water, t.ss, S.pets
  return {
    now = S.now, gcdRemains = S.gcdRemains, castRemains = S.castRemains, gcd = S.gcd, latency = S.latency,
    mode = S.mode, player = S.player, weapons = S.weapons, talents = S.talents, enemies = S.enemies,
    memo = S.memo, spells = spellMap(S.spells), inflight = next(S.inflight or {}) and shallow(S.inflight) or {},
    buffs = { mw = { stacks = b.mw.stacks, remains = b.mw.remains },
              ls = { charges = b.ls.charges, remains = b.ls.remains },
              flurry = b.flurry and { charges = b.flurry.charges, remains = b.flurry.remains },
              rage = b.rage, lust = b.lust, em = b.em },
    target = { exists = t.exists, enemy = t.enemy, level = t.level, hp = t.hp, hpMax = t.hpMax, hpPct = t.hpPct,
               ttd = t.ttd, range = t.range, fs = t.fs, guessed = t.guessed, dead = t.dead, armor = t.armor,
               ss = ss and { charges = ss.charges, remains = ss.remains } },
    totems = { fire = fire and { kind = fire.kind, remains = fire.remains },
               water = water and { remains = water.remains } },
    swing = { attacking = sw.attacking, resetByInstant = sw.resetByInstant, mh = hand(sw.mh), oh = hand(sw.oh) },
    pets = pets and { wolves = pets.wolves },
  }
end

-- n.player is shared with the parent state: replace it before changing mana
local function setMana(n, mana)
  local p = n.player
  if p.mana == mana then return end
  if n.ownSpells then
    -- scratch state: its own player table, no allocation
    local o = n.spare.player
    if o ~= p then
      o.level, o.manaMax, o.baseMana, o.hpPct, o.ap = p.level, p.manaMax, p.baseMana, p.hpPct, p.ap
      o.spNature, o.spFire, o.meleeCrit, o.spellCrit = p.spNature, p.spFire, p.meleeCrit, p.spellCrit
      o.meleeHit, o.spellHit, o.spellHaste, o.meleeHaste = p.meleeHit, p.spellHit, p.spellHaste, p.meleeHaste
      o.moving, o.inCombat = p.moving, p.inCombat
      n.player = o
    end
    o.mana = mana
    return
  end
  n.player = {
    level = p.level, mana = mana, manaMax = p.manaMax, baseMana = p.baseMana, hpPct = p.hpPct, ap = p.ap,
    spNature = p.spNature, spFire = p.spFire, meleeCrit = p.meleeCrit, spellCrit = p.spellCrit,
    meleeHit = p.meleeHit, spellHit = p.spellHit, spellHaste = p.spellHaste, meleeHaste = p.meleeHaste,
    moving = p.moving, inCombat = p.inCombat,
  }
end

-- replace n.spells[key] by a copy with the new cooldown (the old table may be shared)
local function setCd(n, key, cd)
  local sp = n.spells[key]
  if sp.cd == cd then return end
  if n.ownSpells then
    -- scratch state: its own entry for this key, filled from the (maybe shared) current one
    local e = n.spare.spells[key]
    if not e then e = {}; n.spare.spells[key] = e end
    if e ~= sp then e.id, e.rank, e.cost, e.cast = sp.id, sp.rank, sp.cost, sp.cast; n.spells[key] = e end
    e.cd = cd
    return
  end
  n.spells[key] = { id = sp.id, rank = sp.rank, cd = cd, cost = sp.cost, cast = sp.cast }
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
  local g = spells.byKey[key].gcd or 0
  if g <= 0 then return 0 end
  if g < 1.5 then return 1.0 end
  return math.max(1.0, S.gcd or 1.5)
end

-- Static Shock gives Lightning Shield 2 extra charges
function M.lsMaxCharges(S)
  return 3 + (talent(S, "staticShock") > 0 and 2 or 0)
end

function M.castTime(S, key)
  local meta = spells.byKey[key]
  if not meta or (meta.castBase or 0) <= 0 then return 0 end
  local mw = math.floor(((S.buffs and S.buffs.mw and S.buffs.mw.stacks) or 0) + 1e-9)
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
    local ls = S.buffs.ls
    if (ls.charges or 0) >= M.lsMaxCharges(S) then return false end
    -- charges are not spent in the model: a refresh only matters when the shield is gone or ending
    return not ((ls.charges or 0) > 0 and (ls.remains or 0) >= M.HORIZON)
  end,
}

function M.readyIn(S, key)
  local meta, sp = spells.byKey[key], S.spells and S.spells[key]
  if not meta or not sp then return nil end
  -- cheapest tests first: most buttons are simply on cooldown
  local r = sp.cd or 0
  local c, g = S.castRemains or 0, S.gcdRemains or 0
  if c > r then r = c end
  if g > r then r = g end
  if r >= M.HORIZON then return nil end
  if (sp.cost or 0) > (S.player.mana or 0) then return nil end
  local t = S.target
  local live = alive(S)
  if M.NEEDS_TARGET[key] then
    if not live or t.range == "far" then return nil end
    if M.MELEE_ONLY[key] and t.range ~= "melee" then return nil end
    if M.SHOCK_RANGE[key] and t.range ~= "melee" and t.range ~= "20" then return nil end
  end
  local fire = S.totems.fire
  local special = SPECIAL[key]
  if special and not special(S, fire, live) then return nil end
  -- the same fire totem again changes nothing while it still stands longer than value.TAIL counts
  local kind = M.TOTEM_KIND[key]
  if kind and kind == fire.kind and (fire.remains or 0) >= M.TOTEM_REDROP then return nil end
  if S.player.moving and M.CAST_SPELLS[key] and M.castTime(S, key) > 0 then return nil end
  return r
end

function M.addMw(n, x)
  if x <= 0 then return end
  local mw = n.buffs.mw
  mw.stacks = math.min(5, (mw.stacks or 0) + x)
  mw.remains = M.MW_DURATION
end

function M.resetSwings(n)
  for _, h in ipairs(M.HANDS) do
    local s = n.swing[h]
    if s then s.next = s.speed end
  end
end

-- swings of one hand landing within dt; only those before `life` (time to die) deal damage
local function runHand(n, hand, dt, cast, life)
  local s = n.swing[hand]
  if not s or (s.speed or 0) <= 0 then return 0 end
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
  local perSwing, mwPer
  while at <= dt + 1e-9 do
    if at <= life + 1e-9 then
      if not perSwing then
        local st = damage.swingStats(n)
        perSwing, mwPer = st[hand], st["mw" .. hand]
      end
      dmg = dmg + perSwing
      M.addMw(n, mwPer)
      if (n.buffs.rage or 0) > at then
        setMana(n, math.min(n.player.manaMax or math.huge, n.player.mana + M.RAGE_MANA_AP * (n.player.ap or 0)))
      end
    end
    at = at + speed
  end
  s.next = at - dt
  return dmg
end

-- in place, no copy. cast = { ends = sec, reset = bool } | nil
-- cdsDone: the caller already lowered spell cooldowns by dt (clone(S, dt))
function M.advance(n, dt, cast, cdsDone)
  local t, sw = n.target, n.swing
  local live = t and t.exists and t.enemy and not t.dead
  local life = dt
  local ttd = t.ttd
  if live and ttd then
    if ttd < 0 then life = 0 elseif ttd < life then life = ttd end
  end
  local dmg = 0
  local mh, oh = sw.mh, sw.oh
  if sw.attacking and live and t.range == "melee" then
    dmg = runHand(n, "mh", dt, cast, life) + runHand(n, "oh", dt, cast, life)
  else
    if mh then local x = (mh.next or 0) - dt; mh.next = x > 0 and x or 0 end
    if oh then local x = (oh.next or 0) - dt; oh.next = x > 0 and x or 0 end
  end
  local tot = n.totems
  local fire = tot.fire
  local pets = n.pets
  if not pets then pets = { wolves = 0 }; n.pets = pets end
  local fs, fireLeft, wolves = t.fs or 0, fire.remains or 0, pets.wolves or 0
  if live then
    local src = fire.kind and FIRE_SOURCE[fire.kind]
    if fs > 0 or wolves > 0 or (src and fireLeft > 0) then
      local r = damage.rates(n)
      if fs > 0 then dmg = dmg + r.flameShock * (fs < life and fs or life) end
      if src and fireLeft > 0 then dmg = dmg + r[src] * (fireLeft < life and fireLeft or life) end
      if wolves > 0 then dmg = dmg + r.feralSpirit * (wolves < life and wolves or life) end
    end
  end
  if not cdsDone then
    local keys, map = spellKeys(n), n.spells
    local own = n.ownSpells and n.spare.spells
    for i = 1, #keys do
      local key = keys[i]
      local sp = map[key]
      local cd = sp.cd
      if cd and cd > 0 then
        cd = cd > dt and cd - dt or 0
        if own and own[key] == sp then sp.cd = cd else setCd(n, key, cd) end
      end
    end
  end
  local x = (n.gcdRemains or 0) - dt
  n.gcdRemains = x > 0 and x or 0
  x = (n.castRemains or 0) - dt
  n.castRemains = x > 0 and x or 0
  local b = n.buffs
  local mw, ls, fl = b.mw, b.ls, b.flurry
  x = (mw.remains or 0) - dt
  if x > 0 then mw.remains = x else mw.remains = 0; mw.stacks = 0 end
  x = (ls.remains or 0) - dt
  if x > 0 then ls.remains = x else ls.remains = 0; ls.charges = 0 end
  x = (fl.remains or 0) - dt
  if x > 0 then fl.remains = x else fl.remains = 0; fl.charges = 0 end
  x = (b.rage or 0) - dt; b.rage = x > 0 and x or 0
  x = (b.lust or 0) - dt; b.lust = x > 0 and x or 0
  x = (b.em or 0) - dt; b.em = x > 0 and x or 0
  x = fs - dt
  t.fs = x > 0 and x or 0
  local ss = t.ss
  if ss then
    x = (ss.remains or 0) - dt
    if x > 0 then ss.remains = x else ss.remains = 0; ss.charges = 0 end
  end
  x = fireLeft - dt
  if x > 0 then fire.remains = x else fire.remains = 0; fire.kind = nil end
  local water = tot.water
  if water then x = (water.remains or 0) - dt; water.remains = x > 0 and x or 0 end
  x = wolves - dt
  pets.wolves = x > 0 and x or 0
  local inf = n.inflight
  if not inf then inf = {}; n.inflight = inf end
  if next(inf) then
    for k, v in pairs(inf) do
      local left = v - dt
      if left <= 0 then inf[k] = nil else inf[k] = left end
    end
  end
  n.now = n.now + dt
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
-- copy-on-write; inflight starts empty.
-- A scratch result is valid only until the next peek call that writes the same buffer.
local function newScratch()
  return {
    ownSpells = true, spells = {}, inflight = {},
    buffs = { mw = {}, ls = {} },
    target = {}, totems = {}, swing = {}, pets = {},
    spare = { ss = {}, fire = {}, water = {}, mh = {}, oh = {}, flurry = {}, spells = {}, player = {} },
  }
end
local SCR1, SCR2 = newScratch(), newScratch()

local function fillHand(dst, src)
  if not src then return nil end
  dst.next, dst.speed = src.next, src.speed
  return dst
end

-- copy S into a scratch buffer (not the one S itself lives in), cooldowns lowered by dt
local function fillScratch(S, dt)
  local n = S == SCR1 and SCR2 or SCR1
  local sp = n.spare
  if n.memo ~= S.memo or not S.memo then
    -- another search (or none): the spell key set may differ
    for k in pairs(n.spells) do n.spells[k] = nil end
  end
  local inf = n.inflight
  if next(inf) then for k in pairs(inf) do inf[k] = nil end end
  -- fields the model never changes: copied only when the source state changes
  -- (sources are search nodes, which are never modified; a scratch source always recopies)
  local t, st = n.target, S.target
  local same = n.src == S and S.memo and S ~= SCR1 and S ~= SCR2
  n.src = S
  if not same then
    n.gcd, n.latency = S.gcd, S.latency
    n.mode, n.weapons, n.talents, n.enemies, n.memo = S.mode, S.weapons, S.talents, S.enemies, S.memo
    t.exists, t.enemy, t.level, t.hpMax, t.hpPct = st.exists, st.enemy, st.level, st.hpMax, st.hpPct
    t.range, t.guessed, t.armor = st.range, st.guessed, st.armor
    n.swing.attacking, n.swing.resetByInstant = S.swing.attacking, S.swing.resetByInstant
  end
  n.now, n.gcdRemains, n.castRemains = S.now, S.gcdRemains, S.castRemains
  n.player = S.player
  local spells, own, from = n.spells, sp.spells, S.spells
  local keys = spellKeys(S)
  for i = 1, #keys do
    local key = keys[i]
    local src = from[key]
    local cd = src.cd
    if cd and cd > 0 then
      local e = own[key]
      if not e then e = {}; own[key] = e end
      cd = cd - dt
      if cd < 0 then cd = 0 end
      e.id, e.rank, e.cd, e.cost, e.cast = src.id, src.rank, cd, src.cost, src.cast
      spells[key] = e
    else
      spells[key] = src -- ready: shared, setCd switches to the own entry before a change
    end
  end
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
  nsw.mh, nsw.oh = fillHand(sp.mh, sw.mh), fillHand(sp.oh, sw.oh)
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

local CAST = {} -- apply's cast description for advance, reused (advance does not keep it)

-- apply() on a copy n of S whose cooldowns are already lowered by adv (<= dt): the state moves
-- adv seconds on; if adv < dt the rest of the GCD / cast stays in gcdRemains / castRemains
local function applyOn(n, key, ct, dt, adv)
  local meta = spells.byKey[key]
  local sp = n.spells[key]
  local dmg = alive(n) and damage.action(n, key) or 0
  local mwAtCast = math.floor((n.buffs.mw.stacks or 0) + 1e-9)

  setMana(n, n.player.mana - (sp.cost or 0))
  local cd = M.cooldownFor(n, key) - adv
  if cd < 0 then cd = 0 end
  if meta.sharedCd then
    for _, k in ipairs(M.SHARED[meta.sharedCd]) do
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
  if M.CAST_SPELLS[key] then n.buffs.mw.stacks = 0; n.buffs.mw.remains = 0 end
  if key == "stormstrike" then
    local nss = n.ownSpells and n.spare.ss or {}
    nss.charges, nss.remains = M.SS_CHARGES, M.SS_DURATION
    n.target.ss = nss
    M.addMw(n, damage.mwPerHit(n, "mh") + (n.weapons.oh and damage.mwPerHit(n, "oh") or 0))
  elseif key == "lavaLash" then
    M.addMw(n, damage.mwPerHit(n, "oh"))
  elseif key == "flameShock" then
    n.target.fs = fsDuration(n)
  elseif M.TOTEM_KIND[key] then
    n.totems.fire = { kind = M.TOTEM_KIND[key], remains = M.TOTEM_DURATION[key] }
  elseif key == "callOfElements" then
    -- drops the whole totem set; its fire totem is taken as Magma (Searing before Magma is learned)
    if n.totems.water then n.totems.water.remains = M.WATER_DURATION end
    local fk = n.spells.magmaTotem and "magmaTotem" or "searingTotem"
    n.totems.fire = { kind = M.TOTEM_KIND[fk], remains = M.TOTEM_DURATION[fk] }
  elseif key == "lightningShield" then
    n.buffs.ls = { charges = M.lsMaxCharges(n), remains = M.LS_DURATION }
  elseif key == "shamanisticRage" then
    n.buffs.rage = M.RAGE_DURATION
  elseif key == "feralSpirit" then
    n.pets = n.pets or {}
    n.pets.wolves = M.WOLVES_DURATION
  end
  n.inflight = n.inflight or {}
  n.inflight[key] = M.INFLIGHT
  if dmg > 0 then
    n.target.hp = math.max(0, (n.target.hp or 0) - dmg)
    if n.target.hp <= 0 then n.target.dead = true end
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
  local dt = math.max(M.gcdFor(S, key), ct)
  local adv = (limit and limit < dt) and limit or dt
  -- cooldowns are lowered by adv right in the copy; advance skips them
  return applyOn(M.clone(S, adv), key, ct, dt, adv)
end

-- like apply(), but the result is a scratch state (see peekWait)
function M.peekApply(S, key, limit)
  local ct = M.castTime(S, key)
  local dt = math.max(M.gcdFor(S, key), ct)
  local adv = (limit and limit < dt) and limit or dt
  return applyOn(fillScratch(S, adv), key, ct, dt, adv)
end

-- candidates in spells.CATALOG order, waitSwing last
function M.actions(S)
  local out = {}
  for _, meta in ipairs(spells.CATALOG) do
    local r = M.readyIn(S, meta.key)
    if r then out[#out + 1] = { key = meta.key, readyIn = r } end
  end
  local r = M.swingIn(S)
  if r and r < M.HORIZON then out[#out + 1] = { key = "waitSwing", readyIn = r } end
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
