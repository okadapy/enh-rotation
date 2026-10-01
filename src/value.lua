-- Value of a chain of actions: useful damage now, minus mana at the mode's price,
-- plus what the end state is still worth (Maelstrom, remaining DoT/totem/pet damage, ready buttons).
local util = require("util")

local M = {}

M.WEIGHTS = {
  solo  = { mana = 1.0,  overkill = 0.0, kill = 0.15 },
  group = { mana = 0.05, overkill = 0.2, kill = 0.0 },
  raid  = { mana = 0.05, overkill = 0.2, kill = 0.0 },
}
M.WEIGHTS.pvp = M.WEIGHTS.group

M.DISCOUNT = 0.5             -- ready cooldowns, DoT ticks and totem pulses after the horizon
-- solo: mana drunk back per second of drinking, by the level the drink needs (3.3.5a vendor and
-- conjured water, wotlkdb.com: Morning Glory Dew 2934 mana / 30 s at 45, Conjured Crystal Water
-- 4200 / 30 s at 55, Filtered Draenic Water 5100 / 30 s at 60, Purified Draenic Water 7200 / 30 s
-- at 65, Pungent Seal Whey 12840 / 30 s at 70, Honeymint Tea 19200 / 30 s at 75; below 45: Moonberry
-- Juice 1992 / 30 s, Sweet Nectar 1345 / 27 s, Melon Juice 835 / 24 s, Ice Cold Milk 437 / 21 s,
-- Refreshing Spring Water 151 / 18 s)
M.DRINK = { { 75, 19200 / 30 }, { 70, 12840 / 30 }, { 65, 7200 / 30 }, { 60, 5100 / 30 }, { 55, 4200 / 30 },
            { 45, 2934 / 30 }, { 35, 1992 / 30 }, { 25, 1345 / 27 }, { 15, 835 / 24 }, { 5, 437 / 21 },
            { 1, 151 / 18 } }
-- solo: the player's mana option (S.manaPolicy, nil = balanced) multiplies the drinking price.
-- balanced: the level's water, as it is. save: 1.5x, drinking stops the grind for longer than
-- the water's own time (sitting down, eating for health too, the walk back to the pull): fewer
-- spells, fewer stops. spend: 0.5x, half of the drinking falls into time lost anyway (looting,
-- the walk to the next mob, waiting for a respawn): at 52-54 a bar then costs ~14 s, a little
-- under the fixed 20 s a bar the price had before the water (0.7x of balanced there), when plans
-- pressed Earth Shock and Stormstrike whenever they were ready.
M.MANA_POLICY = { balanced = 1.0, save = 1.5, spend = 0.5 }
M.MELEE_SHARE = 1.5          -- enhancement damage / auto-attack damage, for the damage-per-second estimate
M.SUPPORT = 0.06             -- share of auto-attack damage the support totems add (Windfury, Strength of Earth...)
M.TAIL = 12                  -- s of remaining totem/pet time worth counting: later it can simply be recast
                             -- (not Flame Shock: a recast overwrites the DoT, see fsCap)
M.MW_SHARE = 0.2             -- one Maelstrom stack = 1/5 of an instant Lightning Bolt
M.OOM_WEIGHT = 0.5           -- group/raid mana weight when the fight outlasts the mana
M.FIGHT_MANA_PER_SEC = 0.003 -- net share of max mana spent per second (after regen), for the OOM projection
M.READY_KEYS = { "stormstrike", "lavaLash", "earthShock", "fireNova" }
M.RESERVE_KEYS = { "stormstrike", "earthShock", "lavaLash" } -- solo: the melee buttons the mana is kept for
M.COOLDOWN = {}  -- base cooldowns of READY_KEYS (spells data)
do
  local spells = require("spells")
  for _, key in ipairs(M.READY_KEYS) do M.COOLDOWN[key] = spells.byKey[key] and spells.byKey[key].cd or 0 end
end
M.FIRE_SOURCE = { searing = "searingTotem", magma = "magmaTotem", fireElemental = "fireElemental" }
do
  local rage = require("spells").byKey.shamanisticRage
  M.RAGE_DURATION, M.RAGE_CD = rage.duration or 15, rage.cd or 60 -- Shamanistic Rage: 15 s window, 1 min cooldown
end

-- looked up on every call so tests can swap the module: require returns what the test preloaded
-- (the client has no module table of its own, the build's require reads the bundled list)
local function D() return require("damage") end

-- the mode's weights: M.WEIGHTS[S.mode] or M.WEIGHTS.group (looked up in place: hot)

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

-- mana per second of drinking at the character's level (M.DRINK)
function M.drinkRate(level)
  local d = M.DRINK
  level = level or 1
  for i = 1, #d do
    if level >= d[i][1] then return d[i][2] end
  end
  return d[#d][2]
end

-- damage points one mana point is worth; scales with the character through AP + SP
function M.manaPrice(S)
  local p = S.player
  local ref = ((p.ap or 0) + (p.spNature or 0)) / 4000
  local W = M.WEIGHTS
  local w = W[S.mode] or W.group
  if S.mode == "solo" then
    -- Mana spent now is drunk back later: every point costs 1 / drinkRate seconds of sitting,
    -- i.e. that much of the character's damage. The drink is the best water of the character's
    -- level: at 52-54 Morning Glory Dew gives 98 mana a second, a full bar is ~30 s. (A fixed 20 s
    -- per bar was ~1.5x too cheap there, and Chain Lightning at 2.6x a Bolt's mana for the same
    -- damage on one target looked worth its price.) Drinking is linear, so the price does not grow
    -- as the bar empties: the "scarcity" and "Rage on cooldown" multipliers left from the old
    -- AP-based price made it 4-6x the drinking time, and a level-53 player in melee was told to
    -- idle with Stormstrike and Lava Lash ready. A bar that runs dry needs no extra price: what
    -- cannot be paid cannot be pressed.
    -- The player's option (MANA_POLICY) scales it; the reserve (reserveValue) stays as it is.
    -- the search's states carry it in their memo (search.root), not as a field of every copy
    local pol = S.manaPolicy
    if pol == nil then local m = S.memo; pol = m and m.manaPolicy end
    local f = M.MANA_POLICY[pol] or 1
    local dps = M.dpsEstimate(S)
    if dps > 0 then return f * w.mana * dps / M.drinkRate(p.level) end
    return f * w.mana * ref
  end
  local ttd = S.target and S.target.ttd
  if ttd and p.manaMax and (p.mana or 0) < ttd * p.manaMax * M.FIGHT_MANA_PER_SEC then
    return M.OOM_WEIGHT * ref
  end
  return w.mana * ref
end

-- Without mana spent, or with price (= manaPrice(S), taken by the caller), only S.mode,
-- S.target.hp, S.target.hpMax and S.target.dead are read from S (search relies on it for its
-- allocation-free tail and for a press in the buffer of the wait before it).
-- The kill counts when the target dies in this step, by our damage or at its time-to-die: the
-- model stops counting damage there, so "killed by hp" alone flipped with every noisy estimate.
function M.step(S, S2, dmg, manaSpent, price)
  local W = M.WEIGHTS
  local w = W[S.mode] or W.group
  dmg = dmg or 0
  local hp = S.target.hp or 0
  local hpLeft = hp > 0 and hp or 0 -- = math.max(0, hp), math.min below the same, inlined (hot)
  local useful = hpLeft < dmg and hpLeft or dmg
  local v = useful + (dmg - useful) * w.overkill
  if manaSpent and manaSpent ~= 0 then v = v - manaSpent * (price or M.manaPrice(S)) end
  if w.kill > 0 and hpLeft > 0 and not S.target.dead and ((S2.target.hp or 0) <= 0 or S2.target.dead) then
    v = v + w.kill * (S.target.hpMax or hpLeft)
  end
  return v
end

-- lifetime(S, remains, cap), written out where it is needed (every end state runs it): the
-- seconds of `remains` that still count, at most `cap` (TAIL) and not after the target dies (ttd)

-- Flame Shock is not capped at TAIL: "it can simply be recast later" does not hold for a DoT
-- that a recast overwrites (3.3.5a: the ticks left are lost). Its whole remaining duration counts,
-- and the recast is valued as the shock slot's option (shockOption), minus the ticks it clips.
local function fsCap(S, damage)
  local m = S.memo
  local d = m and m.fsCap
  if not d then
    if not damage.dot then return M.TAIL end
    local _, ticks, period = damage.dot(S, "flameShock")
    d = (ticks or 0) * (period or 0)
    if d <= 0 then d = M.TAIL end
    if m then m.fsCap = d end
  end
  return d
end

-- remaining periodic damage (continuous dps, same as model.advance), at the discount
-- (lifetime() and fsCap's memo inlined: this runs for every end state)
local function periodicValue(S, damage)
  local t = S.target
  local fs = t.fs or 0
  local fire = S.totems and S.totems.fire
  local src = fire and fire.kind and M.FIRE_SOURCE[fire.kind]
  local fireLeft = src and (fire.remains or 0) or 0
  local wolves = S.pets and S.pets.wolves or 0
  if fs <= 0 and fireLeft <= 0 and wolves <= 0 then return 0 end
  -- one lookup for all sources when the damage module offers it (the search's memo)
  local r = damage.rates and damage.rates(S)
  local ttd = t.ttd
  local v = 0
  if fs > 0 then
    local m = S.memo
    local cap = m and m.fsCap
    if not cap then cap = fsCap(S, damage) end
    local left = fs > cap and cap or fs -- lifetime(S, fs, cap)
    if ttd and ttd < left then left = ttd end
    if left < 0 then left = 0 end
    v = v + (r and r.flameShock or damage.periodic(S, "flameShock")) * left
  end
  if fireLeft > 0 then
    -- Searing Totem out of reach: only the time after the target comes within 20 yards counts
    local span = fireLeft > M.TAIL and M.TAIL or fireLeft -- lifetime(S, fireLeft)
    if ttd and ttd < span then span = ttd end
    if span < 0 then span = 0 end
    if src == "searingTotem" and damage.fireUptime then span = damage.fireUptime(S, src, span) end
    v = v + (r and r[src] or damage.periodic(S, src)) * span
  end
  if wolves > 0 then
    local left = wolves > M.TAIL and M.TAIL or wolves -- lifetime(S, wolves)
    if ttd and ttd < left then left = ttd end
    if left < 0 then left = 0 end
    v = v + (r and r.feralSpirit or damage.periodic(S, "feralSpirit")) * left
  end
  return v * M.DISCOUNT
end

-- The shock slot (Earth and Flame Shock share the cooldown) is worth its better use: Earth Shock,
-- or a Flame Shock recast. Kept up by recasting at expiry, Flame Shock takes one of the
-- N = duration / cooldown shock presses its DoT spans and Earth Shock the other N - 1, so a
-- press is worth g = (hit + full DoT + (N - 1) * Earth Shock) / N on average; the terminal sees
-- only the next press, so the recast is credited that. A recast overwrites the DoT (3.3.5a: the
-- ticks left are lost), and periodicValue has already counted those: they come off, g - DoT left.
-- Earth Shock wins while the DoT left is worth more than g - Earth Shock, i.e. a DoT that still
-- runs is not clipped unless it is about to run out (level 80: under ~4 s without Stormstrike's
-- nature bonus, less with it). Without the recast here an end state whose DoT ran out was worth
-- nothing for it and a refreshed one 12 s of ticks (TAIL), so clipping 4.5 s looked best.
local function shockOption(S, damage, A, es)
  if not S.spells.flameShock then return es end
  -- duration, cycle length and tick rate do not change inside one search: once per memo
  local m = S.memo
  local c = m and m.fsShock
  if not c then
    local cap, cd = fsCap(S, damage), M.COOLDOWN.earthShock or 0
    local n = cd > 0 and cap / cd or 1
    if n < 1 then n = 1 end
    c = { cap = cap, n = n, p = damage.periodic(S, "flameShock") }
    if m then m.fsShock = c end
  end
  local cap, n, p = c.cap, c.n, c.p
  local fs = A and A.flameShock
  if fs == nil then fs = damage.action(S, "flameShock") end
  -- lifetime() of the fresh DoT and of the one left, inline (this runs for every end state)
  local ttd, left = S.target.ttd, S.target.fs or 0
  local full = cap
  if left > cap then left = cap end
  if ttd then
    if ttd < full then full = ttd end
    if ttd < left then left = ttd end
  end
  if full < 0 then full = 0 end
  if left < 0 then left = 0 end
  local v = (fs + p * full + (n - 1) * es) / n - p * left
  if v > es then return v end
  return es
end

-- a button is worth its damage at the discount once ready; while on cooldown only the part
-- of the cooldown already recovered counts (pressing it now is not free, waiting is not free either)
local function readyValue(S, damage, A, live)
  local v = 0
  local spells = S.spells
  if not spells then return 0 end
  local fire = S.totems and S.totems.fire
  -- Fire Nova needs a totem, but not the one standing by a dead mob: then it counts as the others
  local novaOk = (fire and fire.kind) or not live
  local keys, cooldown = M.READY_KEYS, M.COOLDOWN
  for i = 1, #keys do
    local key = keys[i]
    local sp = spells[key]
    if sp and (key ~= "fireNova" or novaOk) then
      local cd, full = sp.cd or 0, cooldown[key] or 0
      local share = 1
      if cd > 0 then share = full > cd and (1 - cd / full) or 0 end
      if share > 0 then
        local d = A and A[key]
        if d == nil then d = damage.action(S, key) end
        if key == "earthShock" and live then d = shockOption(S, damage, A, d) end
        v = v + d * share
      end
    end
  end
  return v * M.DISCOUNT
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
    local left = water.remains > M.TAIL and M.TAIL or water.remains -- lifetime(S, water.remains)
    local ttd = S.target.ttd
    if ttd and ttd < left then left = ttd end
    if left < 0 then left = 0 end
    v = v + left * M.SUPPORT * dps * M.DISCOUNT
  end
  return v
end

-- Solo: mana the core melee buttons need soon, one press of each known one: Stormstrike and Lava
-- Lash come back in 8 and 6 s, Earth Shock shares its 6 s with Flame Shock, so about one of
-- each per Stormstrike cycle. 0 outside solo: in a group the mana is nearly free.
-- Pure and allocation-free.
function M.manaReserve(S)
  if S.mode ~= "solo" or not S.spells then return 0 end
  local spells, keys = S.spells, M.RESERVE_KEYS
  local cost = 0
  for i = 1, #keys do
    local sp = spells[keys[i]]
    if sp and (sp.cost or 0) > 0 then cost = cost + sp.cost end
  end
  return cost
end

-- Damage of the reserve's presses that `mana` cannot pay for: the best set of them it still buys
-- (at most 3 buttons, 8 sets, no allocation) against all of them.
local function unpaid(S, mana, damage, A)
  local spells, keys = S.spells, M.RESERVE_KEYS
  local c1, c2, c3, d1, d2, d3 = 0, 0, 0, 0, 0, 0
  local n = 0
  for i = 1, #keys do
    local key = keys[i]
    local sp = spells[key]
    if sp and (sp.cost or 0) > 0 then
      local d = A and A[key]
      if d == nil then d = damage.action(S, key) end
      n = n + 1
      if n == 1 then c1, d1 = sp.cost, d elseif n == 2 then c2, d2 = sp.cost, d else c3, d3 = sp.cost, d end
    end
  end
  local all, best = d1 + d2 + d3, 0
  for m1 = 0, 1 do
    for m2 = 0, 1 do
      for m3 = 0, 1 do
        if m1 * c1 + m2 * c2 + m3 * c3 <= mana then
          local d = m1 * d1 + m2 * d2 + m3 * d3
          if d > best then best = d end
        end
      end
    end
  end
  return all - best
end

-- Solo, while the target is still on its way (alive, not in melee): mana is priced by what it
-- buys. The search sees 6 s ahead, so a Lightning Bolt on the pull that leaves the bar below the
-- reserve costs only its drinking time inside the horizon; the melee buttons it starves come
-- after. On arrival they are all ready at once and there is no drinking in the fight, so the
-- presses the end state's mana cannot pay for are lost, not delayed: their full damage counts
-- (no DISCOUNT), on top of the drinking manaPrice charged in step when the mana was spent.
-- Above the reserve nothing changes. In melee it does not apply: the search itself weighs the
-- melee buttons against each other and against idling there, and a press is what the reserve
-- is for. A dead target leaves the next pull to the drinking price.
local function reserveValue(S, damage, A)
  if S.target.range == "melee" then return 0 end
  local mana = S.player.mana or 0
  if mana >= M.manaReserve(S) then return 0 end
  return -unpaid(S, mana, damage, A)
end

-- Shamanistic Rage is worth the mana its window returns, and it returns mana only on melee hits
-- (10 PPM) while a target lives. Ready (or the recovered share of its 60 s cooldown, as
-- readyValue), it is a whole 15 s window for a later fight; a window running on a live target in
-- melee with auto attack on counts for the seconds left of it (the mob's ttd, the mana bar's
-- room). Both at the discount, at the mana's price. Without this the ready Rage was worth nothing
-- and a press cost nothing: its mana on a mob dying in 4 s (a quarter of the window) beat the
-- melee buttons, and the full window was missing on the next pull. Solo only (terminal): in a
-- group or raid mana is nearly free (manaPrice), and there the window is a small part of the plan.
function M.rageValue(S, damage, live)
  local sp = S.spells and S.spells.shamanisticRage
  if not sp or not damage.rageManaRate then return 0 end
  local rate = damage.rageManaRate(S)
  if rate <= 0 then return 0 end
  local cd, full = sp.cd or 0, M.RAGE_CD
  local mana = 0
  if cd <= 0 then
    mana = rate * M.RAGE_DURATION
  elseif full > cd then
    mana = rate * M.RAGE_DURATION * (1 - cd / full)
  end
  local left = S.buffs and S.buffs.rage or 0
  if left > 0 and live and S.target.range == "melee" and S.swing and S.swing.attacking then
    local p = S.player
    local ttd = S.target.ttd
    if ttd and ttd < left then left = ttd end
    local now = left > 0 and rate * left or 0
    local room = (p.manaMax or 0) - (p.mana or 0)
    if now > room then now = room > 0 and room or 0 end
    mana = mana + now
  end
  if mana <= 0 then return 0 end
  return mana * M.manaPrice(S) * M.DISCOUNT
end

-- Lightning Shield (free, 10 min) missing at the end: it takes a global cooldown to put back,
-- later, when that GCD has a damage button to take from: one GCD of the character's damage, at
-- the discount. Put up now, in a GCD with nothing better to do (a mob about to die), it costs
-- nothing; the shield's own damage (Static Shock) is in the auto attacks. Without this the
-- shield was worth its Static Shock procs alone, and it took the free GCD at a dying mob only by
-- a few points, or lost it to a Flame Shock for one tick. Solo only (terminal), like rageValue: the leveling pull, where a mob about to die leaves free
-- GCDs; a group keeps the old worth (the shield's Static Shock damage in the auto attacks).
function M.shieldValue(S)
  local spells = S.spells
  if not (spells and spells.lightningShield) then return 0 end
  local ls = S.buffs and S.buffs.ls
  if ls and (ls.charges or 0) > 0 then return 0 end
  if not util.wantsLightningShield(S) then return 0 end
  return -(S.gcd or 1.5) * M.dpsEstimate(S) * M.DISCOUNT
end

-- Solo, a kill inside the horizon frees the seconds after it for the next mob: a second is worth
-- the character's damage per second (the time value manaPrice uses for drinking), at the discount
-- (the next pull is not in the plan). Killing the mob sooner is worth that much; without it a mob
-- the swings finish anyway was worth the same finished 1.5 s sooner by a Lava Lash, and the plan
-- stood empty in melee.
--
-- A kill sooner than the one nothing pressed gives (search: S.memo.killBase) counts only the
-- seconds beyond FINISH_MIN. The kill time is an expectation: one hit's damage is random (crits,
-- glancing blows, misses), so a finisher that saves a fraction of a swing interval saves it only
-- on average, and the next pull starts with retargeting and running that takes longer. Without
-- the margin an Earth Shock that saved 2.0-2.8 s (130 damage a second at 52) was within 50 of
-- its mana, and the shock came and went as the mob's health fell. Without a memo (direct
-- calls) the kill counts in full.
M.FINISH_MIN = 0.5
function M.killCredit(S, live)
  local died = S.target.diedAt
  if live or not died or S.now <= died then return 0 end
  local m = S.memo
  local base = m and m.killBase
  if base and died < base then
    died = died + M.FINISH_MIN
    if died > base then died = base end
    if S.now <= died then return 0 end
  end
  return (S.now - died) * M.dpsEstimate(S) * M.DISCOUNT
end

function M.terminal(S)
  local damage = D()
  -- one lookup of the per-buff action table for all parts (nothing below changes S's buffs)
  local A = damage.actionTable and damage.actionTable(S)
  -- whether the target is alive, and Maelstrom stacks as a share of an instant Lightning Bolt
  -- (inlined: this runs for every end state)
  local t = S.target
  local live = t and t.exists ~= false and t.enemy ~= false and not t.dead and (t.hp == nil or t.hp > 0)
  local mael = 0
  local mw = S.buffs and S.buffs.mw
  local stacks = (mw and mw.stacks) or 0
  if stacks > 5 then stacks = 5 end
  if stacks > 0 and S.spells and S.spells.lightningBolt then
    local lb = A and A.lightningBolt
    if lb == nil then lb = damage.action(S, "lightningBolt") end
    mael = stacks * M.MW_SHARE * lb * M.DISCOUNT
  end
  local v = mael + readyValue(S, damage, A, live)
  if S.mode == "solo" then v = v + M.rageValue(S, damage, live) + M.shieldValue(S) + M.killCredit(S, live) end
  if live then
    v = v + periodicValue(S, damage) + autoValue(S, damage) + (t.range == "melee" and 0 or reserveValue(S, damage, A))
  end
  return v
end

return M
