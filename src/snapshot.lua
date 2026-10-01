local spells = require("spells")
local talents = require("talents")
local damage = require("damage")
local value = require("value")
local util = require("util")
local model = require("model")

local M = {}

--@addon
local raid = require("raid")
local gear = require("gear")

-- the slots of the items the model knows: tier (head, shoulders, chest, legs, hands), trinkets, relic
M.GEAR_SLOTS = { 1, 3, 5, 7, 10, 13, 14, 18 }
M.GLYPH_SOCKETS = 6

-- equipped items and active glyphs -> c.gearMods (gear.effects): at scan and when the equipment,
-- glyphs or spec change (runtime.REGEAR), never per snapshot
function M.scanGear(c)
  local items, glyphs = {}, {}
  if GetInventoryItemID then
    for _, slot in ipairs(M.GEAR_SLOTS) do
      local id = GetInventoryItemID("player", slot)
      if id then items[#items + 1] = id end
    end
  end
  if GetGlyphSocketInfo then
    for i = 1, M.GLYPH_SOCKETS do
      local enabled, _, spell = GetGlyphSocketInfo(i)
      if enabled and spell then glyphs[#glyphs + 1] = spell end
    end
  end
  c.gearItems, c.gearGlyphs = items, glyphs
  c.gearMods = gear.effects(items, glyphs)
  -- the relic's proc buff by name (gear_data.PROCS); an unknown name: never up
  local proc = c.gearMods and c.gearMods.proc
  local name = proc and GetSpellInfo(proc.aura)
  c.procNames = proc and (name and { [name] = "proc" } or {}) or nil
end

-- S.mods (raid.effects): raid debuffs on the target from every caster, the player's buffs the
-- group gives, which earth and air totems are our own, the equipment. One more pass over the
-- target's auras per snapshot (the search reads the result, never the client).
function M.mods(c, S, now)
  local deb = S.target.exists and M.auras("target", "HARMFUL", c.raidDebuffs, false, now) or nil
  local buffs = M.auras("player", "HELPFUL", c.raidBuffs, false, now)
  local earth = M.totem(M.SLOT.earth, c.raidTotems, now)
  local air = M.totem(M.SLOT.air, c.raidTotems, now)
  return raid.effects(deb, buffs, { earth = earth, air = air }, c.gearMods)
end
--@end

M.BUFFS = { [53817] = "mw", [49281] = "ls", [16280] = "flurry", [30823] = "rage", [2825] = "lust", [32182] = "lust", [16166] = "em",
  -- Water Shield: matched by name, so rank 1 stands for all ranks (not a castable action here)
  [52127] = "ws" }
M.DEBUFFS = { [8050] = "fs", [17364] = "ss" }
M.TOTEMS = { [2894] = "fireElemental", [8190] = "magma", [3599] = "searing" }
M.ENCHANTS = { [8232] = "wf", [8024] = "ft", [8017] = "rb" }
M.SLOT = { fire = 1, earth = 2, water = 3, air = 4 }
M.LB_BASE = { 1.5, 2.0 }
M.ENCHANT_RESCAN = 5
M.TWO_HAND_SPEED = 3.0
-- a single stray reading must not break the held plan: leaving melee and starting to move count only after they last
M.RANGE_HOLD = 0.4
M.MOVE_HOLD = 0.3
M.RANGE_PROBES = { { "stormstrike", "melee" }, { "lavaLash", "melee" }, { "earthShock", "20" }, { "lightningBolt", "30" } }
M.HP_BY_LEVEL = { { 1, 42 }, { 10, 200 }, { 20, 600 }, { 30, 1200 }, { 40, 2000 }, { 50, 3500 }, { 60, 4500 }, { 70, 7000 }, { 80, 12000 }, { 83, 14000 } }
M.BASE_MANA = { { 1, 55 }, { 10, 185 }, { 20, 410 }, { 30, 635 }, { 40, 860 }, { 50, 1085 }, { 60, 1520 }, { 70, 2678 }, { 80, 4396 } }
M.SHIELD_PREFS = { auto = true, lightning = true, water = true }
M.CLASS_MULT = { normal = 1, trivial = 1, minus = 0.5, rare = 1.5, elite = 3, rareelite = 3, worldboss = 100 }

local CR_HIT_MELEE, CR_HIT_SPELL, CR_HASTE_MELEE, CR_HASTE_SPELL = 6, 8, 18, 20

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

local function namesOf(ids, strip)
  local out = {}
  for id, key in pairs(ids) do
    local name = GetSpellInfo(id)
    if name then
      if strip then name = (name:gsub(" Weapon$", "")) end
      out[name] = key
    end
  end
  return out
end

function M.scan(talentNames)
  local c = {
    names = {}, keyByName = {}, known = {},
    buffNames = namesOf(M.BUFFS), debuffNames = namesOf(M.DEBUFFS),
    totemNames = namesOf(M.TOTEMS), enchantNames = namesOf(M.ENCHANTS, true),
    enchant = {}, enchantAt = -math.huge, enchantSig = nil,
  }
  for _, meta in ipairs(spells.CATALOG) do
    local name = GetSpellInfo(meta.ranks[1])
    if name then
      c.names[meta.key] = name
      c.keyByName[name] = meta.key
      for i = #meta.ranks, 1, -1 do
        if IsSpellKnown(meta.ranks[i]) then
          c.known[meta.key] = { id = meta.ranks[i], rank = i }
          break
        end
      end
      if not c.known[meta.key] then
        local _, rankText = GetSpellInfo(name)
        if rankText then
          local r = math.min(#meta.ranks, tonumber(rankText:match("%d+")) or 1)
          c.known[meta.key] = { id = meta.ranks[r], rank = r }
        end
      end
    end
  end
  --@addon
  c.raidDebuffs, c.raidBuffs, c.raidTotems = namesOf(raid.DEBUFFS), namesOf(raid.BUFFS), namesOf(raid.OWN_TOTEMS)
  M.scanGear(c)
  --@end
  c.talents = talents.read(GetNumTalentTabs, GetNumTalents, GetTalentInfo, talentNames)
  return c
end

function M.auras(unit, filter, names, mineOnly, now)
  local out = {}
  for i = 1, 40 do
    local name, _, _, count, _, _, expires, caster = UnitAura(unit, i, filter)
    if not name then break end
    local key = names[name]
    if key and (not mineOnly or caster == "player") then
      local remains = (expires and expires > 0) and math.max(0, expires - now) or 600
      local prev = out[key]
      if not prev or remains > prev.remains then out[key] = { count = count or 0, remains = remains } end
    end
  end
  return out
end

function M.tooltip()
  return EnhRotScanTip or CreateFrame("GameTooltip", "EnhRotScanTip", nil, "GameTooltipTemplate")
end

-- imbue kind and the weapon's own speed ("Speed 2.70", "Скорость 2,70") from the item tooltip
function M.enchantOf(tip, slot, names)
  tip:SetOwner(WorldFrame, "ANCHOR_NONE")
  tip:ClearLines()
  tip:SetInventoryItem("player", slot)
  local found, speed
  local regions = { tip:GetRegions() }
  for _, r in ipairs(regions) do
    if r:GetObjectType() == "FontString" and r:IsShown() then
      local text = r:GetText()
      if text then
        if not found then
          for base, kind in pairs(names) do
            if text:find(base, 1, true) then found = kind; break end
          end
        end
        local a, b = text:match("^%D+(%d)[%.,](%d%d)$")
        if a and not speed then speed = tonumber(a .. "." .. b) end
      end
    end
  end
  return found, speed
end

function M.enchants(c, now)
  local hasMH, _, _, hasOH = GetWeaponEnchantInfo()
  -- the equipped items too: a weapon swap with the same imbues changes the tooltip speed
  local link = GetInventoryItemLink
  local sig = tostring(hasMH) .. "/" .. tostring(hasOH) .. "/" .. tostring(link and link("player", 16))
    .. "/" .. tostring(link and link("player", 17))
  if sig ~= c.enchantSig or now - c.enchantAt > M.ENCHANT_RESCAN then
    local tip = M.tooltip()
    local mh, mhSpeed = M.enchantOf(tip, 16, c.enchantNames)
    local oh, ohSpeed = M.enchantOf(tip, 17, c.enchantNames)
    c.enchant = {
      -- present but not Windfury/Flametongue/Rockbiter (Frostbrand, Earthliving): "other"
      mh = hasMH and (mh or "other") or nil,
      oh = hasOH and (oh or "other") or nil,
      mhSpeed = mhSpeed, ohSpeed = ohSpeed,
    }
    c.enchantSig, c.enchantAt = sig, now
  end
  return c.enchant
end

function M.totem(slot, names, now)
  local have, name, start, dur = GetTotemInfo(slot)
  if not have or not name or name == "" then return nil, 0 end
  local remains = math.max(0, (start or 0) + (dur or 0) - now)
  for base, kind in pairs(names) do
    if name:find(base, 1, true) then return kind, remains end
  end
  return "other", remains
end

function M.guessHealth(level, classification)
  return interp(M.HP_BY_LEVEL, level) * (M.CLASS_MULT[classification] or 1)
end

function M.mode(override)
  if override and override ~= "auto" then return override end
  if (GetNumRaidMembers() or 0) > 0 then return "raid" end
  if (GetNumPartyMembers() or 0) > 0 then return "group" end
  return "solo"
end

function M.range(c)
  local meleeProbed = false
  for _, p in ipairs(M.RANGE_PROBES) do
    local key, band = p[1], p[2]
    local name = c.known[key] and c.names[key]
    if name then
      if band == "melee" then
        meleeProbed = true
      elseif not meleeProbed then
        meleeProbed = true
        if CheckInteractDistance("target", 3) then return "melee" end
      end
      if IsSpellInRange(name, "target") == 1 then return band end
    end
  end
  return "far"
end

-- per target: a new target and getting closer apply at once, leaving melee only after RANGE_HOLD of such readings
function M.heldRange(ctx, guid, raw, now)
  local h = ctx.rangeHold
  if not h then
    h = {}
    ctx.rangeHold = h
  end
  if not guid or h.guid ~= guid or raw == "melee" or h.value ~= "melee" then
    h.guid, h.value, h.since = guid, raw, nil
    return raw
  end
  h.since = h.since or now
  if now - h.since >= M.RANGE_HOLD then
    h.value, h.since = raw, nil
    return raw
  end
  return "melee"
end

-- a short shuffle is not movement: report it after MOVE_HOLD of continuous movement
function M.moving(ctx, now)
  if (GetUnitSpeed("player") or 0) <= 0 then
    ctx.moveSince = nil
    return false
  end
  ctx.moveSince = ctx.moveSince or now
  return now - ctx.moveSince >= M.MOVE_HOLD
end

function M.spellHaste(c, mw)
  local rating = 1 + (GetCombatRatingBonus(CR_HASTE_SPELL) or 0) / 100
  local k, name = c.known.lightningBolt, c.names.lightningBolt
  if not k or not name then return rating end
  local castMs = select(7, GetSpellInfo(name))
  local base = (M.LB_BASE[k.rank] or 2.5) * (1 - 0.2 * math.min(5, mw or 0))
  if not castMs or castMs <= 0 or base <= 0 then return rating end
  return math.max(1, math.min(3, base / (castMs / 1000)))
end

function M.playerInfo(haste, moving)
  local base, pos, neg = UnitAttackPower("player")
  local hpMax = UnitHealthMax("player") or 0
  local level = UnitLevel("player") or 1
  return {
    level = level,
    mana = UnitPower("player", 0) or 0,
    manaMax = UnitPowerMax("player", 0) or 0,
    baseMana = math.floor(interp(M.BASE_MANA, level) + 0.5),
    hpPct = hpMax > 0 and (UnitHealth("player") or 0) / hpMax or 1,
    ap = (base or 0) + (pos or 0) + (neg or 0),
    spNature = GetSpellBonusDamage(4) or 0,
    spFire = GetSpellBonusDamage(3) or 0,
    meleeCrit = (GetCritChance() or 0) / 100,
    spellCrit = (GetSpellCritChance(4) or 0) / 100,
    meleeHit = ((GetCombatRatingBonus(CR_HIT_MELEE) or 0) + (GetHitModifier and GetHitModifier() or 0)) / 100,
    spellHit = ((GetCombatRatingBonus(CR_HIT_SPELL) or 0) + (GetSpellHitModifier and GetSpellHitModifier() or 0)) / 100,
    spellHaste = haste,
    meleeHaste = 1 + (GetCombatRatingBonus(CR_HASTE_MELEE) or 0) / 100,
    moving = moving and true or false,
    inCombat = UnitAffectingCombat("player") and true or false,
  }
end

-- equip slot from the item when the client gives it, otherwise by speed (two-handers are slow)
function M.twoHand(speed)
  local link = GetInventoryItemLink and GetInventoryItemLink("player", 16)
  if link and GetItemInfo then
    local loc = select(9, GetItemInfo(link))
    if loc then return loc == "INVTYPE_2HWEAPON" end
  end
  return (speed or 0) >= M.TWO_HAND_SPEED
end

function M.weapons(c, now)
  local mhSpeed, ohSpeed = UnitAttackSpeed("player")
  local minMH, maxMH, minOH, maxOH = UnitDamage("player")
  local ench = M.enchants(c, now)
  local w = { mh = { speed = mhSpeed or 2.0, base = ench.mhSpeed, min = minMH or 0, max = maxMH or 0, enchant = ench.mh } }
  if ohSpeed and ohSpeed > 0 then
    w.oh = { speed = ohSpeed, base = ench.ohSpeed, min = minOH or 0, max = maxOH or 0, enchant = ench.oh }
  elseif M.twoHand(ench.mhSpeed or w.mh.speed) then
    w.mh.twoHand = true
  end
  return w
end

function M.spellInfo(c, now)
  local out = {}
  for key, k in pairs(c.known) do
    local name = c.names[key]
    local _, _, _, cost, _, _, castMs = GetSpellInfo(name)
    local st, dur = GetSpellCooldown(name)
    local cd = 0
    if st and st > 0 and dur and dur > 1.5 then cd = math.max(0, st + dur - now) end
    out[key] = { id = k.id, rank = k.rank, cd = cd, cost = cost or 0, cast = (castMs or 0) / 1000 }
  end
  return out
end

function M.targetInfo(ctx, c, now, playerLevel)
  local t = { exists = false, enemy = false, level = 0, hp = 0, hpMax = 0, hpPct = 0, ttd = nil, range = "far",
              isBoss = false, fs = 0, ss = { charges = 0, remains = 0 }, guessed = false }
  if not UnitExists("target") or UnitIsDeadOrGhost("target") then
    if ctx.rangeHold then ctx.rangeHold.guid = nil end
    return t
  end
  t.exists = true
  t.enemy = UnitCanAttack("player", "target") and true or false
  local level = UnitLevel("target") or 0
  t.isBoss = level == -1 or UnitClassification("target") == "worldboss"
  if level <= 0 then
    level = playerLevel + 3
    t.guessed = true
  end
  t.level = level
  local hp, hpMax = UnitHealth("target") or 0, UnitHealthMax("target") or 0
  t.hpPct = hpMax > 0 and hp / hpMax or 0
  if hpMax == 100 and not UnitIsPlayer("target") then
    hpMax = M.guessHealth(level, UnitClassification("target"))
    hp = hpMax * t.hpPct
    t.guessed = true
  end
  t.hp, t.hpMax = hp, hpMax
  local guid = UnitGUID("target")
  -- the estimate itself is read in build: its prior needs the whole state
  if t.enemy and guid and ctx.ttd then ctx.ttd:add(now, guid, t.hpPct) end
  local deb = M.auras("target", "HARMFUL", c.debuffNames, true, now)
  if deb.fs then t.fs = deb.fs.remains end
  if deb.ss then t.ss = { charges = deb.ss.count, remains = deb.ss.remains } end
  t.range = M.heldRange(ctx, guid, M.range(c), now)
  -- fighting us: both in combat, or our Flame Shock on it (model: a mob like that runs in)
  t.isPlayer = UnitIsPlayer("target") and true or false
  t.inCombat = (t.fs > 0 or (UnitAffectingCombat("target") and UnitAffectingCombat("player"))) and true or false
  return t
end

-- Expected seconds to kill the target from what the state knows, for the young regression
-- (ttd): health / (the character's damage per second + the Flame Shock and fire totem already
-- ticking on it). In a party every other member adds GROUP_MATE of that rate (issue #22, Dire Maul
-- in a party of five: our 239K of the group's 739K, the group killing ~3.1x as fast as we alone):
-- without a prior a young regression read 736 s on a mob that died in ~27 s, and nothing while it
-- had seen no decline. Not in a raid: twenty-odd players' damage says nothing of ours. Only while
-- the mob fights us: before the pull nothing is killing it.
M.GROUP_MATE = 0.55
function M.ttdPrior(S)
  local t = S.target
  if (S.mode ~= "solo" and S.mode ~= "group") or not t.enemy or (t.hp or 0) <= 0 or not S.player.inCombat then return nil end
  local fighting = t.inCombat
  if fighting == nil then fighting = UnitAffectingCombat("target") or (t.fs or 0) > 0 end
  if not fighting then return nil end
  local dps = value.dpsEstimate(S)
  local fire = S.totems.fire
  local src = fire.kind and value.FIRE_SOURCE[fire.kind]
  if (t.fs or 0) > 0 or (src and fire.remains > 0) then
    local r = damage.rates(S)
    if (t.fs or 0) > 0 then dps = dps + r.flameShock end
    if src and fire.remains > 0 then dps = dps + r[src] end
  end
  if dps <= 0 then return nil end
  if S.mode == "group" then dps = dps * (1 + M.GROUP_MATE * (GetNumPartyMembers() or 0)) end
  return t.hp / dps
end

-- The long cooldowns' gate for this snapshot (model.cooldownAllowed reads it along the whole
-- plan): S.cdAllowed[key] = true / false for every gated key, nil without options. "auto" is
-- latched per target: once allowed it holds until ttd < need x model.COOLDOWN_RELEASE, so a noisy
-- ttd near the line does not flip the first button. Latches are kept for the last
-- M.LATCH_TARGETS GUIDs (ctx.cdLatch = { slot, ... }, most recently seen first, slot =
-- { guid = ..., [key] = true }): a tank swap or dotting another mob and coming back keeps the
-- first target's latch; the least recently seen one is dropped. No options clears them all.
M.LATCH_TARGETS = 3

-- The latch slot for guid, moved to the front; a new table only for a GUID not seen among the
-- kept ones (the least recently seen slot is dropped past M.LATCH_TARGETS).
local function latchFor(ctx, guid)
  local list = ctx.cdLatch
  if not list then
    list = {}
    ctx.cdLatch = list
  end
  local n, at = #list, nil
  for i = 1, n do
    if list[i].guid == guid then at = i break end
  end
  local slot
  if at then
    slot = list[at]
  else
    slot = { guid = guid }
    at = n < M.LATCH_TARGETS and n + 1 or n
  end
  for i = at, 2, -1 do list[i] = list[i - 1] end
  list[1] = slot
  return slot
end

function M.cooldownGate(ctx, S, guid)
  if not S.cooldowns then
    ctx.cdLatch = nil
    return nil
  end
  -- no target: decided without a latch, the kept ones stay as they are
  local latch = guid ~= nil and latchFor(ctx, guid) or nil
  local out = {}
  for key in pairs(model.COOLDOWN_TTD) do
    local ok = model.cooldownDecide(S, key, latch ~= nil and latch[key])
    out[key] = ok
    -- only "auto" on a known target latches (a boss or "always" needs no memory)
    if latch then latch[key] = (ok and S.cooldowns[key] == "auto") or nil end
  end
  return out
end

function M.targetTtd(ctx, S, now)
  local t = S.target
  local guid = t.enemy and ctx.ttd and UnitGUID("target")
  if not guid then return end
  t.ttd, t.ttdSource = ctx.ttd:smoothed(now, guid, M.ttdPrior(S))
end

-- A mob fighting us at 20-30 yards comes to melee (model.advance counts meleeIn down); as
-- model.canApproach: solo only (in a group it runs to the tank), never a player. A mob not in
-- combat stays where it is: it comes only when pulled (model.applyOn), or the player walks in.
function M.meleeIn(S)
  local t = S.target
  local eta = util.approachEta(t.range)
  if eta and S.mode == "solo" and t.exists and t.enemy and t.inCombat and not t.isPlayer then return eta end
  return nil
end

function M.swingInfo(ctx, now, weapons)
  local st = ctx.swing and ctx.swing:state(now)
  if not st then
    st = { attacking = false, mh = { next = 0, speed = weapons.mh.speed },
           oh = weapons.oh and { next = 0, speed = weapons.oh.speed } or nil }
  end
  if ctx.attacking ~= nil then st.attacking = ctx.attacking end
  st.resetByInstant = st.resetByInstant or {}
  return st
end

function M.inflight(src, now)
  local out = {}
  if not src then return out end
  for key, untilAt in pairs(src) do
    if untilAt > now then out[key] = untilAt - now else src[key] = nil end
  end
  return out
end

local function charges(a) return a and math.max(1, a.count) or 0 end
local function remains(a) return a and a.remains or 0 end

-- Latency: the median gap between a press (UNIT_SPELLCAST_SENT) and the server's answer (START of
-- a cast, SUCCEEDED of an instant) over the session's last PING_N presses (runtime.onCast). That
-- is what a press really takes, the server's tick included. GetNetStats is the home latency the
-- client refreshes every 30 s, without the server's part; + 0.1 stood in for it, and still does
-- until PING_MIN presses are measured. The median: one lag spike moves it little.
M.PING_N, M.PING_MIN = 15, 3

-- p = { n, i, median, [1..PING_N] }: a ring of the last samples
function M.addPing(p, dt)
  if dt < 0 then return end
  local n, i = p.n or 0, (p.i or 0) % M.PING_N + 1
  p.i, p[i] = i, dt
  if n < M.PING_N then n = n + 1; p.n = n end
  local s = {}
  for k = 1, n do s[k] = p[k] end
  table.sort(s)
  local m = math.floor((n + 1) / 2)
  p.median = n % 2 == 1 and s[m] or (s[m] + s[m + 1]) / 2
end

function M.latency(p, netMs)
  if p and (p.n or 0) >= M.PING_MIN then return p.median end
  return (netMs or 0) / 1000 + 0.1
end

function M.build(ctx)
  local now = ctx.now or GetTime()
  local c = ctx.cache or M.scan()
  ctx.cache = c
  local mine = M.auras("player", "HELPFUL", c.buffNames, false, now)
  local mw = mine.mw and mine.mw.count or 0
  local haste = M.spellHaste(c, mw)
  local S = { now = now, gcdRemains = 0, castRemains = 0, gcd = math.max(1.0, 1.5 / haste), mode = M.mode(ctx.mode) }
  local _, _, latMs = GetNetStats()
  S.latency = M.latency(ctx.ping, latMs)
  local gcdName = c.names.lightningBolt
  if gcdName then
    local st, dur = GetSpellCooldown(gcdName)
    if st and st > 0 and dur and dur > 0 and dur <= 1.51 then S.gcdRemains = math.max(0, st + dur - now) end
  end
  local _, _, _, _, _, endMs = UnitCastingInfo("player")
  if endMs then S.castRemains = math.max(0, endMs / 1000 - now) end
  S.player = M.playerInfo(haste, M.moving(ctx, now))
  S.weapons = M.weapons(c, now)
  S.talents = c.talents or {}
  S.spells = M.spellInfo(c, now)
  S.buffs = {
    mw = { stacks = mw, remains = remains(mine.mw) },
    ls = { charges = charges(mine.ls), remains = remains(mine.ls) },
    ws = mine.ws and { charges = charges(mine.ws), remains = remains(mine.ws) } or nil,
    flurry = { charges = charges(mine.flurry), remains = remains(mine.flurry) },
    rage = remains(mine.rage), lust = remains(mine.lust), em = remains(mine.em),
  }
  S.player.shield = (mine.ls and "lightning") or (mine.ws and "water") or nil
  S.shieldPref = M.SHIELD_PREFS[ctx.shield] and ctx.shield or "auto"
  S.target = M.targetInfo(ctx, c, now, S.player.level)
  S.target.meleeIn = M.meleeIn(S)
  S.cooldowns = ctx.cooldowns -- the player's options for the long cooldowns (read-only, shared)
  S.weaveMin = ctx.weaveMin -- the weaving option (nil: the model decides, as before the option)
  S.manaPolicy = ctx.manaPolicy -- solo mana option (value.MANA_POLICY; nil: balanced)
  local fireKind, fireRemains = M.totem(M.SLOT.fire, c.totemNames, now)
  local _, waterRemains = M.totem(M.SLOT.water, c.totemNames, now)
  S.totems = { fire = { kind = fireKind, remains = fireRemains }, water = { remains = waterRemains } }
  --@addon
  S.mods = M.mods(c, S, now)
  -- the relic's proc buff: the model carries it along the plan (stacks at least 1 while up)
  if c.procNames then
    local a = M.auras("player", "HELPFUL", c.procNames, false, now).proc
    -- the item's own passive may share the proc buff's name: one that outlasts the proc is not it
    local p = S.mods and S.mods.proc
    if a and p and a.remains > p.duration then a = nil end
    S.buffs.relic = { stacks = a and math.max(1, a.count) or 0, remains = a and a.remains or 0 }
  end
  --@end
  S.swing = M.swingInfo(ctx, now, S.weapons)
  local melee, nearby = 0, 0
  if ctx.enemies then melee, nearby = ctx.enemies:counts(now) end
  if S.target.exists and S.target.enemy then
    nearby = math.max(nearby, 1)
    if S.target.range == "melee" then melee = math.max(melee, 1) end
  end
  S.enemies = { melee = melee, nearby = nearby }
  S.inflight = M.inflight(ctx.inflight, now)
  S.pets = { wolves = math.max(0, (ctx.wolvesUntil or 0) - now) }
  M.targetTtd(ctx, S, now)
  S.cdAllowed = M.cooldownGate(ctx, S, S.target.exists and UnitGUID("target") or nil)
  return S
end

return M
