local M = {}

M.HAND_TOLERANCE = 0.25
M.CALIBRATE_VOTES = 3
M.HORIZON = 6.0
M.EXTRA_WINDOW = 0.1
M.CAST_RESET = { lightningBolt = true, chainLightning = true }
M.HAND_OFFSET = 0.2 -- the server swings the off hand at least 0.2 s after the main hand

local HANDS = { "mh", "oh" }

local Clock = {}
Clock.__index = Clock

-- runtime may swap c.saved at any moment, so every access goes through here
local function store(self)
  local s = self.saved
  if type(s) ~= "table" then
    s = {}
    self.saved = s
  end
  s.votes = s.votes or {}
  s.reset = s.reset or {}
  return s
end

function M.new(saved)
  saved = saved or {}
  saved.votes = saved.votes or {}
  saved.reset = saved.reset or {}
  return setmetatable({
    saved = saved,
    attacking = false,
    hands = {},
    cast = nil,
    extraLeft = 0,
    extraAt = -1,
    obs = nil,
    resyncs = 0,
  }, Clock)
end

function Clock:onSpeed(now, mhSpeed, ohSpeed)
  local speeds = { mh = mhSpeed, oh = ohSpeed }
  for _, h in ipairs(HANDS) do
    local sp = speeds[h]
    local st = self.hands[h]
    if not sp or sp <= 0 then
      self.hands[h] = nil
    elseif not st then
      self.hands[h] = { speed = sp, due = now + sp }
    else
      local k = sp / st.speed
      local function scale(due)
        local left = due - now
        if left > 0 then return now + left * k end
        return due
      end
      st.due = scale(st.due)
      local o = self.obs
      if h == "mh" and o then o.oldDue, o.resetDue = scale(o.oldDue), scale(o.resetDue) end
      st.speed = sp
    end
  end
end

function Clock:onAttack(now, on)
  self.attacking = on and true or false
  if not self.attacking then return end
  for _, h in ipairs(HANDS) do
    local st = self.hands[h]
    if st and st.due < now then st.due = now end
  end
end

function Clock:onExtraAttacks(now, count)
  self.extraLeft = self.extraLeft + (count or 1)
  self.extraAt = now
end

-- Returns "mh" if this swing settles a pending instant-spell observation.
function Clock:_calibrate(now)
  local o = self.obs
  if not o then return nil end
  if now > math.max(o.oldDue, o.resetDue) + M.HAND_TOLERANCE then
    self.obs = nil
    return nil
  end
  local dOld, dReset = math.abs(now - o.oldDue), math.abs(now - o.resetDue)
  -- the off hand trails by ~0.2 s: skip only a swing that fits it better than both hypotheses
  local oh = self.hands.oh
  if oh and math.abs(now - oh.due) < math.min(dOld, dReset) then return nil end
  self.obs = nil
  if math.min(dOld, dReset) > M.HAND_TOLERANCE then return nil end
  local saved = store(self)
  local v = saved.votes[o.key]
  if not v then
    v = { reset = 0, keep = 0 }
    saved.votes[o.key] = v
  end
  if dReset < dOld then v.reset = v.reset + 1 else v.keep = v.keep + 1 end
  if v.reset - v.keep >= M.CALIBRATE_VOTES then
    saved.reset[o.key] = true
  elseif v.keep - v.reset >= M.CALIBRATE_VOTES then
    saved.reset[o.key] = false
  end
  return "mh"
end

function Clock:onSwing(now, isExtra)
  if isExtra then return "extra" end
  if self.extraLeft > 0 then
    if now - self.extraAt <= M.EXTRA_WINDOW then
      self.extraLeft = self.extraLeft - 1
      return "extra"
    end
    self.extraLeft = 0
  end
  local best = self:_calibrate(now)
  if not best then
    local bestErr, early
    for _, h in ipairs(HANDS) do
      local st = self.hands[h]
      if st then
        local err = math.abs(now - st.due)
        if not bestErr or err < bestErr then best, bestErr = h, err end
        if not early or st.due < self.hands[early].due then early = h end
      end
    end
    if not best then return nil end
    local other = early == "mh" and "oh" or "mh"
    local o = self.hands[other]
    if bestErr > M.HAND_TOLERANCE then
      -- lost sync: the earliest hand swung now, shift the other one by the same amount
      self.resyncs = self.resyncs + 1
      local shift = now - self.hands[early].due
      if o then
        o.due = o.due + shift
        if o.due < now + M.HAND_OFFSET then o.due = now + M.HAND_OFFSET end
      end
      best = early
    elseif math.abs(now - self.hands[early].due) <= M.HAND_TOLERANCE then
      best = early -- both hands fit: the later hand never swings first
    end
  end
  local st = self.hands[best]
  if not st then return nil end
  st.due = now + st.speed
  return best
end

function Clock:onCastStart(now, key, mwStacks, castTime)
  if not castTime or castTime <= 0 then return end
  self.obs = nil
  self.cast = { key = key, start = now, finish = now + castTime, mw = mwStacks or 0 }
end

-- spell pushback: UNIT_SPELLCAST_DELAYED, newFinish from UnitCastingInfo endTime
function Clock:onCastDelayed(now, newFinish)
  local c = self.cast
  if c and newFinish and newFinish > c.finish then c.finish = newFinish end
end

function Clock:onCastEnd(now, key, mwStacks, ok)
  local c = self.cast
  self.cast = nil
  if not c then return end
  local reset = ok and M.CAST_RESET[c.key] and (c.mw or 0) == 0
  for _, h in ipairs(HANDS) do
    local st = self.hands[h]
    if st then
      if reset then
        st.due = now + st.speed
      elseif st.due < now then
        st.due = now
      end
    end
  end
end

function Clock:onInstant(now, key)
  self.obs = nil
  local mh = self.hands.mh
  if not mh or not self.attacking then return end
  local decided = store(self).reset[key]
  if decided == true then
    for _, h in ipairs(HANDS) do
      local st = self.hands[h]
      if st then st.due = now + st.speed end
    end
    return
  end
  if decided == false then return end
  local resetDue = now + mh.speed
  if math.abs(resetDue - mh.due) >= 2 * M.HAND_TOLERANCE then
    self.obs = { key = key, at = now, oldDue = mh.due, resetDue = resetDue }
  end
end

function Clock:state(now)
  local out = { attacking = self.attacking, resetByInstant = {} }
  for k, v in pairs(store(self).reset) do
    if v then out.resetByInstant[k] = true end
  end
  local c = self.cast
  for _, h in ipairs(HANDS) do
    local st = self.hands[h]
    if st then
      local due = st.due
      if c and now < c.finish then
        if M.CAST_RESET[c.key] and c.mw == 0 then
          due = c.finish + st.speed
        elseif due < c.finish then
          due = c.finish
        end
      end
      out[h] = { next = math.max(0, due - now), speed = st.speed }
    end
  end
  return out
end

function Clock:castWindow(now, castTime, latency)
  if not self.attacking then return 0, M.HORIZON end
  local s = self:state(now)
  local need = castTime + (latency or 0)
  local events = {}
  for _, h in ipairs(HANDS) do
    local st = s[h]
    if st and st.speed > 0 then
      local t = st.next
      while t <= M.HORIZON do
        events[#events + 1] = t
        t = t + st.speed
      end
    end
  end
  table.sort(events)
  local prev = 0
  for _, t in ipairs(events) do
    if t - prev >= need then return prev, t - need end
    prev = t
  end
  if M.HORIZON - prev >= need then return prev, M.HORIZON - need end
  return nil
end

return M
