local M = {}

M.MELEE_WINDOW = 2.5
M.NEARBY_WINDOW = 6

local DAMAGE = {
  SWING_DAMAGE = true, SWING_MISSED = true, RANGE_DAMAGE = true, RANGE_MISSED = true,
  SPELL_DAMAGE = true, SPELL_MISSED = true, SPELL_PERIODIC_DAMAGE = true,
  SPELL_PERIODIC_MISSED = true, DAMAGE_SHIELD = true,
}
local MELEE = { SWING_DAMAGE = true, SWING_MISSED = true }
local DEATH = { UNIT_DIED = true, UNIT_DESTROYED = true, PARTY_KILL = true }

local E = {}
E.__index = E

function M.new()
  return setmetatable({ melee = {}, nearby = {}, mine = {} }, E)
end

function E:onEvent(now, subEvent, src, dst, player)
  if not subEvent then return end
  if subEvent == "SPELL_SUMMON" then
    if src and src == player and dst then self.mine[dst] = true end
    return
  end
  if DEATH[subEvent] then
    if dst then
      self.melee[dst] = nil
      self.nearby[dst] = nil
      self.mine[dst] = nil
    end
    return
  end
  if not DAMAGE[subEvent] then return end
  local fromMe = src ~= nil and (src == player or self.mine[src])
  local toMe = dst ~= nil and (dst == player or self.mine[dst])
  if fromMe and dst and not toMe then
    self.nearby[dst] = now
  elseif toMe and src and not fromMe then
    self.nearby[src] = now
    if MELEE[subEvent] and dst == player then self.melee[src] = now end
  end
end

function E:counts(now)
  local m, n = 0, 0
  for g, t in pairs(self.melee) do
    if now - t <= M.MELEE_WINDOW then m = m + 1 else self.melee[g] = nil end
  end
  for g, t in pairs(self.nearby) do
    if now - t <= M.NEARBY_WINDOW then n = n + 1 else self.nearby[g] = nil end
  end
  if n < m then n = m end
  return m, n
end

return M
