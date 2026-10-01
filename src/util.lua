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
-- The shield the player wants kept up (S.shieldPref "auto" / "lightning" / "water"; nil = "auto"):
-- Lightning Shield when asked for, or on "auto" unless Water Shield is on (S.player.shield).
-- Only one shield can be up, so casting Lightning Shield over Water Shield would remove it.
function M.wantsLightningShield(S)
  local pref = S.shieldPref
  if pref == "lightning" then return true end
  if pref == "water" then return false end
  return not (S.player and S.player.shield == "water")
end
return M
