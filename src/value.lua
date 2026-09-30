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
M.SOLO_REGEN = 20            -- solo: seconds of drinking (lost damage) per full bar of mana
M.MELEE_SHARE = 1.5          -- enhancement damage / auto-attack damage, for the damage-per-second estimate
M.SUPPORT = 0.06             -- share of auto-attack damage the support totems add (Windfury, Strength of Earth...)
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

-- looked up on every call so tests can swap the module: require returns what the test preloaded
-- (the client has no module table of its own, the build's require reads the bundled list)
local function D() return require("damage") end

local function weights(S) return M.WEIGHTS[S.mode] or M.WEIGHTS.group end

-- the character's damage per second: auto attacks are about MELEE_SHARE of it
function M.dpsEstimate(S)
  local sw, w = S.swing, S.weapons
  if not (sw and w) then return 0 end
  local damage = D()
  local dps = 0
  if sw.mh and w.mh and (sw.mh.speed or 0) > 0 then dps = dps + damage.auto(S, "mh") / sw.mh.speed end
  if sw.oh and w.oh and (sw.oh.speed or 0) > 0 then dps = dps + damage.auto(S, "oh") / sw.oh.speed end
  return dps * M.MELEE_SHARE
end

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
    -- mana spent now is drunk back later: a full bar costs SOLO_REGEN seconds of damage
    local dps = M.dpsEstimate(S)
    if dps > 0 and (p.manaMax or 0) > 0 then return w.mana * scarcity * dps * M.SOLO_REGEN / p.manaMax end
    return w.mana * scarcity * ref
  end
  local ttd = S.target and S.target.ttd
  if ttd and p.manaMax and (p.mana or 0) < ttd * p.manaMax * M.FIGHT_MANA_PER_SEC then
    return M.OOM_WEIGHT * ref
  end
  return w.mana * ref
end

-- Without mana spent only S.mode, S.target.hp, S.target.hpMax and S.target.dead are read from S
-- (search relies on it for its allocation-free tail).
-- The kill counts when the target dies in this step, by our damage or at its time-to-die: the
-- model stops counting damage there, so "killed by hp" alone flipped with every noisy estimate.
function M.step(S, S2, dmg, manaSpent)
  local w = weights(S)
  dmg = dmg or 0
  local hpLeft = math.max(0, S.target.hp or 0)
  local useful = math.min(dmg, hpLeft)
  local v = useful + (dmg - useful) * w.overkill
  if manaSpent and manaSpent ~= 0 then v = v - manaSpent * M.manaPrice(S) end
  if w.kill > 0 and hpLeft > 0 and not S.target.dead and ((S2.target.hp or 0) <= 0 or S2.target.dead) then
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
  local fs = S.target.fs or 0
  local fire = S.totems and S.totems.fire
  local src = fire and fire.kind and M.FIRE_SOURCE[fire.kind]
  local fireLeft = src and (fire.remains or 0) or 0
  local wolves = S.pets and S.pets.wolves or 0
  if fs <= 0 and fireLeft <= 0 and wolves <= 0 then return 0 end
  -- one lookup for all sources when the damage module offers it (the search's memo)
  local r = damage.rates and damage.rates(S)
  local v = 0
  if fs > 0 then v = v + (r and r.flameShock or damage.periodic(S, "flameShock")) * lifetime(S, fs) end
  if fireLeft > 0 then v = v + (r and r[src] or damage.periodic(S, src)) * lifetime(S, fireLeft) end
  if wolves > 0 then v = v + (r and r.feralSpirit or damage.periodic(S, "feralSpirit")) * lifetime(S, wolves) end
  return v * M.DISCOUNT
end

local function maelstromValue(S, damage)
  local mw = S.buffs and S.buffs.mw
  local stacks = (mw and mw.stacks) or 0
  if stacks > 5 then stacks = 5 end
  if stacks <= 0 or not (S.spells and S.spells.lightningBolt) then return 0 end
  local A = damage.actionTable and damage.actionTable(S)
  local lb = A and A.lightningBolt
  if lb == nil then lb = damage.action(S, "lightningBolt") end
  return stacks * M.MW_SHARE * lb * M.DISCOUNT
end

-- a button is worth its damage at the discount once ready; while on cooldown only the part
-- of the cooldown already recovered counts (pressing it now is not free, waiting is not free either)
local function readyValue(S, damage)
  local v = 0
  local spells = S.spells
  if not spells then return 0 end
  local fire = S.totems and S.totems.fire
  -- Fire Nova needs a totem, but not the one standing by a dead mob: then it counts as the others
  local novaOk = (fire and fire.kind) or not alive(S)
  local keys = M.READY_KEYS
  local A = damage.actionTable and damage.actionTable(S)
  for i = 1, #keys do
    local key = keys[i]
    local sp = spells[key]
    if sp and (key ~= "fireNova" or novaOk) then
      local cd, full = sp.cd or 0, M.COOLDOWN[key] or 0
      local share = 1
      if cd > 0 then share = full > cd and (1 - cd / full) or 0 end
      if share > 0 then
        local d = A and A[key]
        if d == nil then d = damage.action(S, key) end
        v = v + d * M.DISCOUNT * share
      end
    end
  end
  return v
end

-- Auto-attack parts, one lookup of both hands' swing damage:
-- * how far each hand's current swing has come: a swing held back or reset by a cast shifts
--   every later swing, and that shift is exactly this much auto-attack damage;
-- * the support totems (the water slot stands for the whole set Call of the Elements drops).
local function autoValue(S, damage)
  local sw = S.swing
  if not (sw and sw.attacking) then return 0 end
  local mh, oh = sw.mh, sw.oh
  local st = damage.swingStats and damage.swingStats(S)
  local amh = mh and (mh.speed or 0) > 0 and (st and st.mh or damage.auto(S, "mh")) or 0
  local aoh = oh and (oh.speed or 0) > 0 and (st and st.oh or damage.auto(S, "oh")) or 0
  local v = 0
  if S.target.range == "melee" then
    if amh > 0 then
      local p = 1 - (mh.next or 0) / mh.speed
      if p > 0 then v = v + (p < 1 and p or 1) * amh end
    end
    if aoh > 0 then
      local p = 1 - (oh.next or 0) / oh.speed
      if p > 0 then v = v + (p < 1 and p or 1) * aoh end
    end
  end
  local water = S.totems and S.totems.water
  if water and (water.remains or 0) > 0 then
    local dps = (amh > 0 and amh / mh.speed or 0) + (aoh > 0 and aoh / oh.speed or 0)
    v = v + lifetime(S, water.remains) * M.SUPPORT * dps * M.DISCOUNT
  end
  return v
end

function M.terminal(S)
  local damage = D()
  local v = maelstromValue(S, damage) + readyValue(S, damage)
  if alive(S) then v = v + periodicValue(S, damage) + autoValue(S, damage) end
  return v
end

return M
