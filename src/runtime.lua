local spells = require("spells")
local swing = require("swing")
local enemies = require("enemies")
local ttd = require("ttd")
local snapshot = require("snapshot")
local planner = require("planner")
local timeline = require("timeline")
local recorder = require("recorder")

local M = {}

M.PULSE = 0.25
M.RECORD_MAX = 30
M.MODES = { "auto", "solo", "group", "raid", "pvp" }
M.EVENTS = {
  "COMBAT_LOG_EVENT_UNFILTERED",
  "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
  "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_DELAYED",
  "UNIT_AURA", "PLAYER_TARGET_CHANGED", "UNIT_MANA", "PLAYER_TOTEM_UPDATE", "UNIT_ATTACK_SPEED",
  "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
}
M.RESCAN = { SPELLS_CHANGED = true, LEARNED_SPELL_IN_TAB = true, PLAYER_LEVEL_UP = true, CHARACTER_POINTS_CHANGED = true, PLAYER_TALENT_UPDATE = true }
M.PRIORITY = { cast = 6, target = 5, swing = 4, aura = 3, totem = 2, power = 1, pulse = 0 }
M.WAIT_KEYS = { waitSwing = true, wait = true }
M.LUST_IDS = { 2825, 32182 }
M.DEATH = { UNIT_DIED = true, UNIT_DESTROYED = true, PARTY_KILL = true }
M.WOLVES = spells.byKey.feralSpirit.duration or 45
M.ATTACK_ID = 6603
M.ALERT_ICONS = {
  noEnchant = "Interface\\Icons\\Spell_Nature_Cyclone",
  outOfRange = "Interface\\Icons\\Ability_Rogue_Sprint",
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
  if sp.lightningShield and b.ls.charges <= 0 then
    return withIcon({ key = "lightningShield", reason = "Lightning Shield missing" })
  end
  if (w.mh and not w.mh.enchant) or (w.oh and not w.oh.enchant) then
    return withIcon({ key = "noEnchant", reason = "Weapon imbue missing" })
  end
  local rage = sp.shamanisticRage
  if rage and S.player.manaMax > 0 and S.player.mana / S.player.manaMax < 0.2 and rage.cd <= (S.gcdRemains or 0) + 0.1 then
    return withIcon({ key = "shamanisticRage", reason = "Low mana: Shamanistic Rage" })
  end
  if S.target.exists and S.target.enemy and S.target.range == "far" then
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
  return ("EnhRot: %s | replans=%d timeouts=%d errors=%d"):format(table.concat(parts, " "), c.replans, c.timeouts, c.errors)
end

function M.report(rt, msg)
  rt.counters.errors = rt.counters.errors + 1
  if rt.reported then return end
  rt.reported = true
  print("|cffff5555EnhRot|r " .. msg)
end

function M.mark(rt, kind, key)
  local p = rt.pending
  if not p or M.PRIORITY[kind] > M.PRIORITY[p.kind] or (kind == p.kind and key and not p.key) then
    rt.pending = { kind = kind, key = key }
  end
end

local function mwNow(ctx, now)
  local a = snapshot.auras("player", "HELPFUL", ctx.cache.buffNames, false, now)
  return a.mw and a.mw.count or 0
end

-- the event belongs to the tracked hard cast (castID = 4th argument of UNIT_SPELLCAST_* in 3.3.5a)
local function ownCast(rt, key, castID)
  local c = rt.casting
  return c and c.key == key and (castID == nil or c.id == nil or castID == c.id)
end

function M.onCast(rt, event, key, now, castID)
  local ctx = rt.ctx
  if event == "UNIT_SPELLCAST_START" then
    local _, _, _, _, startMs, endMs, _, id = UnitCastingInfo("player")
    local castTime = (startMs and endMs) and (endMs - startMs) / 1000 or 0
    rt.casting = { key = key, mw = mwNow(ctx, now), id = castID or id }
    ctx.swing:onCastStart(now, key, rt.casting.mw, castTime)
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    if ownCast(rt, key, castID) then
      ctx.swing:onCastEnd(now, key, rt.casting.mw, true)
      rt.casting = nil
    elseif (spells.byKey[key].castBase or 0) <= 0 then
      -- a 5-stack Lightning Bolt is instant too, but it is no sample of an instant spell
      ctx.swing:onInstant(now, key)
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
    M.mark(rt, "cast") -- replan, but nothing was cast
    return
  elseif event == "UNIT_SPELLCAST_DELAYED" then
    local endMs = select(6, UnitCastingInfo("player"))
    if endMs and rt.casting and rt.casting.key == key then ctx.swing:onCastDelayed(now, endMs / 1000) end
  else
    return
  end
  M.mark(rt, "cast", key)
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
    rt.planner = planner.new({})
  elseif event == "PLAYER_ENTERING_WORLD" then
    rt.playerGUID = UnitGUID("player")
    rt.shown = false
    ctx.swing:onSpeed(now, UnitAttackSpeed("player"))
  elseif M.RESCAN[event] then
    ctx.cache = snapshot.scan()
    M.mark(rt, "target")
  end
end

function M.update(rt, dt)
  rt.elapsed = rt.elapsed + (dt or 0)
  if not rt.shown then
    rt.shown = true
    WeakAuras.ScanEvents("ENHROT_SHOW")
  end
  if not rt.pending and rt.elapsed < M.PULSE then return false end
  local ev = rt.pending or { kind = "pulse" }
  rt.pending, rt.elapsed = nil, 0
  local now = GetTime()
  rt.ctx.now = now
  local S = snapshot.build(rt.ctx)
  local alert = M.alert(S)
  if not alert and rt.config.showLust ~= false then alert = M.lustReady(S, now) end
  rt.tl:setAlert(alert)
  if not (S.target.exists and S.target.enemy) then
    rt.plan, rt.S = { value = 0, steps = {} }, S
    rt.tl:render(rt.plan, S, now)
    return true
  end
  local plan = rt.planner:update(S, ev)
  if not M.validPlan(plan) then
    M.report(rt, "planner returned an invalid plan")
    return false
  end
  if plan.timedOut then rt.counters.timeouts = rt.counters.timeouts + 1 end
  local first = plan.steps[1] and plan.steps[1].key
  if first ~= rt.lastFirst then
    rt.lastFirst = first
    rt.counters.replans = rt.counters.replans + 1
    if rt.rec then rt.rec:push(S, plan) end
    if rt.config.printDebug then print(M.signature(plan, rt.counters)) end
  end
  rt.plan, rt.S = plan, S
  rt.tl:render(plan, S, now)
  return true
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
                inflight = {}, mode = M.MODES[config.mode or 1] or "auto", attacking = nil }
  ctx.swing:onSpeed(now, UnitAttackSpeed("player"))
  -- after /reload auto-attack may already be on; PLAYER_ENTER_COMBAT will not come again
  if IsCurrentSpell and IsCurrentSpell(M.ATTACK_ID) then
    ctx.attacking = true
    ctx.swing:onAttack(now, true)
  end
  local frame = EnhRotEngineFrame or CreateFrame("Frame", "EnhRotEngineFrame")
  frame:UnregisterAllEvents()
  for _, e in ipairs(M.EVENTS) do frame:RegisterEvent(e) end
  for e in pairs(M.RESCAN) do frame:RegisterEvent(e) end
  if frame.enhrotTimeline then
    frame.enhrotTimeline.frame:SetScript("OnUpdate", nil)
    frame.enhrotTimeline.frame:Hide()
  end
  local tl = timeline.new(env.region or UIParent, M.timelineOptions(config))
  frame.enhrotTimeline = tl
  local rt = {
    config = config, env = env, ctx = ctx, frame = frame, tl = tl, elapsed = 0, pending = nil, shown = false,
    planner = planner.new({}), rec = config.record and recorder.new(env.saved, M.RECORD_MAX) or nil,
    playerGUID = UnitGUID("player"), mine = {}, counters = { replans = 0, timeouts = 0, errors = 0 }, reported = false,
  }
  frame:SetScript("OnEvent", function(_, event, ...) M.onEvent(rt, event, ...) end)
  frame:SetScript("OnUpdate", function(_, dt) M.update(rt, dt) end)
  frame:Show()
  env.rt = rt
  return rt
end

return M
