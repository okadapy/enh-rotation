local M = {}

M.WINDOW = 10
M.MIN_SAMPLES = 3
M.MIN_SPAN = 1.5
M.HEAL_RESET = 0.05
M.FORGET = 30

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

function T:estimate(now, guid)
  local u = guid and self.units[guid]
  if not u then return nil end
  local s = u.samples
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
  local slope = (n * sth - st * sh) / den
  if slope >= 0 then return nil end
  local left = s[n].hp / -slope - (now - s[n].t)
  if left < 0 then left = 0 end
  return left
end

return M
