-- Raid debuffs on the target and what the group already gives (WotLK 3.3.5a), as S.mods
-- multipliers for damage / value. Addon only (tools/build.lua B.ADDON_SRC). Filled in by the
-- raid task of stage 2; until then nothing is found and S.mods stays nil.
local M = {}

M.DEBUFFS, M.BUFFS, M.OWN_TOTEMS = {}, {}, {}
-- value.SUPPORT (support totems' share of auto-attack damage) split by what each totem gives
M.SUPPORT = { haste = 0.04, strength = 0.02 }

function M.effects(found, buffs, own, gearMods)
  return nil
end

return M
