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

M.EXPORT_PREFIX = "!ENHROT:1!"

-- The recorded list as one printable string for a bug report (copied from the export window):
-- LibSerialize -> LibDeflate -> EncodeForPrint, as WeakAuras does for its own strings.
-- libs = { serialize = LibSerialize, deflate = LibDeflate }; nil when the client lacks them.
function M.export(list, libs)
  if not (libs and libs.serialize and libs.deflate) then return nil end
  local ser = libs.serialize:SerializeEx({ errorOnUnserializableType = false }, list or {})
  local packed = libs.deflate:CompressDeflate(ser, { level = 9 })
  return M.EXPORT_PREFIX .. libs.deflate:EncodeForPrint(packed)
end

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
