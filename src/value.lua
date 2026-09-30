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
M.MW_SHARE = 0.2             -- one Maelstrom stack = 1/5 of an instant Lightning Bolt
M.OOM_WEIGHT = 0.5           -- group/raid mana weight when the fight outlasts the mana
M.FIGHT_MANA_PER_SEC = 0.01  -- share of max mana spent per second, for the OOM projection
M.RAGE_SCARCITY = 1.5        -- solo: mana is dearer while Shamanistic Rage is on cooldown
M.READY_KEYS = { "stormstrike", "lavaLash", "earthShock", "fireNova" }
M.FIRE_SOURCE = { searing = "searingTotem", magma = "magmaTotem", fireElemental = "fireElemental" }

-- looked up on every call so tests (and the build) can swap the module
local function D() return require("damage") end

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

function M.step(S, S2, dmg, manaSpent)
  local w = weights(S)
  dmg = dmg or 0
  local hpLeft = math.max(0, S.target.hp or 0)
  local useful = math.min(dmg, hpLeft)
  local v = useful + (dmg - useful) * w.overkill - (manaSpent or 0) * M.manaPrice(S)
  if w.kill > 0 and hpLeft > 0 and (S2.target.hp or 0) <= 0 then
    v = v + w.kill * (S.target.hpMax or hpLeft)
  end
  return v
end

local function alive(S)
  local t = S.target
  return t and t.exists ~= false and t.enemy ~= false and not t.dead and (t.hp == nil or t.hp > 0)
end

local function lifetime(S, remains)
  remains = remains or 0
  local ttd = S.target.ttd
  if ttd then return math.max(0, math.min(remains, ttd)) end
  return math.max(0, remains)
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
  local stacks = math.min(5, (S.buffs and S.buffs.mw and S.buffs.mw.stacks) or 0)
  if stacks <= 0 or not (S.spells and S.spells.lightningBolt) then return 0 end
  return stacks * M.MW_SHARE * damage.action(S, "lightningBolt")
end

local function readyValue(S, damage)
  local v = 0
  local fire = S.totems and S.totems.fire
  for _, key in ipairs(M.READY_KEYS) do
    local sp = S.spells and S.spells[key]
    if sp and (sp.cd or 0) <= 0 and (key ~= "fireNova" or (fire and fire.kind)) then
      v = v + damage.action(S, key) * M.DISCOUNT
    end
  end
  return v
end

function M.terminal(S)
  local damage = D()
  return maelstromValue(S, damage) + periodicValue(S, damage) + readyValue(S, damage)
end

return M
