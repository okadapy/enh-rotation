-- Equipment and glyphs -> S.mods additions (gear_data). Pure: snapshot reads the item and glyph
-- ids and calls effects once per equipment change (snapshot.scan), not per snapshot.
-- Addon only (tools/build.lua B.ADDON_SRC).
local data = require("gear_data")

local M = {}

-- item id -> set key; one key for every version of a piece (10 / 25, item levels, factions)
local SET_OF = {}
for set, ids in pairs(data.SETS) do
  for _, id in ipairs(ids) do SET_OF[id] = set end
end

local function add(mods, patch)
  for k, v in pairs(patch) do mods[k] = (mods[k] or 0) + v end
end

-- items: equipped item ids (any slots); glyphs: glyph spell ids. nil when nothing is known.
function M.effects(items, glyphs)
  local mods, pieces, any = {}, {}, false
  for _, id in ipairs(items or {}) do
    local relic = data.RELICS[id]
    if relic then add(mods, relic); any = true end
    local proc = data.PROCS[id]
    if proc then mods.proc = proc; any = true end -- a table, not an addition (one relic slot)
    local set = SET_OF[id]
    if set then pieces[set] = (pieces[set] or 0) + 1 end
  end
  for _, b in ipairs(data.BONUS) do
    if (pieces[b[1]] or 0) >= b[2] then
      mods[b[3]] = (mods[b[3]] or 0) + b[4]
      any = true
    end
  end
  for _, id in ipairs(glyphs or {}) do
    local g = data.GLYPHS[id]
    if g then add(mods, g); any = true end
  end
  return any and mods or nil
end

return M
