-- The big icon explained on mouse-over: what it is, when, why, what follows, and the runner-up
-- (the best chain of another first button from the same search, planner.alts) with how much
-- worse it is. The timeline never takes the mouse (no click is lost in a fight): the cursor is
-- polled over a frame of our own on the big icon. Out of combat on hover; in combat only with
-- Shift held (no popups by themselves in a fight).
local spells = require("spells")
local search = require("search")

local M = {}
M.OPTION = { type = "toggle", key = "hoverTips", name = "Explain the big icon on mouse-over (Shift in combat)", default = true }
M.POLL = 0.1      -- s between mouse checks
M.REFRESH = 1.0   -- s between runner-up updates while the tooltip is open
M.MAX_RIVALS = 12 -- chains replayed per update at most
M.NOW = 0.05      -- due within this: "Press now"
M.CLOSE = 1       -- % worse below this: "about as good"
M.MORE = 3        -- buttons listed after the first
M.GREY = { 0.7, 0.7, 0.7 }
M.GOLD = { 1, 0.82, 0 }

local function name(key)
  local m = spells.byKey[key]
  return m and m.name or key
end

local function shifted(steps, by)
  local out = {}
  for i, st in ipairs(steps) do
    out[i] = { key = st.key, at = math.max(0, st.at - by), reason = st.reason, afterSwing = st.afterSwing }
  end
  return out
end

-- The shown plan and the best chain of every other first button, replayed on one state (the
-- planner's view: its own casts in flight), so the two values compare.
function M.rivals(view, evaluate, firstKey)
  evaluate, firstKey = evaluate or search.evaluate, firstKey or search.firstKey
  local plan, p, S = view.plan, view.planner, view.S
  local st = plan and plan.steps and plan.steps[1]
  if not (st and S and p) then return nil end
  local s = p.prepare and p:prepare(S) or S
  local v, _, h = evaluate(s, plan.steps)
  if not v then return nil end
  local out = { value = v, horizon = h or v }
  local alts = p.alts
  if not alts then return out end
  local by = (S.now or 0) - (p.altsNow or S.now or 0)
  local mine, keys = firstKey(st), {}
  for f, chain in pairs(alts) do
    if f ~= mine and #chain > 0 then keys[#keys + 1] = f end
  end
  table.sort(keys) -- the same ones every time when there are more than MAX_RIVALS
  local best
  for i = 1, math.min(#keys, M.MAX_RIVALS) do
    local chain = alts[keys[i]]
    local w = evaluate(s, shifted(chain, by))
    if w and (not best or w > best.value) then
      best = { key = chain[1].key, afterSwing = chain[1].afterSwing, value = w }
    end
  end
  if best then
    best.loss = v - best.value
    local base = math.abs(out.horizon)
    best.pct = base > 0 and best.loss / base * 100 or 0
    out.second = best
  end
  return out
end

local function line(out, text, c) out[#out + 1] = { text, c[1], c[2], c[3] } end

function M.lines(view, elapsed, hotkey, r)
  local steps = view.plan and view.plan.steps
  local st = steps and steps[1]
  if not st then return nil end
  local out = {}
  line(out, hotkey and (name(st.key) .. " [" .. hotkey .. "]") or name(st.key), { 1, 1, 1 })
  local wait = (st.at or 0) - (elapsed or 0)
  line(out, wait <= M.NOW and "Press now" or ("Press in %.1f s"):format(wait), M.GOLD)
  if st.reason and st.reason ~= "" then line(out, "Why: " .. st.reason, { 1, 1, 1 }) end
  local after = {}
  for i = 2, math.min(#steps, M.MORE + 1) do after[#after + 1] = name(steps[i].key) end
  if #after > 0 then line(out, "Then: " .. table.concat(after, ", "), M.GREY) end
  local sec = r and r.second
  if sec then
    local what = name(sec.key) .. (sec.afterSwing and " after the swing" or "")
    if sec.pct < M.CLOSE then
      line(out, ("Runner-up: %s - about as good"):format(what), M.GREY)
    else
      line(out, ("Runner-up: %s - %d%% worse over the next %d s"):format(what, math.floor(sec.pct + 0.5), search.HORIZON), M.GREY)
    end
  elseif r then
    line(out, "No other first button comes close", M.GREY)
  end
  return out
end

local E = {}
E.__index = E

function M.new(deps)
  deps.over = deps.over or function(f) return f.IsMouseOver and f:IsMouseOver() end
  return setmetatable({ deps = deps, wait = 0, shown = false, refreshAt = -math.huge }, E)
end

function E:start(frame)
  self.driver = frame
  frame:SetScript("OnUpdate", function(_, dt) self:tick(dt) end)
end

-- a frame of our own over the big icon, never mouse-enabled (IsMouseOver works without it)
function E:area(view)
  local a = self.hover
  if not a or a.on ~= view.frame then
    a = CreateFrame("Frame", nil, view.frame)
    a.on = view.frame
    self.hover = a
  end
  if a.icon ~= view.icon then
    a:ClearAllPoints()
    a:SetAllPoints(view.icon)
    a.icon = view.icon
  end
  return a
end

function E:close()
  local tip = self.deps.tooltip
  if self.shown and (not tip.IsOwned or tip:IsOwned(self.hover)) then tip:Hide() end
  self.shown = false
end

function E:tick(dt)
  self.wait = self.wait - (dt or 0)
  if self.wait > 0 then return end
  self.wait = M.POLL
  local d = self.deps
  local view = d.enabled() and d.view()
  local st = view and view.active and view.plan and view.plan.steps[1]
  if not (st and view.icon and view.icon:IsShown()) then return self:close() end
  local a = self:area(view)
  if not (d.over(a) and (not d.inCombat() or d.shift())) then return self:close() end
  local now = d.now()
  if self.shown and now < self.refreshAt and self.first == st.key then return end
  self.refreshAt, self.first = now + M.REFRESH, st.key
  local L = M.lines(view, now - (view.at or now), d.hotkey(st.key), M.rivals(view, d.evaluate, d.firstKey))
  local tip = d.tooltip
  tip:SetOwner(a, "ANCHOR_TOP")
  tip:SetText(L[1][1], L[1][2], L[1][3], L[1][4])
  for i = 2, #L do tip:AddLine(L[i][1], L[i][2], L[i][3], L[i][4], true) end
  tip:Show()
  self.shown = true
end

return M
