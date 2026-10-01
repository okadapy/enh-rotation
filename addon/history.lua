-- Fight reviews kept: the session's full ones in memory, a short record per boss fight in
-- SavedVariables (DoubtMyRotationDB.fights) and the trend against the last fights on that boss.
local M = {}
M.SESSION_MAX = 10
M.BOSS_FIGHTS = 20
M.BOSS_MAX = 50
M.TREND_OF = 5
M.SAME_RATE = 0.03 -- matched share, absolute
M.SAME_LOST = 0.10 -- loss per second, relative

local H = {}
H.__index = H

-- db: the addon's saved table; now(): seconds since the epoch (the client's time)
function M.new(db, now)
  if type(db.fights) ~= "table" then db.fights = {} end
  return setmetatable({ db = db, now = now, session = {} }, H)
end

function M.short(f, tips, date)
  local codes = {}
  for i = 1, math.min(3, #tips) do codes[i] = tips[i].code end
  return { date = date, seconds = math.floor((f.seconds or 0) + 0.5), rate = f.rate, delay = f.delay,
           lostPerSec = (f.seconds or 0) > 0 and (f.lost or 0) / f.seconds or 0, tips = codes }
end

-- prev: newest first; nil with fewer than 2 fights before
function M.trend(prev, cur)
  local n = math.min(#prev, M.TREND_OF)
  if n < 2 then return nil end
  local rate, rn, lost = 0, 0, 0
  for i = 1, n do
    if prev[i].rate then rate, rn = rate + prev[i].rate, rn + 1 end
    lost = lost + (prev[i].lostPerSec or 0)
  end
  lost = lost / n
  local dr = (rn > 0 and cur.rate) and (cur.rate - rate / rn) or 0
  local dl = lost > 0 and ((cur.lostPerSec or 0) - lost) / lost or 0
  local eps = 1e-9
  local up = dr >= M.SAME_RATE - eps or dl <= -M.SAME_LOST + eps
  local down = dr <= -M.SAME_RATE + eps or dl >= M.SAME_LOST - eps
  if up and not down then return "better" end
  if down and not up then return "worse" end
  return "same"
end

local function evict(fights)
  local n, oldest, oldKey = 0, nil, nil
  for k, b in pairs(fights) do
    n = n + 1
    local t = b.last or 0
    if oldest == nil or t < oldest or (t == oldest and k < oldKey) then oldest, oldKey = t, k end
  end
  if n > M.BOSS_MAX then fights[oldKey] = nil end
end

function H:add(f, tips)
  local short = M.short(f, tips, self.now())
  local entry = { fight = f, tips = tips, short = short }
  table.insert(self.session, 1, entry)
  while #self.session > M.SESSION_MAX do table.remove(self.session) end
  if f.key and not f.trash then
    local fights = self.db.fights
    local b = fights[f.key]
    entry.trend = M.trend(b and b.list or {}, short)
    if not b then
      b = { list = {} }
      fights[f.key] = b
    end
    b.last = short.date
    table.insert(b.list, 1, short)
    while #b.list > M.BOSS_FIGHTS do table.remove(b.list) end
    evict(fights)
  end
  return entry
end

function H:boss(key)
  local b = self.db.fights[key]
  return b and b.list or {}
end

return M
