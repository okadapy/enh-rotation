-- Value of a chain of actions: useful damage now, minus mana at the mode's price,
-- plus what the end state is still worth (Maelstrom, remaining DoT/totem/pet damage, ready buttons).
local M = {}

M.WEIGHTS = {
  solo  = { mana = 1.0,  overkill = 0.0, kill = 0.15 },
  group = { mana = 0.05, overkill = 0.2, kill = 0.0 },
  raid  = { mana = 0.05, overkill = 0.2, kill = 0.0 },
}
M.WEIGHTS.pvp = M.WEIGHTS.group

M.DISCOUNT = 0.5             -- ready cooldowns, DoT ticks and totem pulses after the horizon
M.TAIL = 12                  -- s of remaining DoT/totem/pet time worth counting: later it can simply be recast
M.MW_SHARE = 0.2             -- one Maelstrom stack = 1/5 of an instant Lightning Bolt
M.OOM_WEIGHT = 0.5           -- group/raid mana weight when the fight outlasts the mana
M.FIGHT_MANA_PER_SEC = 0.003 -- net share of max mana spent per second (after regen), for the OOM projection
M.RAGE_SCARCITY = 1.5        -- solo: mana is dearer while Shamanistic Rage is on cooldown
M.READY_KEYS = { "stormstrike", "lavaLash", "earthShock", "fireNova" }
M.COOLDOWN = {}  -- base cooldowns of READY_KEYS (spells data)
do
  local spells = require("spells")
  for _, key in ipairs(M.READY_KEYS) do M.COOLDOWN[key] = spells.byKey[key] and spells.byKey[key].cd or 0 end
end
M.FIRE_SOURCE = { searing = "searingTotem", magma = "magmaTotem", fireElemental = "fireElemental" }

-- looked up on every call so tests (and the build) can swap the module
local function D() return package.loaded.damage or require("damage") end

local function weights(S) return M.WEIGHTS[S.mode] or M.WEIGHTS.group end

-- damage points one mana point is worth; scales with the character through AP + SP
function M.manaPrice(S)
  local p = S.player
  local ref = ((p.ap or 0) + (p.spNature or 0)) / 4000
  local w = weights(S)
  if S.mode == "solo" then
    local frac = (p.manaMax and p.manaMax > 0) and ((p.mana or 0) / p.manaMax) or 1
    local scarcity = 1 + 3 * (1 - frac) * (1 - frac)
    local rage = S.spells and S.spells.shamanisticRage
    if not rage or (rage.cd or 0) > 0 then scarcity = scarcity * M.RAGE_SCARCITY end
    return w.mana * scarcity * ref
  end
  local ttd = S.target and S.target.ttd
  if ttd and p.manaMax and (p.mana or 0) < ttd * p.manaMax * M.FIGHT_MANA_PER_SEC then
    return M.OOM_WEIGHT * ref
  end
  return w.mana * ref
end

-- Without mana spent only S.mode, S.target.hp and S.target.hpMax are read from S
-- (search relies on it for its allocation-free tail).
function M.step(S, S2, dmg, manaSpent)
  local w = weights(S)
  dmg = dmg or 0
  local hpLeft = math.max(0, S.target.hp or 0)
  local useful = math.min(dmg, hpLeft)
  local v = useful + (dmg - useful) * w.overkill
  if manaSpent and manaSpent ~= 0 then v = v - manaSpent * M.manaPrice(S) end
  if w.kill > 0 and hpLeft > 0 and (S2.target.hp or 0) <= 0 then
    v = v + w.kill * (S.target.hpMax or hpLeft)
  end
  return v
end

local function alive(S)
  local t = S.target
  return t and t.exists ~= false and t.enemy ~= false and not t.dead and (t.hp == nil or t.hp > 0)
end

-- seconds of `remains` that still count: at most TAIL, and not after the target dies
local function lifetime(S, remains)
  remains = remains or 0
  if remains > M.TAIL then remains = M.TAIL end
  local ttd = S.target.ttd
  if ttd and ttd < remains then remains = ttd end
  if remains < 0 then return 0 end
  return remains
end

-- remaining periodic damage (continuous dps, same as model.advance), at the discount
local function periodicValue(S, damage)
  if not alive(S) then return 0 end
  local v = 0
  local fs = S.target.fs or 0
  if fs > 0 then v = v + damage.periodic(S, "flameShock") * lifetime(S, fs) end
  local fire = S.totems and S.totems.fire
  local src = fire and fire.kind and M.FIRE_SOURCE[fire.kind]
  if src and (fire.remains or 0) > 0 then v = v + damage.periodic(S, src) * lifetime(S, fire.remains) end
  local wolves = S.pets and S.pets.wolves or 0
  if wolves > 0 then v = v + damage.periodic(S, "feralSpirit") * lifetime(S, wolves) end
  return v * M.DISCOUNT
end

local function maelstromValue(S, damage)
  local mw = S.buffs and S.buffs.mw
  local stacks = (mw and mw.stacks) or 0
  if stacks > 5 then stacks = 5 end
  if stacks <= 0 or not (S.spells and S.spells.lightningBolt) then return 0 end
  return stacks * M.MW_SHARE * damage.action(S, "lightningBolt") * M.DISCOUNT
end

-- how far each hand's current swing has come: a swing held back or reset by a cast shifts
-- every later swing, and that shift is exactly this much auto-attack damage
local function swingValue(S, damage)
  local sw = S.swing
  if not (sw and sw.attacking and alive(S) and S.target.range == "melee") then return 0 end
  local v = 0
  local mh, oh = sw.mh, sw.oh
  if mh and (mh.speed or 0) > 0 then
    local p = 1 - (mh.next or 0) / mh.speed
    if p > 0 then v = v + (p < 1 and p or 1) * damage.auto(S, "mh") end
  end
  if oh and (oh.speed or 0) > 0 then
    local p = 1 - (oh.next or 0) / oh.speed
    if p > 0 then v = v + (p < 1 and p or 1) * damage.auto(S, "oh") end
  end
  return v
end

-- a button is worth its damage at the discount once ready; while on cooldown only the part
-- of the cooldown already recovered counts (pressing it now is not free, waiting is not free either)
local function readyValue(S, damage)
  local v = 0
  local spells = S.spells
  if not spells then return 0 end
  local fire = S.totems and S.totems.fire
  local keys = M.READY_KEYS
  for i = 1, #keys do
    local key = keys[i]
    local sp = spells[key]
    if sp and (key ~= "fireNova" or (fire and fire.kind)) then
      local cd, full = sp.cd or 0, M.COOLDOWN[key] or 0
      local share = 1
      if cd > 0 then share = full > cd and (1 - cd / full) or 0 end
      if share > 0 then v = v + damage.action(S, key) * M.DISCOUNT * share end
    end
  end
  return v
end

function M.terminal(S)
  local damage = D()
  return maelstromValue(S, damage) + periodicValue(S, damage) + readyValue(S, damage) + swingValue(S, damage)
end

return M
