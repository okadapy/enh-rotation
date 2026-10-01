-- Tips after a fight: pure functions over the collector's numbers (addon/fightlog.lua). Every
-- tip has a weight in damage (rough for the mechanics: through the plan's damage per second),
-- only for the order; the texts are soft ("can do better"), never "played badly".
local spells = require("spells")

local M = {}
M.MAX = 5
M.WRONG_SHARE = 0.15 -- a wrong pair is a tip from this share of the fight's loss
M.DELAY = 0.3
M.MW_WASTED = 2
M.MW_IDLE = 3
M.GCD_IDLE = 0.05 -- share of the fight
M.SWINGS = 3
M.FS_UPTIME = 0.8
M.FS_SEEN = 30
M.PREP = 5
M.TRENDS = { better = "better than before", worse = "worse than before", same = "same as before" }

function M.k(n)
  if n >= 1000 then return ("%.1fk"):format(n / 1000) end
  return tostring(math.floor(n + 0.5))
end

function M.pct(rate)
  if not rate then return "-" end
  return ("%d%%"):format(math.floor(rate * 100 + 0.5))
end

local function name(key)
  local s = spells.byKey[key]
  return s and s.name or key
end

local function topPair(f)
  local top
  for _, p in pairs(f.pairs or {}) do
    if not top or p.lost > top.lost or (p.lost == top.lost and p.sug .. p.key < top.sug .. top.key) then top = p end
  end
  return top
end

local PREP = {
  { code = "prep_shield", field = "shield", text = "No Lightning Shield for %ds" },
  { code = "prep_totems", field = "totems", text = "No fire totem for %ds" },
  { code = "prep_enchants", field = "enchants", text = "Weapon enchant missing for %ds" },
  { code = "prep_attack", field = "autoAttack", text = "Auto-attack off in melee for %ds" },
}

function M.tips(f)
  local out, dps = {}, f.dps or 0
  local function add(code, weight, text, detail)
    out[#out + 1] = { code = code, weight = weight, text = text, detail = detail }
  end
  local top = topPair(f)
  if top and f.lost > 0 and top.lost > 0 and top.lost >= M.WRONG_SHARE * f.lost then
    add("wrong", top.lost, ("Often pressed %s where %s was better (~%s damage)"):format(name(top.key), name(top.sug), M.k(top.lost)),
      ("%d times; follow the big icon when the two differ"):format(top.count))
  end
  if f.delay and f.delay > M.DELAY then
    add("delay", (f.suggested or 0) * (f.delay - M.DELAY) * dps,
      ("Presses come ~%.1fs late - try queueing the next button earlier"):format(f.delay),
      "Press as the icon reaches the line; the client queues the next spell")
  end
  local mw = f.mw or {}
  if (mw.wasted or 0) >= M.MW_WASTED then
    add("mw_wasted", mw.wasted * 0.3 * dps, ("%d Maelstrom stacks wasted - cast at 5 right away"):format(mw.wasted),
      "A stack that comes at 5 is lost; Lightning Bolt at 5 is instant")
  end
  if (mw.idle or 0) >= M.MW_IDLE then
    add("mw_idle", mw.idle * 0.2 * dps, ("Sat on 5 Maelstrom stacks for %ds"):format(math.floor(mw.idle + 0.5)),
      "At 5 stacks the next swing can waste a proc")
  end
  if f.seconds and f.seconds > 0 and (f.gcdIdle or 0) >= M.GCD_IDLE * f.seconds then
    add("gcd_idle", f.gcdIdle * dps, ("GCD idle %d%% of the fight"):format(math.floor(f.gcdIdle / f.seconds * 100 + 0.5)),
      "A button was ready and the global cooldown free, but nothing was pressed")
  end
  if (f.swings or 0) >= M.SWINGS then
    add("swings", f.swings * 0.5 * dps, ("%d swings delayed by casts"):format(f.swings),
      "Hard casts in melee push the swings back; cast at 5 Maelstrom stacks")
  end
  local fs = f.fs or {}
  if (fs.seen or 0) >= M.FS_SEEN and fs.up / fs.seen < M.FS_UPTIME then
    add("flame_shock", (fs.seen - fs.up) * 0.1 * dps, ("Flame Shock uptime %d%%"):format(math.floor(fs.up / fs.seen * 100 + 0.5)),
      "Lava Lash and the ticks need it on the target")
  end
  local prep = f.prep or {}
  for _, p in ipairs(PREP) do
    local s = prep[p.field] or 0
    if s >= M.PREP then add(p.code, s * 0.1 * dps, p.text:format(math.floor(s + 0.5)), "Before the pull or between packs") end
  end
  if #out == 0 then
    add("clean", 0, ("Clean fight - %s matched, ~%.2fs delay"):format(M.pct(f.rate), f.delay or 0), nil)
    return out
  end
  table.sort(out, function(a, b) return a.weight > b.weight or (a.weight == b.weight and a.code < b.code) end)
  while #out > M.MAX do table.remove(out) end
  return out
end

-- the line in chat after a fight (the caller adds the addon's tag); trend: history.trend or nil
function M.summary(f, tips, trend)
  local head = ("%s - %s matched, ~%s damage lost"):format(f.key or f.name, M.pct(f.rate), M.k(f.lost or 0))
  if trend and M.TRENDS[trend] then head = head .. ", " .. M.TRENDS[trend] end
  local tip = tips[1]
  local tail = (tip and tip.code ~= "clean") and ("Tip: " .. tip.text .. ".") or "Clean fight."
  return head .. ". " .. tail .. " /dmr last"
end

return M
