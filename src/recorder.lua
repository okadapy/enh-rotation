local M = {}
M.KEY = "enhrotSnapshots"
M.PRESS_KEY = "enhrotPresses"
M.MIN_GAP = 2
M.PRESS_MAX = 200

local function copy(v, seen)
  if type(v) ~= "table" then
    if type(v) == "function" then return nil end
    return v
  end
  seen = seen or {}
  if seen[v] then return seen[v] end
  local out = {}
  seen[v] = out
  for k, x in pairs(v) do out[copy(k, seen)] = copy(x, seen) end
  return out
end
M.copy = copy

M.EXPORT_PREFIX = "!ENHROT:2!"

-- The recorded data as one printable string for a bug report (copied from the export window):
-- LibSerialize -> LibDeflate -> EncodeForPrint, as WeakAuras does for its own strings.
-- data = { version = addon version, snapshots = list, presses = press log };
-- libs = { serialize = LibSerialize, deflate = LibDeflate }; nil when the client lacks them.
-- Version 1 of the string held the bare snapshot list.
function M.export(data, libs)
  if not (libs and libs.serialize and libs.deflate) then return nil end
  data = data or {}
  local body = { version = data.version, snapshots = data.snapshots or {}, presses = data.presses or {} }
  local ser = libs.serialize:SerializeEx({ errorOnUnserializableType = false }, body)
  local packed = libs.deflate:CompressDeflate(ser, { level = 9 })
  return M.EXPORT_PREFIX .. libs.deflate:EncodeForPrint(packed)
end

local R = {}
R.__index = R

function M.new(saved, max, pressMax)
  saved[M.KEY] = saved[M.KEY] or {}
  saved[M.PRESS_KEY] = saved[M.PRESS_KEY] or {}
  return setmetatable({ list = saved[M.KEY], max = max or 30, last = -math.huge,
                        presses = saved[M.PRESS_KEY], pressMax = pressMax or M.PRESS_MAX }, R)
end

function R:push(S, plan)
  if (S.now or 0) - self.last < M.MIN_GAP then return false end
  self.last = S.now or 0
  local rec = { S = copy(S), plan = copy(plan) }
  self.list[#self.list + 1] = rec
  -- the next press is written into this snapshot (pressed); none before the next one: stays nil
  self.open = rec
  while #self.list > self.max do table.remove(self.list, 1) end
  return true
end

-- times in the log: milliseconds are enough and keep the export short
local function ms(x)
  if type(x) ~= "number" then return nil end
  return math.floor(x * 1000 + 0.5) / 1000
end
M.ms = ms

-- The player pressed key at now. shown = the plan on screen then, shownAt = its S.now,
-- due = when its first button became due (nil: nothing suggested).
-- Log entry: t = time (GetTime), key = pressed, sug / at = first suggested button and its
-- at as shown, hit = key == sug, delay = seconds from sug becoming due to the press
-- (negative: pressed early), cf = confirmed by the server (START / SUCCEEDED).
function R:press(key, now, shown, due)
  local st = shown and shown.steps and shown.steps[1]
  local e = { t = ms(now), key = key }
  if st then
    e.sug, e.at, e.hit = st.key, ms(st.at), st.key == key
    if due then e.delay = ms(now - due) end
  end
  local list = self.presses
  list[#list + 1] = e
  while #list > self.pressMax do table.remove(list, 1) end
  local open = self.open
  if open then
    self.open = nil
    local first = open.plan and open.plan.steps and open.plan.steps[1]
    open.pressed = { key = key, after = ms(now - (open.S.now or now)), matched = first ~= nil and first.key == key }
  end
  return e
end

-- the server confirmed the last press of key (START / SUCCEEDED after SENT)
function R:confirm(key)
  local e = self.presses[#self.presses]
  if e and e.key == key then e.cf = true end
end

return M
