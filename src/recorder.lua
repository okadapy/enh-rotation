local M = {}
M.KEY = "enhrotSnapshots"
M.MIN_GAP = 2

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

local R = {}
R.__index = R

function M.new(saved, max)
  saved[M.KEY] = saved[M.KEY] or {}
  return setmetatable({ list = saved[M.KEY], max = max or 30, last = -math.huge }, R)
end

function R:push(S, plan)
  if (S.now or 0) - self.last < M.MIN_GAP then return false end
  self.last = S.now or 0
  self.list[#self.list + 1] = { S = copy(S), plan = copy(plan) }
  while #self.list > self.max do table.remove(self.list, 1) end
  return true
end

return M
