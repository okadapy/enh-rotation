local M = {}
M.GROUP_ID = "EnhRot"
M.HOST_ID = "EnhRot Timeline"
M.TOC = 30300
M.INTERNAL_VERSION = 90
M.WIDTH, M.HEIGHT = 340, 120
M.EVENT = "ENHROT_SHOW"

M.OPTIONS = {
  { type = "range", key = "scale", name = "Scale", min = 0.5, max = 2, step = 0.05, default = 1, width = 1, useDesc = false },
  { type = "range", key = "seconds", name = "Timeline length (s)", min = 3, max = 10, step = 0.5, default = 6, width = 1, useDesc = false },
  { type = "range", key = "icons", name = "Icons on timeline", min = 1, max = 4, step = 1, default = 4, width = 1, useDesc = false },
  { type = "select", key = "mode", name = "Mode", desc = "auto picks solo/group/raid by your group",
    values = { "auto", "solo", "group", "raid", "pvp (reserved)" }, default = 1, width = 1, useDesc = true },
  { type = "toggle", key = "showReason", name = "Show reason under icon", default = true, width = 1, useDesc = false },
  { type = "toggle", key = "showLust", name = "Show Bloodlust ready in group", default = true, width = 1, useDesc = false },
  { type = "toggle", key = "record", name = "Record snapshots for bug reports", default = false, width = 1, useDesc = false },
  { type = "toggle", key = "export", name = "Export snapshots (copy window)", default = false, width = 1, useDesc = false },
  { type = "toggle", key = "printDebug", name = "Print debug to chat", default = false, width = 1, useDesc = false },
}

function M.defaultConfig()
  local c = {}
  for _, o in ipairs(M.OPTIONS) do c[o.key] = o.default end
  return c
end

local function animation()
  local none = function() return { type = "none", duration_type = "seconds", easeType = "none", easeStrength = 3 } end
  return { start = none(), main = none(), finish = none() }
end

function M.hostTrigger()
  return [[function(allstates, event)
  if event ~= "ENHROT_SHOW" and event ~= "OPTIONS" then return false end
  allstates[""] = { show = true, changed = true, progressType = "static", value = 0, total = 0, autoHide = false }
  return true
end]]
end

function M.host(initCode)
  return {
    id = M.HOST_ID, uid = "EnhRotHost01", parent = M.GROUP_ID, regionType = "texture",
    internalVersion = M.INTERNAL_VERSION, tocversion = M.TOC,
    width = M.WIDTH, height = M.HEIGHT, xOffset = 0, yOffset = 0,
    anchorPoint = "CENTER", selfPoint = "CENTER", anchorFrameType = "SCREEN", frameStrata = 1,
    texture = "Interface\\Buttons\\WHITE8X8", color = { 0, 0, 0, 0 }, blendMode = "BLEND",
    rotation = 0, discrete_rotation = 0, rotate = true, mirror = false, desaturate = false, alpha = 1,
    triggers = {
      { trigger = { type = "custom", custom_type = "stateupdate", check = "event", events = M.EVENT,
                    custom = M.hostTrigger(), customVariables = "{}", debuffType = "HELPFUL",
                    unit = "player", names = {}, spellIds = {} },
        untrigger = {} },
      activeTriggerMode = -10, disjunctive = "any",
    },
    load = { use_class = true, class = { single = "SHAMAN", multi = {} }, spec = { multi = {} }, talent = { multi = {} }, size = { multi = {} } },
    actions = { init = { do_custom = true, custom = initCode }, start = {}, finish = {} },
    conditions = {}, animation = animation(), subRegions = {},
    authorOptions = M.OPTIONS, config = M.defaultConfig(), information = {},
  }
end

function M.group(ids)
  return {
    id = M.GROUP_ID, uid = "EnhRotGroup01", regionType = "group", internalVersion = M.INTERNAL_VERSION, tocversion = M.TOC,
    controlledChildren = ids, anchorPoint = "CENTER", selfPoint = "CENTER", anchorFrameType = "SCREEN",
    xOffset = 0, yOffset = -200, frameStrata = 1, scale = 1, alpha = 1,
    border = false, borderEdge = "Square Full White", borderOffset = 4, borderInset = 1, borderSize = 2,
    borderColor = { 0, 0, 0, 1 }, backdropColor = { 1, 1, 1, 0.5 },
    triggers = { { trigger = { type = "aura2", debuffType = "HELPFUL", unit = "player", names = {}, spellIds = {} }, untrigger = {} } },
    load = { class = { multi = {} }, spec = { multi = {} }, talent = { multi = {} }, size = { multi = {} } },
    actions = { init = {}, start = {}, finish = {} }, animation = animation(), conditions = {},
    subRegions = {}, config = {}, authorOptions = {}, information = {},
  }
end

function M.transmit(initCode, version)
  return { m = "d", d = M.group({ M.HOST_ID }), c = { M.host(initCode) }, v = 1421, s = version or "5.22.0" }
end

return M
