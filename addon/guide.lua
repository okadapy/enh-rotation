-- One message window at a time, never in a fight: the first-run guide and the level cards wait
-- here. Entering combat hides the open one and puts it first in line; it comes back after.
local M = {}

local Q = {}
Q.__index = Q

local function fighting()
  if InCombatLockdown() then return true end
  return UnitAffectingCombat("player") and true or false
end

function M.new(deps)
  deps = deps or {}
  return setmetatable({ items = {}, current = nil, fighting = deps.fighting or fighting }, Q)
end

local function has(q, id)
  if q.current and q.current.id == id then return true end
  for _, it in ipairs(q.items) do
    if it.id == id then return true end
  end
  return false
end

-- item = { id, show = function(close) ... end, hide = function() ... end }: show opens the window and
-- calls close() once the player is done with it; hide puts it away without close (a fight began)
function Q:push(item)
  if has(self, item.id) then return false end
  self.items[#self.items + 1] = item
  self:pump()
  return true
end

function Q:pump()
  if self.current or #self.items == 0 or self.fighting() then return end
  local item = table.remove(self.items, 1)
  -- each showing gets its own close: one handed out before a fight hid the window must not close
  -- the same window shown again after it
  local shown = {}
  self.current, self.shown = item, shown
  item.show(function() self:finish(item, shown) end)
end

function Q:finish(item, shown)
  if self.current ~= item or (shown and self.shown ~= shown) then return end
  self.current, self.shown = nil, nil
  self:pump()
end

function Q:combat()
  local item = self.current
  if not item then return end
  self.current, self.shown = nil, nil
  if item.hide then item.hide() end
  table.insert(self.items, 1, item)
end

function Q:start(frame)
  frame:RegisterEvent("PLAYER_REGEN_DISABLED")
  frame:RegisterEvent("PLAYER_REGEN_ENABLED")
  frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then self:combat() else self:pump() end
  end)
end

return M
