local M = {}

M.WINDOW = 10
M.MIN_SAMPLES = 3
M.MIN_SPAN = 1.5
M.HEAL_RESET = 0.05
M.FORGET = 30
M.TAU = 1.5 -- s: time constant of the smoothed estimate (smoothed)
M.EPS = 0.05 -- s: the shortest time-to-die the smoothing divides by
M.PRIOR_SPAN = 3 -- s of regression data the prior (expected kill rate) is worth
M.PRIOR_SAMPLES = 4 -- the regression's weight is its span times n / (n + PRIOR_SAMPLES)

local T = {}
T.__index = T

function M.new()
  return setmetatable({ units = {} }, T)
end

function T:reset(guid)
  if guid then self.units[guid] = nil else self.units = {} end
end

function T:add(now, guid, hpPct)
  if not guid or not hpPct then return end
  for g, u in pairs(self.units) do
    if now - u.seen > M.FORGET then self.units[g] = nil end
  end
  local u = self.units[guid]
  if not u then
    u = { samples = {}, seen = now }
    self.units[guid] = u
  end
  u.seen = now
  local s = u.samples
  local last = s[#s]
  if last and hpPct > last.hp + M.HEAL_RESET then
    s = {}
    u.samples = s
  end
  s[#s + 1] = { t = now, hp = hpPct }
  while #s > 0 and now - s[1].t > M.WINDOW do table.remove(s, 1) end
end

-- least-squares slope of the samples (health share per second) and their time span;
-- nil while there are too few samples or too short a span
local function fit(s)
  local n = #s
  if n < M.MIN_SAMPLES or s[n].t - s[1].t < M.MIN_SPAN then return nil end
  local t0 = s[1].t
  local st, sh, stt, sth = 0, 0, 0, 0
  for i = 1, n do
    local t = s[i].t - t0
    st = st + t
    sh = sh + s[i].hp
    stt = stt + t * t
    sth = sth + t * s[i].hp
  end
  local den = n * stt - st * st
  if den <= 0 then return nil end
  return (n * sth - st * sh) / den, s[n].t - t0
end

-- Without a prior: the regression alone, nil until it has seen a decline.
-- With a prior (seconds to die at the expected kill rate, from the caller): both as kill speeds
-- (health share per second, linear in the damage done), the prior worth PRIOR_SPAN seconds of
-- data, the regression its span scaled by n / (n + PRIOR_SAMPLES). The first seconds of a fight
-- are a few whole-percent steps and a swing or two: the regression then says 100-200 s for a
-- mob that dies in 7, and the prior carries the estimate until the data outweighs it. A flat
-- regression counts as speed 0 (nothing is killing the mob), so it pulls the estimate up.
-- Second value: "regression" / "prior" / "blend".
function T:estimate(now, guid, prior)
  local u = guid and self.units[guid]
  if prior then
    if prior <= 0 then return 0, "prior" end
    local s = u and u.samples
    local n = s and #s or 0
    if n == 0 then return prior, "prior" end
    local last = s[n]
    if last.hp <= 0 then return 0, "prior" end
    local speed = last.hp / prior
    local slope, span = fit(s)
    if not slope then return prior, "prior" end
    local w = span * n / (n + M.PRIOR_SAMPLES)
    local sr = slope < 0 and -slope or 0
    speed = (M.PRIOR_SPAN * speed + w * sr) / (M.PRIOR_SPAN + w)
    local left = last.hp / speed - (now - last.t)
    if left < 0 then left = 0 end
    return left, "blend"
  end
  if not u then return nil end
  local s = u.samples
  local slope = fit(s)
  if not slope or slope >= 0 then return nil end
  local n = #s
  local left = s[n].hp / -slope - (now - s[n].t)
  if left < 0 then left = 0 end
  return left, "regression"
end

-- The estimate for the planner. The raw regression jumps with every hit (health comes in whole
-- percent for most mobs), and a first-glance 500 s drops to 20 s a second later; the plan near a
-- mob's death followed that noise. Smoothed as a kill rate (1 / time-to-die, which is linear in
-- the damage done) with time constant TAU, while the previous value runs down with the clock.
-- A long estimate (a boss) stays long: the group mana projection needs it. nil (no decline seen,
-- a heal) starts afresh. prior (optional, seconds): see estimate; the second value is the source.
function T:smoothed(now, guid, prior)
  local raw, src = self:estimate(now, guid, prior)
  local u = guid and self.units[guid]
  if not raw or not u then
    if u then u.sm = nil end
    return raw, src
  end
  local prev = u.sm
  if not prev then
    u.sm, u.smAt = raw, now
    return raw, src
  end
  local dt = now - u.smAt
  if dt <= 0 then return prev, src end
  local pred = prev - dt
  if pred < M.EPS then pred = M.EPS end
  local a = 1 - math.exp(-dt / M.TAU)
  local rate = 1 / pred + a * (1 / math.max(raw, M.EPS) - 1 / pred)
  local v = 1 / rate
  if raw <= 0 then v = 0 end
  u.sm, u.smAt = v, now
  return v, src
end

return M
