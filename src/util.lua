local M = {}
function M.copy(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = M.copy(v) end
  return r
end
function M.merge(dst, patch)
  for k, v in pairs(patch or {}) do
    if type(v) == "table" and type(dst[k]) == "table" then M.merge(dst[k], v) else dst[k] = M.copy(v) end
  end
  return dst
end
function M.clamp(x, lo, hi) if x < lo then return lo elseif x > hi then return hi end return x end
-- A hostile NPC fighting the shaman runs to him at about MOB_SPEED yards per second: from the far
-- edge of a range band (snapshot.range) it needs approachEta(band) seconds to reach melee.
M.MOB_SPEED = 7
M.BAND_YARDS = { ["20"] = 20, ["30"] = 30 }
function M.approachEta(range)
  local y = M.BAND_YARDS[range]
  return y and y / M.MOB_SPEED or nil
end
return M
