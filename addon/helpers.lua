-- The stage 1 helpers in one place: the lit action button and its key, the big icon's tooltip,
-- the checklist. core starts them once a shaman is logged in; each reads the engine only
-- through core.view() and its option live (an option change needs no engine restart).
local highlight = require("highlight")
local explain = require("explain")
local ready = require("ready")

local M = {}

function M.options()
  local list = {}
  for _, o in ipairs(highlight.OPTIONS) do list[#list + 1] = o end
  list[#list + 1] = explain.OPTION
  for _, o in ipairs(ready.OPTIONS) do list[#list + 1] = o end
  return list
end

-- the frame there is, if any (as core does with its own named frames): one driver per helper
local function frame(name) return _G[name] or CreateFrame("Frame", name) end

function M.start(core, say)
  local h = {}
  -- read anew each call: /dmr reset, the settings window and a profile switch replace the config
  -- table (core.config: the active profile's values; db.config is the one before profiles)
  local function config() return core.config or core.db.config end
  h.highlight = highlight.new({ view = core.view, config = config, now = GetTime })
  h.highlight:start(frame("DoubtMyRotationHighlight"))
  h.explain = explain.new({
    view = core.view, now = GetTime, tooltip = GameTooltip,
    enabled = function() return config().hoverTips ~= false end,
    hotkey = function(key) return h.highlight:hotkey(key) end,
    inCombat = function() return UnitAffectingCombat("player") end,
    shift = function() return IsShiftKeyDown and IsShiftKeyDown() end,
  })
  h.explain:start(frame("DoubtMyRotationExplain"))
  h.ready = ready.new({ view = core.view, config = config, db = core.db, say = say, now = GetTime })
  h.ready:start(frame("DoubtMyRotationChecks"))
  h.check = function() h.ready:open() end
  return h
end

return M
