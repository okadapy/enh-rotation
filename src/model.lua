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
M.WATER_DURATION = 300
M.WOLVES_DURATION = duration("feralSpirit", 45)
M.RAGE_DURATION = duration("shamanisticRage", 15)
M.RAGE_MANA_AP = 0.15
M.LS_DURATION = duration("lightningShield", 600)
M.INFLIGHT = 1.0
M.WAIT_SWING_PAD = 0.01
M.CAST_SPELLS = { lightningBolt = true, chainLightning = true }
M.NATURE_CONSUME = { earthShock = true, lightningBolt = true, chainLightning = true }
M.NEEDS_TARGET = { stormstrike = true, lavaLash = true, earthShock = true, flameShock = true,
                   frostShock = true, lightningBolt = true, chainLightning = true }
M.MELEE_ONLY = { stormstrike = true, lavaLash = true }
M.SHOCK_RANGE = { earthShock = true, flameShock = true, frostShock = true }
M.HANDS = { "mh", "oh" }

M.copy = util.copy

local function talent(S, k) return (S.talents and S.talents[k]) or 0 end
local function dec(x, dt) return math.max(0, (x or 0) - dt) end

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

function M.readyIn(S, key)
  local meta, sp = spells.byKey[key], S.spells and S.spells[key]
  if not meta or not sp then return nil end
  local t = S.target
  local hasTarget = alive(S)
  if M.NEEDS_TARGET[key] then
    if not hasTarget or t.range == "far" then return nil end
    if M.MELEE_ONLY[key] and t.range ~= "melee" then return nil end
    if M.SHOCK_RANGE[key] and t.range ~= "melee" and t.range ~= "20" then return nil end
  end
  local fire = S.totems.fire
  if key == "lavaLash" and not S.weapons.oh then return nil end
  if key == "fireNova" and not fireUp(S) then return nil end
  if (key == "searingTotem" or key == "magmaTotem") and fire.kind == "fireElemental" and (fire.remains or 0) > 0 then return nil end
  if key == "magmaTotem" and not hasTarget and ((S.enemies and S.enemies.nearby) or 0) < 1 then return nil end
  if key == "lightningShield" and (S.buffs.ls.charges or 0) >= M.lsMaxCharges(S) then return nil end
  if (sp.cost or 0) > (S.player.mana or 0) then return nil end
  if S.player.moving and M.castTime(S, key) > 0 then return nil end
  local r = math.max(sp.cd or 0, S.castRemains or 0, S.gcdRemains or 0)
  if r >= M.HORIZON then return nil end
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

-- swings landing within dt; only those before `life` (time to die) deal damage
local function runSwings(n, dt, cast, life)
  local dmg = 0
  for _, hand in ipairs(M.HANDS) do
    local s = n.swing[hand]
    if s and (s.speed or 0) > 0 then
      local at = s.next or 0
      if cast then
        if cast.reset then
          at = cast.ends + s.speed
        elseif at < cast.ends then
          at = cast.ends
        end
      end
      while at <= dt + 1e-9 do
        if at <= life + 1e-9 then
          dmg = dmg + damage.auto(n, hand)
          M.addMw(n, damage.mwPerSwing(n, hand))
          if (n.buffs.rage or 0) > at then
            n.player.mana = math.min(n.player.manaMax or math.huge, n.player.mana + M.RAGE_MANA_AP * (n.player.ap or 0))
          end
        end
        at = at + s.speed
      end
      s.next = at - dt
    end
  end
  return dmg
end

-- in place, no copy. cast = { ends = sec, reset = bool } | nil
function M.advance(n, dt, cast)
  local t = n.target
  local live = alive(n)
  local life = dt
  if live and t.ttd then life = math.min(life, math.max(0, t.ttd)) end
  local dmg = 0
  if n.swing.attacking and live and t.range == "melee" then
    dmg = dmg + runSwings(n, dt, cast, life)
  else
    for _, h in ipairs(M.HANDS) do
      local s = n.swing[h]
      if s then s.next = dec(s.next, dt) end
    end
  end
  local fire = n.totems.fire
  n.pets = n.pets or { wolves = 0 }
  if live then
    if (t.fs or 0) > 0 then dmg = dmg + damage.periodic(n, "flameShock") * math.min(life, t.fs) end
    local src = fire.kind and M.FIRE_SOURCE[fire.kind]
    if src and (fire.remains or 0) > 0 then
      dmg = dmg + damage.periodic(n, src) * math.min(life, fire.remains)
    end
    if (n.pets.wolves or 0) > 0 then
      dmg = dmg + damage.periodic(n, "feralSpirit") * math.min(life, n.pets.wolves)
    end
  end
  for _, sp in pairs(n.spells) do sp.cd = dec(sp.cd, dt) end
  n.gcdRemains, n.castRemains = dec(n.gcdRemains, dt), dec(n.castRemains, dt)
  local b = n.buffs
  b.mw.remains = dec(b.mw.remains, dt); if b.mw.remains <= 0 then b.mw.stacks = 0 end
  b.ls.remains = dec(b.ls.remains, dt); if b.ls.remains <= 0 then b.ls.charges = 0 end
  b.flurry.remains = dec(b.flurry.remains, dt); if b.flurry.remains <= 0 then b.flurry.charges = 0 end
  b.rage, b.lust, b.em = dec(b.rage, dt), dec(b.lust, dt), dec(b.em, dt)
  t.fs = dec(t.fs, dt)
  if t.ss then t.ss.remains = dec(t.ss.remains, dt); if t.ss.remains <= 0 then t.ss.charges = 0 end end
  fire.remains = dec(fire.remains, dt); if fire.remains <= 0 then fire.kind = nil end
  if n.totems.water then n.totems.water.remains = dec(n.totems.water.remains, dt) end
  n.pets.wolves = dec(n.pets.wolves, dt)
  n.inflight = n.inflight or {}
  for k, v in pairs(n.inflight) do
    local left = v - dt
    if left <= 0 then n.inflight[k] = nil else n.inflight[k] = left end
  end
  n.now = n.now + dt
  if live then
    t.hp = math.max(0, (t.hp or 0) - dmg)
    if t.ttd then t.ttd = t.ttd - dt end
    if t.hp <= 0 or (t.ttd and t.ttd <= 0) then t.dead = true end
  end
  return dmg
end

function M.wait(S, dt)
  local n = M.copy(S)
  local dmg = M.advance(n, dt, nil)
  return n, dmg
end

function M.apply(S, key)
  local meta = spells.byKey[key]
  local n = M.copy(S)
  local sp = n.spells[key]
  local ct = M.castTime(n, key)
  local dt = math.max(M.gcdFor(n, key), ct)
  local dmg = alive(n) and damage.action(n, key) or 0
  local mwAtCast = math.floor((n.buffs.mw.stacks or 0) + 1e-9)

  n.player.mana = n.player.mana - (sp.cost or 0)
  local cd = M.cooldownFor(n, key)
  if meta.sharedCd then
    for k, other in pairs(n.spells) do
      local m = spells.byKey[k]
      if m and m.sharedCd == meta.sharedCd then other.cd = cd end
    end
  else
    sp.cd = cd
  end

  local ss = n.target.ss
  if ss and M.NATURE_CONSUME[key] and (ss.charges or 0) > 0 then
    ss.charges = ss.charges - 1
    if ss.charges <= 0 then ss.remains = 0 end
  end
  if M.CAST_SPELLS[key] then n.buffs.mw.stacks = 0; n.buffs.mw.remains = 0 end
  if key == "stormstrike" then
    n.target.ss = { charges = M.SS_CHARGES, remains = M.SS_DURATION }
    M.addMw(n, damage.mwPerHit(n, "mh") + (n.weapons.oh and damage.mwPerHit(n, "oh") or 0))
  elseif key == "lavaLash" then
    M.addMw(n, damage.mwPerHit(n, "oh"))
  elseif key == "flameShock" then
    local _, ticks, period = damage.dot(n, "flameShock")
    n.target.fs = ticks * period
  elseif M.TOTEM_KIND[key] then
    n.totems.fire = { kind = M.TOTEM_KIND[key], remains = M.TOTEM_DURATION[key] }
  elseif key == "callOfElements" then
    if n.totems.water then n.totems.water.remains = M.WATER_DURATION end
    if not fireUp(n) then n.totems.fire = { kind = "searing", remains = M.TOTEM_DURATION.searingTotem } end
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
    cast = { ends = ct, reset = mwAtCast == 0 }
  elseif n.swing.resetByInstant and n.swing.resetByInstant[key] then
    M.resetSwings(n)
  end
  local autoDmg = M.advance(n, dt, cast)
  return n, dmg + autoDmg, dt
end

-- candidates in spells.CATALOG order, waitSwing last
function M.actions(S)
  local out = {}
  for _, meta in ipairs(spells.CATALOG) do
    local r = M.readyIn(S, meta.key)
    if r then out[#out + 1] = { key = meta.key, readyIn = r } end
  end
  local sw = S.swing
  if sw and sw.attacking and alive(S) and S.target.range == "melee" then
    local nxt = math.huge
    for _, h in ipairs(M.HANDS) do
      if sw[h] and sw[h].next then nxt = math.min(nxt, sw[h].next) end
    end
    local r = nxt + M.WAIT_SWING_PAD
    if r < M.HORIZON then out[#out + 1] = { key = "waitSwing", readyIn = r } end
  end
  return out
end

return M
