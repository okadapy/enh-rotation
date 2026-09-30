local spells = require("spells")
local swing = require("swing")
local enemies = require("enemies")
local ttd = require("ttd")
local snapshot = require("snapshot")
local planner = require("planner")
local timeline = require("timeline")
local recorder = require("recorder")
local version = require("version")
local util = require("util")

local M = {}

M.PULSE = 0.25
M.FRAME_MS = 2 -- search time per frame; a search runs over several frames (planner.work)
M.RECORD_MAX = 30
M.PRESS_MAX = 200
M.VERSION = version
M.MODES = { "auto", "solo", "group", "raid", "pvp" }
M.SHIELDS = { "auto", "lightning", "water" } -- option "shield" (select index) -> S.shieldPref
M.EVENTS = {
  "COMBAT_LOG_EVENT_UNFILTERED",
  "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
  "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_DELAYED",
  "UNIT_AURA", "PLAYER_TARGET_CHANGED", "UNIT_MANA", "PLAYER_TOTEM_UPDATE", "UNIT_ATTACK_SPEED",
  "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
}
M.RESCAN = { SPELLS_CHANGED = true, LEARNED_SPELL_IN_TAB = true, PLAYER_LEVEL_UP = true, CHARACTER_POINTS_CHANGED = true, PLAYER_TALENT_UPDATE = true }
M.PRIORITY = { cast = 6, target = 5, swing = 4, aura = 3, totem = 2, power = 1, pulse = 0 }
M.WAIT_KEYS = { waitSwing = true, wait = true }
M.SENT_WINDOW = 1.0 -- s: a START / SUCCEEDED this soon after SENT of the same spell confirms that press
M.THROTTLED = { aura = true, power = true, swing = true }
M.MIN_GAP = 0.1
M.SLEEP_POLL = 1
M.LUST_IDS = { 2825, 32182 }
M.DEATH = { UNIT_DIED = true, UNIT_DESTROYED = true, PARTY_KILL = true }
M.WOLVES = spells.byKey.feralSpirit.duration or 45
M.ATTACK_ID = 6603
M.ALERT_ICONS = {
  noEnchant = "Interface\\Icons\\Spell_Nature_Cyclone",
  outOfRange = "Interface\\Icons\\Ability_Rogue_Sprint",
  moveIn = "Interface\\Icons\\Ability_Rogue_Sprint",
  autoAttack = "Interface\\Icons\\INV_Sword_04",
  waterShield = "Interface\\Icons\\Ability_Shaman_WaterShield",
}

function M.validPlan(plan)
  if type(plan) ~= "table" or type(plan.steps) ~= "table" then return false end
  for _, st in ipairs(plan.steps) do
    if type(st) ~= "table" or type(st.at) ~= "number" then return false end
    if st.at ~= st.at or st.at < -1 or st.at > 60 then return false end
    if not (spells.byKey[st.key] or M.WAIT_KEYS[st.key]) then return false end
  end
  return true
end

local function withIcon(a)
  local meta = spells.byKey[a.key]
  a.icon = (meta and meta.icon) or M.ALERT_ICONS[a.key]
  return a
end

function M.alert(S)
  local sp, b, w = S.spells, S.buffs, S.weapons
  local t = S.target
  local melee = t.exists and t.enemy and t.range == "melee"
  -- in melee reach without auto-attack: no swings, no Maelstrom, no mana from Shamanistic Rage;
  -- first, it costs more than any missing buff (recorded in game: whole fights like that)
  if melee and S.swing and not S.swing.attacking then
    return withIcon({ key = "autoAttack", reason = "Auto-attack is off" })
  end
  -- not while the cast is on its way (the aura comes a moment after the cast)
  if util.wantsLightningShield(S) then
    if sp.lightningShield and b.ls.charges <= 0 and not (S.inflight and S.inflight.lightningShield) then
      return withIcon({ key = "lightningShield", reason = "Lightning Shield missing" })
    end
  elseif S.shieldPref == "water" and not (S.player and S.player.shield == "water") then
    return withIcon({ key = "waterShield", reason = "Water Shield missing" })
  end
  if (w.mh and not w.mh.enchant) or (w.oh and not w.oh.enchant) then
    return withIcon({ key = "noEnchant", reason = "Weapon imbue missing" })
  end
  -- Shamanistic Rage returns mana only through melee hits: not at range, not without auto-attack
  local rage = sp.shamanisticRage
  if rage and melee and S.player.manaMax > 0 and S.player.mana / S.player.manaMax < 0.2
    and rage.cd <= (S.gcdRemains or 0) + 0.1 then
    return withIcon({ key = "shamanisticRage", reason = "Low mana: Shamanistic Rage" })
  end
  if t.exists and t.enemy and t.range == "far" then
    return withIcon({ key = "outOfRange", reason = "Target out of range" })
  end
  return nil
end

-- Sated (Bloodlust) / Exhaustion (Heroism): the buff cannot land again for 10 min
M.SATED_IDS = { [57724] = true, [57723] = true }

local function sated()
  for i = 1, 40 do
    local name, _, _, _, _, _, _, _, _, _, id = UnitAura("player", i, "HARMFUL")
    if not name then return false end
    if M.SATED_IDS[id] then return true end
    for sid in pairs(M.SATED_IDS) do
      if name == GetSpellInfo(sid) then return true end
    end
  end
  return false
end

function M.lustReady(S, now)
  if S.mode ~= "group" and S.mode ~= "raid" then return nil end
  if sated() then return nil end
  for _, id in ipairs(M.LUST_IDS) do
    local name = GetSpellInfo(id)
    if name and GetSpellInfo(name) then
      local st, dur = GetSpellCooldown(name)
      if not st or st == 0 or st + dur - now <= 0 then
        local _, _, icon = GetSpellInfo(name)
        return { key = "lust", icon = icon, reason = name .. " ready" }
      end
    end
  end
  return nil
end

function M.signature(plan, c)
  local parts = {}
  for _, st in ipairs(plan.steps) do parts[#parts + 1] = ("%s@%.1f"):format(st.key, st.at) end
  return ("EnhRot: %s | replans=%d capped=%d errors=%d"):format(table.concat(parts, " "), c.replans, c.capped, c.errors)
end

function M.report(rt, msg)
  rt.counters.errors = rt.counters.errors + 1
  if rt.reported then return end
  rt.reported = true
  print("|cffff5555EnhRot|r " .. msg)
end

-- done: the end (or pushback) of a cast whose START was already reported - no new press
function M.mark(rt, kind, key, done)
  local p = rt.pending
  if not p or M.PRIORITY[kind] > M.PRIORITY[p.kind]
    or (kind == p.kind and key and (not p.key or (p.done and not done))) then
    rt.pending = { kind = kind, key = key, done = done or nil }
  end
end

-- the press of key was already reported by UNIT_SPELLCAST_SENT (and is still in flight)
local function sentFor(rt, key, now)
  local s = rt.sent
  return s and s.key == key and now - s.at <= M.SENT_WINDOW
end

local function mwNow(ctx, now)
  local a = snapshot.auras("player", "HELPFUL", ctx.cache.buffNames, false, now)
  return a.mw and a.mw.count or 0
end

-- The first shown button and since when it is due: replans that keep suggesting it at 0 do not
-- move that moment on (the delay of a press is counted from it).
function M.trackDue(rt, plan, now)
  local st = plan and plan.steps[1]
  local d = rt.due
  if not st then
    rt.due = nil
  elseif d and d.key == st.key then
    if d.at > now then d.at = now + st.at end
  else
    rt.due = { key = st.key, at = now + st.at }
  end
end

-- press log (recording on): what was pressed against what was shown
local function logPress(rt, key, now)
  if not rt.rec then return end
  local d = rt.due
  rt.rec:press(key, now, rt.plan, d and d.at)
end

-- the event belongs to the tracked hard cast (castID = 4th argument of UNIT_SPELLCAST_* in 3.3.5a)
local function ownCast(rt, key, castID)
  local c = rt.casting
  return c and c.key == key and (castID == nil or c.id == nil or castID == c.id)
end

function M.onCast(rt, event, key, now, castID)
  local ctx = rt.ctx
  local done = false
  if event == "UNIT_SPELLCAST_SENT" then
    -- the key press itself: the client starts the GCD at once, the server confirms a round trip
    -- later. Taken as the press now, so the plan does not show the pressed button for that time.
    rt.sent = { key = key, at = now }
    logPress(rt, key, now)
    M.mark(rt, "cast", key)
    return
  end
  local confirmed = sentFor(rt, key, now)
  if confirmed and rt.rec and (event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_SUCCEEDED") then
    rt.rec:confirm(key)
  end
  if event == "UNIT_SPELLCAST_START" then
    done = confirmed
    if confirmed then rt.sent = nil end
    local _, _, _, _, startMs, endMs, _, id = UnitCastingInfo("player")
    local castTime = (startMs and endMs) and (endMs - startMs) / 1000 or 0
    rt.casting = { key = key, mw = mwNow(ctx, now), id = castID or id }
    ctx.swing:onCastStart(now, key, rt.casting.mw, castTime)
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    if confirmed then rt.sent = nil end
    if ownCast(rt, key, castID) then
      ctx.swing:onCastEnd(now, key, rt.casting.mw, true)
      rt.casting = nil
      done = true
    else
      done = confirmed
      -- a 5-stack Lightning Bolt is instant too, but it is no sample of an instant spell
      if (spells.byKey[key].castBase or 0) <= 0 then ctx.swing:onInstant(now, key) end
    end
    ctx.inflight[key] = now + 1
    if key == "feralSpirit" then ctx.wolvesUntil = now + M.WOLVES end
  elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
    -- FAILED also comes for a button pressed during the own cast ("Another action is in progress")
    local stillCasting = event == "UNIT_SPELLCAST_FAILED" and castID == nil and UnitCastingInfo("player") ~= nil
    if ownCast(rt, key, castID) and not stillCasting then
      ctx.swing:onCastEnd(now, key, rt.casting.mw, false)
      rt.casting = nil
    end
    ctx.inflight[key] = nil
    -- Replan, but nothing was cast. A press taken at SENT is not taken back: a second tap during
    -- the GCD fails in the client with the same event, and the first press is real. A press the
    -- server really turned down comes back once the planner's in-flight mark runs out (1 s).
    M.mark(rt, "cast")
    return
  elseif event == "UNIT_SPELLCAST_DELAYED" then
    local endMs = select(6, UnitCastingInfo("player"))
    if endMs and rt.casting and rt.casting.key == key then ctx.swing:onCastDelayed(now, endMs / 1000) end
    done = true
  else
    return
  end
  -- START / SUCCEEDED without SENT before it: the press itself (SENT did not come)
  if not done then logPress(rt, key, now) end
  M.mark(rt, "cast", key, done)
end

-- 3.3.5a: timestamp, event, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, ...
function M.onCombatLog(rt, now, _, sub, src, _, _, dst, _, _, _, a2, _, a4)
  local ctx, pg, mine = rt.ctx, rt.playerGUID, rt.mine
  if M.DEATH[sub] then
    if dst then
      ctx.enemies:onEvent(now, sub, src, dst, pg)
      ctx.ttd:reset(dst)
      mine[dst] = nil
      if dst == UnitGUID("target") then M.mark(rt, "target") end
    end
    return
  end
  -- totems and wolves hit enemies too; enemies counts them as the player's
  -- Fire Elemental Totem summons the elemental itself: the totem's summons are ours too
  if sub == "SPELL_SUMMON" and dst and (src == pg or (src and mine[src])) then mine[dst] = true end
  if src ~= pg and dst ~= pg and not (src and mine[src]) and not (dst and mine[dst]) then return end
  ctx.enemies:onEvent(now, sub, src, dst, pg)
  if src ~= pg then return end
  if sub == "SWING_DAMAGE" or sub == "SWING_MISSED" then
    ctx.swing:onSwing(now, false)
    M.mark(rt, "swing")
  elseif sub == "SPELL_EXTRA_ATTACKS" then
    ctx.swing:onExtraAttacks(now, a4 or 1)
  elseif sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REFRESH" or sub == "SPELL_AURA_APPLIED_DOSE" then
    local key = ctx.cache.keyByName[a2]
    if key then ctx.inflight[key] = nil end
    M.mark(rt, "aura")
  end
end

function M.onEvent(rt, event, ...)
  local now = GetTime()
  local ctx = rt.ctx
  if event == "COMBAT_LOG_EVENT_UNFILTERED" then
    M.onCombatLog(rt, now, ...)
  elseif event:sub(1, 15) == "UNIT_SPELLCAST_" then
    local unit, name, _, castID = ...
    if unit ~= "player" then return end
    local key = ctx.cache.keyByName[name]
    if key then M.onCast(rt, event, key, now, castID) end
  elseif event == "UNIT_AURA" then
    local unit = ...
    if unit == "player" or unit == "target" then M.mark(rt, "aura") end
  elseif event == "PLAYER_TARGET_CHANGED" then
    M.mark(rt, "target")
  elseif event == "UNIT_MANA" then
    if (...) == "player" then M.mark(rt, "power") end
  elseif event == "PLAYER_TOTEM_UPDATE" then
    M.mark(rt, "totem")
  elseif event == "UNIT_ATTACK_SPEED" then
    if (...) == "player" then
      local mh, oh = UnitAttackSpeed("player")
      ctx.swing:onSpeed(now, mh, oh)
      M.mark(rt, "swing")
    end
  elseif event == "PLAYER_ENTER_COMBAT" or event == "PLAYER_LEAVE_COMBAT" then
    ctx.attacking = event == "PLAYER_ENTER_COMBAT"
    ctx.swing:onAttack(now, ctx.attacking)
    M.mark(rt, "swing")
  elseif event == "PLAYER_REGEN_ENABLED" then
    ctx.enemies = enemies.new()
    ctx.ttd:reset()
    rt.mine = {}
    rt.planner = M.newPlanner()
  elseif event == "PLAYER_ENTERING_WORLD" then
    rt.playerGUID = UnitGUID("player")
    rt.shown = false
    ctx.swing:onSpeed(now, UnitAttackSpeed("player"))
  elseif M.RESCAN[event] then
    ctx.cache = snapshot.scan()
    M.checkTalents(rt)
    M.mark(rt, "target")
  end
end

-- The sandbox offers no protected calls: a Lua error inside one update leaves rt.busy set.
-- The next frame sees it and stops the engine instead of repeating the error every frame.
function M.update(rt, dt)
  if rt.stopped then return false end
  if rt.busy then
    M.fail(rt)
    return false
  end
  rt.busy = true
  local r = M.step(rt, dt)
  rt.busy = false
  return r
end

function M.fail(rt)
  rt.stopped = true
  M.halt(rt)
  rt.frame:SetScript("OnUpdate", nil)
  if not rt.failed then
    rt.failed = true
    print("|cffff5555EnhRot|r stopped after an error - /reload to retry")
  end
end

-- no events, no work, timeline hidden
function M.halt(rt)
  rt.frame:UnregisterAllEvents()
  rt.tl:stop()
end

function M.listen(frame)
  frame:UnregisterAllEvents()
  for _, e in ipairs(M.EVENTS) do frame:RegisterEvent(e) end
  for e in pairs(M.RESCAN) do frame:RegisterEvent(e) end
end

-- the host aura was hidden (unloaded, disabled): sleep, and once a second ask it to show again;
-- WeakAuras only lets that event through while the aura is loaded
function M.sleep(rt)
  if rt.stopped or rt.sleeping then return end
  rt.sleeping = true
  M.halt(rt)
  local waited = 0
  rt.frame:SetScript("OnUpdate", function(_, dt)
    waited = waited + (dt or 0)
    if waited >= M.SLEEP_POLL then
      waited = 0
      WeakAuras.ScanEvents("ENHROT_SHOW")
    end
  end)
end

function M.wake(rt)
  if rt.stopped or not rt.sleeping then return end
  rt.sleeping = false
  M.listen(rt.frame)
  rt.tl:start()
  rt.frame:SetScript("OnUpdate", function(_, dt) M.update(rt, dt) end)
  M.mark(rt, "target")
end

function M.newPlanner()
  return planner.new({ budgetMs = M.FRAME_MS })
end

-- a new plan to show (after a replan, or when a search running over several frames finished)
function M.show(rt, plan, S, now)
  if not M.validPlan(plan) then
    M.report(rt, "planner returned an invalid plan")
    return false
  end
  if plan.capped then rt.counters.capped = rt.counters.capped + 1 end
  local first = plan.steps[1] and plan.steps[1].key
  M.trackDue(rt, plan, now)
  if first ~= rt.lastFirst then
    rt.lastFirst = first
    rt.counters.replans = rt.counters.replans + 1
    if rt.rec then rt.rec:push(S, plan) end
    if rt.config.printDebug then print(M.signature(plan, rt.counters)) end
  end
  rt.plan, rt.S = plan, S
  rt.tl:render(plan, S, now)
  rt.tl:setAlert(rt.alert or M.idleHint(plan, S, rt.searching))
  return true
end

-- Nothing to press at 20-30 yards (solo, mana is dear): the timeline would be empty with no
-- hint at all. The plan values the walk to melee at nothing, the player needs to be told.
function M.idleHint(plan, S, searching)
  local t = S and S.target
  if searching or not (t and t.exists and t.enemy) or #plan.steps > 0 then return nil end
  if t.range == "20" or t.range == "30" then return withIcon({ key = "moveIn", reason = "Move into melee" }) end
  return nil
end

-- a frame without a replan: go on with the running search, show its plan once it is done
local function work(rt)
  local p, S = rt.planner, rt.S
  if not (rt.searching and p.work and S) then return false end
  if not p:work(M.FRAME_MS) then return false end
  rt.searching = p:busy()
  return M.show(rt, p:view(S.now), S, S.now)
end

-- Talents are matched by English names (talents.KEYS): on another client language every rank
-- reads as 0. Said once per session, from level 10 (the first talent point) on.
function M.checkTalents(rt)
  if rt.talentsWarned or (UnitLevel("player") or 0) < 10 then return end
  for _, rank in pairs(rt.ctx.cache.talents or {}) do
    if rank > 0 then return end
  end
  rt.talentsWarned = true
  print("|cffff5555EnhRot|r: talents not detected (non-English client?)")
end

-- nothing to suggest: dead or a ghost, on a flight path, in a vehicle, mounted out of combat
-- (UnitInVehicle / UnitHasVehicleUI exist since 3.0; checked anyway, like IsCurrentSpell)
function M.inactive()
  if UnitIsDeadOrGhost("player") then return "dead" end
  if UnitOnTaxi and UnitOnTaxi("player") then return "taxi" end
  if (UnitInVehicle and UnitInVehicle("player")) or (UnitHasVehicleUI and UnitHasVehicleUI("player")) then return "vehicle" end
  if IsMounted and IsMounted() and not UnitAffectingCombat("player") then return "mounted" end
  return nil
end

function M.step(rt, dt)
  rt.elapsed = rt.elapsed + (dt or 0)
  if not rt.shown then
    rt.shown = true
    WeakAuras.ScanEvents("ENHROT_SHOW")
  end
  if not rt.pending and rt.elapsed < M.PULSE then return work(rt) end
  -- in raids target auras change nearly every frame: minor events wait a little, casts do not
  if rt.pending and M.THROTTLED[rt.pending.kind] and rt.elapsed < M.MIN_GAP then return work(rt) end
  local ev = rt.pending or { kind = "pulse" }
  rt.pending, rt.elapsed = nil, 0
  if M.inactive() then
    -- the timeline is hidden and the planner starts afresh afterwards
    if not rt.inactive then
      rt.inactive = true
      rt.planner, rt.searching, rt.lastFirst = M.newPlanner(), false, nil
      rt.plan, rt.due = { value = 0, steps = {} }, nil
    end
    rt.tl:stop() -- again after a wake-up, which shows the timeline
    return false
  end
  if rt.inactive then
    rt.inactive = false
    rt.tl:start()
    ev = { kind = "target" }
  end
  local now = GetTime()
  rt.ctx.now = now
  local S = snapshot.build(rt.ctx)
  local alert = M.alert(S)
  if not alert and rt.config.showLust ~= false then alert = M.lustReady(S, now) end
  rt.alert = alert
  rt.tl:setAlert(alert)
  if not (S.target.exists and S.target.enemy) then
    rt.plan, rt.S, rt.searching, rt.due = { value = 0, steps = {} }, S, false, nil
    rt.tl:render(rt.plan, S, now)
    return true
  end
  local plan = rt.planner:update(S, ev)
  rt.searching = rt.planner.busy and rt.planner:busy() or false
  return M.show(rt, plan, S, now)
end

-- LibSerialize / LibDeflate come with WeakAuras (its own import strings use them)
function M.exportLibs()
  if not LibStub then return nil end
  local ser, def = LibStub("LibSerialize", true), LibStub("LibDeflate", true)
  if not (ser and def) then return nil end
  return { serialize = ser, deflate = def }
end

-- the export window with the recorded snapshots (option "Export snapshots")
function M.showExport(env)
  local function text()
    local saved = env.saved or {}
    local list, presses = saved[recorder.KEY] or {}, saved[recorder.PRESS_KEY] or {}
    local s = recorder.export({ version = M.VERSION, snapshots = list, presses = presses }, M.exportLibs())
    if not s then return "EnhRot: this client has no LibSerialize/LibDeflate, send WeakAuras.lua instead" end
    if #list == 0 and #presses == 0 then return "EnhRot: no snapshots yet - turn on Record snapshots and play a while" end
    return s
  end
  return timeline.exportWindow(text(), text)
end

function M.timelineOptions(config)
  return { icons = config.icons, seconds = config.seconds, scale = config.scale, showReason = config.showReason ~= false }
end

function M.start(config, env)
  config = config or {}
  env = env or {}
  env.saved = env.saved or {}
  env.saved.swing = env.saved.swing or {}
  local now = GetTime()
  local ctx = { cache = snapshot.scan(), swing = swing.new(env.saved.swing), enemies = enemies.new(), ttd = ttd.new(),
                inflight = {}, mode = M.MODES[config.mode or 1] or "auto", attacking = nil,
                shield = M.SHIELDS[config.shield or 1] or "auto" }
  ctx.swing:onSpeed(now, UnitAttackSpeed("player"))
  -- after /reload auto-attack may already be on; PLAYER_ENTER_COMBAT will not come again
  if IsCurrentSpell and IsCurrentSpell(M.ATTACK_ID) then
    ctx.attacking = true
    ctx.swing:onAttack(now, true)
  end
  -- one engine frame and one timeline for the whole session: a re-init reuses both
  local frame = EnhRotEngineFrame or CreateFrame("Frame", "EnhRotEngineFrame")
  M.listen(frame)
  local tl = timeline.new(env.region or UIParent, M.timelineOptions(config), frame.enhrotTimeline)
  frame.enhrotTimeline = tl
  local rt = {
    config = config, env = env, ctx = ctx, frame = frame, tl = tl, elapsed = 0, pending = nil, shown = false,
    planner = M.newPlanner(), rec = config.record and recorder.new(env.saved, M.RECORD_MAX, M.PRESS_MAX) or nil,
    playerGUID = UnitGUID("player"), mine = {}, counters = { replans = 0, capped = 0, errors = 0 }, reported = false,
  }
  tl.onError = function() M.fail(rt) end
  M.checkTalents(rt)
  if config.export then M.showExport(env) end
  frame:SetScript("OnEvent", function(_, event, ...)
    if rt.stopped then return end
    if rt.busy then return M.fail(rt) end
    rt.busy = true
    M.onEvent(rt, event, ...)
    rt.busy = false
  end)
  frame:SetScript("OnUpdate", function(_, dt) M.update(rt, dt) end)
  frame:Show()
  -- the region's hooks stay for the session; they always act on the newest engine state
  frame.enhrotRt = rt
  local region = env.region
  if region and region.HookScript and not region.enhrotHooked then
    region.enhrotHooked = true
    region:HookScript("OnHide", function() if frame.enhrotRt then M.sleep(frame.enhrotRt) end end)
    region:HookScript("OnShow", function() if frame.enhrotRt then M.wake(frame.enhrotRt) end end)
  end
  env.rt = rt
  return rt
end

return M
