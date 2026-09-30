local spells = require("spells")
local model = require("model")

local M = {}

M.DEFAULTS = { width = 340, height = 120, nowX = 60, seconds = 6, big = 64, small = 38, icons = 4, gap = 2, lerp = 12, showReason = true }
M.ICON_Y = 70
M.TICK_Y = 22
M.WHITE = "Interface\\Buttons\\WHITE8X8"
M.GLOW = "Interface\\Buttons\\UI-ActionButton-Border"
M.COLORS = {
  mh = { 0.91, 0.76, 0.35, 1 }, oh = { 0.79, 0.83, 0.86, 1 },
  window = { 0.35, 0.9, 0.47, 0.35 }, now = { 1, 0.83, 0.35, 1 }, gcd = { 1, 1, 1, 0.07 },
  lane = { 0.23, 0.29, 0.24, 1 }, dotOn = { 0.37, 0.7, 1, 1 }, dotOff = { 0.11, 0.16, 0.23, 1 },
}

function M.options(opts)
  local o = {}
  for k, v in pairs(M.DEFAULTS) do o[k] = v end
  for k, v in pairs(opts or {}) do if v ~= nil then o[k] = v end end
  return o
end

function M.xOf(t, o)
  return o.nowX + t / o.seconds * (o.width - o.nowX)
end

function M.swingTimes(S, seconds)
  local out = {}
  local sw = S.swing
  if not sw or not sw.attacking then return out end
  for _, hand in ipairs({ "mh", "oh" }) do
    local h = sw[hand]
    if h and h.speed and h.speed > 0 then
      local t = math.max(0, h.next or 0)
      while t <= seconds do
        out[#out + 1] = { t = t, hand = hand }
        t = t + h.speed
      end
    end
  end
  table.sort(out, function(a, b) return a.t < b.t end)
  return out
end

function M.castWindow(S, swings)
  local mw = (S.buffs and S.buffs.mw and S.buffs.mw.stacks) or 0
  if not (S.spells and S.spells.lightningBolt) or mw < 1 or mw >= 5 or #swings == 0 then return nil end
  local need = model.castTime(S, "lightningBolt") + (S.latency or 0)
  local prev = 0
  for _, s in ipairs(swings) do
    if s.t - prev >= need then return prev, s.t - need end
    prev = s.t
  end
  return nil
end

function M.layout(plan, S, opts, elapsed)
  local o = M.options(opts)
  elapsed = elapsed or 0
  local mw = (S.buffs and S.buffs.mw and S.buffs.mw.stacks) or 0
  local L = { nowX = o.nowX, icons = {}, ticks = {}, window = nil, gcd = nil, reason = nil,
              dots = math.max(0, math.min(5, mw)) }
  local prev
  for _, st in ipairs((plan and plan.steps) or {}) do
    if #L.icons >= o.icons then break end
    local meta = spells.byKey[st.key]
    if meta then
      local t = math.max(0, (st.at or 0) - elapsed)
      local big = #L.icons == 0
      local size = big and o.big or o.small
      local x = M.xOf(t, o)
      if prev then x = math.max(x, prev.x + (prev.size + size) / 2 + o.gap) end
      x = math.min(x, o.width)
      local it = { key = st.key, icon = meta.icon, x = x, size = size, big = big, t = t }
      L.icons[#L.icons + 1] = it
      if big then L.reason = st.reason end
      prev = it
    end
  end
  local swings = M.swingTimes(S, o.seconds + elapsed)
  for _, s in ipairs(swings) do
    local t = s.t - elapsed
    if t >= 0 and t <= o.seconds then L.ticks[#L.ticks + 1] = { x = M.xOf(t, o), hand = s.hand, t = t } end
  end
  local a, b = M.castWindow(S, swings)
  if a then
    a, b = math.max(0, a - elapsed), b - elapsed
    if b > a then L.window = { x1 = M.xOf(a, o), x2 = M.xOf(math.min(b, o.seconds), o), t1 = a, t2 = b } end
  end
  local g = (S.gcdRemains or 0) - elapsed
  if g > 0 then L.gcd = { x1 = o.nowX, x2 = M.xOf(math.min(g, o.seconds), o) } end
  return L
end

local TL = {}
TL.__index = TL

local function tex(f, layer, color)
  local t = f:CreateTexture(nil, layer)
  t:SetTexture(M.WHITE)
  if color then t:SetVertexColor(unpack(color)) end
  t:Hide()
  return t
end

local function place(t, f, x, y, w, h)
  t:ClearAllPoints()
  t:SetPoint("CENTER", f, "BOTTOMLEFT", x, y)
  t:SetWidth(w)
  t:SetHeight(h)
  t:Show()
end

-- old: a timeline from a previous init of the aura. It is reused (frame and textures),
-- so editing aura options does not leave hidden frames behind.
function M.new(parent, opts, old)
  local tl = old
  if not tl then
    local f = CreateFrame("Frame", nil, parent)
    tl = setmetatable({ frame = f, icons = {}, allIcons = {}, ticks = {}, dots = {}, cur = {} }, TL)
    tl.lane = tex(f, "BACKGROUND", M.COLORS.lane)
    tl.gcd = tex(f, "BORDER", M.COLORS.gcd)
    tl.window = tex(f, "ARTWORK", M.COLORS.window)
    tl.now = tex(f, "OVERLAY", M.COLORS.now)
    tl.glow = f:CreateTexture(nil, "OVERLAY")
    tl.glow:SetTexture(M.GLOW)
    tl.glow:SetBlendMode("ADD")
    tl.glow:SetVertexColor(1, 0.82, 0.3, 1)
    tl.glow:Hide()
    for i = 1, 5 do tl.dots[i] = tex(f, "OVERLAY", M.COLORS.dotOff) end
    tl.reason = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tl.reason:Hide()
    tl.alert = f:CreateTexture(nil, "ARTWORK")
    tl.alert:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tl.alert:Hide()
  end
  tl:setup(parent, opts)
  return tl
end

-- (re)apply options: size, scale, icon count; forget the old plan
function TL:setup(parent, opts)
  local o = M.options(opts)
  local f = self.frame
  self.o = o
  if f.SetParent then f:SetParent(parent) end
  f:ClearAllPoints()
  f:SetWidth(o.width)
  f:SetHeight(o.height)
  f:SetPoint("CENTER", parent, "CENTER", 0, 0)
  if o.scale then f:SetScale(o.scale) end
  place(self.lane, f, (o.nowX + o.width) / 2, M.TICK_Y, o.width - o.nowX, 1)
  place(self.now, f, o.nowX, o.height / 2, 2, o.height)
  -- textures are only ever added: fewer icons after an option change just leaves some unused
  self.allIcons = self.allIcons or {}
  self.icons = {}
  for i = 1, math.max(o.icons, #self.allIcons) do
    local ic = self.allIcons[i]
    if not ic then
      ic = f:CreateTexture(nil, "ARTWORK")
      ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      self.allIcons[i] = ic
    end
    ic:Hide()
    if i <= o.icons then self.icons[i] = ic end
  end
  for i, d in ipairs(self.dots) do place(d, f, o.width - 8 - (5 - i) * 16, o.height - 8, 12, 12) end
  place(self.alert, f, 16, M.ICON_Y, 30, 30)
  self.alert:Hide()
  self.glow:Hide()
  self.reason:Hide()
  self.plan, self.S, self.cur, self.busy = nil, nil, {}, false
  self:start()
end

-- OnUpdate with a guard: if the previous tick died half-way (the sandbox has no protected calls),
-- stop instead of repeating the error every frame, and tell the owner (onError)
function TL:start()
  local tl = self
  self.frame:SetScript("OnUpdate", function(_, dt)
    if tl.busy then
      tl:stop()
      if tl.onError then tl.onError() end
      return
    end
    tl.busy = true
    tl:tick(dt)
    tl.busy = false
  end)
  self.frame:Show()
end

function TL:stop()
  self.frame:SetScript("OnUpdate", nil)
  self.frame:Hide()
end

function TL:render(plan, S, now)
  self.plan, self.S, self.at = plan, S, now or GetTime()
end

function TL:setAlert(alert)
  if alert and alert.icon then
    self.alert:SetTexture(alert.icon)
    self.alert:Show()
  else
    self.alert:Hide()
  end
end

function TL:tick(dt)
  if not self.plan or not self.S then return end
  local o, f = self.o, self.frame
  local L = M.layout(self.plan, self.S, o, GetTime() - self.at)
  local k = math.min(1, (dt or 0) * o.lerp)
  local seen, count = {}, {}
  for i, ic in ipairs(self.icons) do
    local it = L.icons[i]
    if it then
      -- the same spell can appear twice (two Bolts); each copy glides on its own
      count[it.key] = (count[it.key] or 0) + 1
      local id = count[it.key] == 1 and it.key or (it.key .. "#" .. count[it.key])
      it.id = id
      local x = self.cur[id]
      if x then x = x + (it.x - x) * k else x = it.x end
      self.cur[id] = x
      seen[id] = true
      ic:SetTexture(it.icon)
      place(ic, f, x, M.ICON_Y, it.size, it.size)
      if it.big then place(self.glow, f, x, M.ICON_Y, it.size * 1.7, it.size * 1.7) end
    else
      ic:Hide()
    end
  end
  if not L.icons[1] then self.glow:Hide() end
  for key in pairs(self.cur) do
    if not seen[key] then self.cur[key] = nil end
  end
  for i, tk in ipairs(L.ticks) do
    local t = self.ticks[i]
    if not t then
      t = tex(f, "ARTWORK")
      self.ticks[i] = t
    end
    t:SetVertexColor(unpack(M.COLORS[tk.hand]))
    place(t, f, tk.x, M.TICK_Y, 2, tk.hand == "mh" and 16 or 10)
  end
  for i = #L.ticks + 1, #self.ticks do self.ticks[i]:Hide() end
  if L.window then
    place(self.window, f, (L.window.x1 + L.window.x2) / 2, M.TICK_Y, math.max(2, L.window.x2 - L.window.x1), 12)
  else
    self.window:Hide()
  end
  if L.gcd then
    place(self.gcd, f, (L.gcd.x1 + L.gcd.x2) / 2, M.ICON_Y, L.gcd.x2 - L.gcd.x1, 44)
  else
    self.gcd:Hide()
  end
  for i, d in ipairs(self.dots) do
    d:SetVertexColor(unpack(i <= L.dots and M.COLORS.dotOn or M.COLORS.dotOff))
  end
  local first = L.icons[1]
  if o.showReason and L.reason and first then
    self.reason:SetText(L.reason)
    self.reason:ClearAllPoints()
    self.reason:SetPoint("TOP", f, "BOTTOMLEFT", self.cur[first.id], M.ICON_Y - first.size / 2 - 4)
    self.reason:Show()
  else
    self.reason:Hide()
  end
end

return M
