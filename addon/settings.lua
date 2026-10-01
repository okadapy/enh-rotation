-- The addon's settings: the aura's options (tools/aura.lua M.OPTIONS) in SavedVariables and the
-- /dmr command. Pure functions over the option list and a config table.
local M = {}

M.HELP = {
  "/dmr list - settings; /dmr set <key> <value> - change one",
  "/dmr reset - defaults; /dmr export - copy window with snapshots",
  "/dmr lock | unlock - move the timeline; /dmr show | hide",
  "/dmr check - is everything ready (imbues, shield, totems, ranks)",
  "/dmr guide - the first-run guide again",
  "/dmr last - review of the last fights; /dmr history - per boss",
}
M.ACTIONS = { export = true, lock = true, unlock = true, show = true, hide = true, check = true, guide = true,
              last = true, history = true }

-- the addon's own options, on top of the aura's (tools/aura.lua M.OPTIONS): the aura has none of these
M.ADDON_OPTIONS = {
  { type = "toggle", key = "compact", name = "One button mode",
    desc = "Only the big icon and reminders: no lane, no swings, no stacks", default = false },
  { type = "toggle", key = "minimap", name = "Minimap button",
    desc = "Left-click: settings, right-click: show or hide the timeline, drag: move it", default = true },
  { type = "toggle", key = "levelCards", name = "What's new on level up",
    desc = "A short card at levels 10, 20 ... 80, out of combat, once", default = true },
  { type = "toggle", key = "elvui", name = "ElvUI style",
    desc = "Style these windows like ElvUI when it is installed. Turning it off takes a /reload", default = true },
  -- addon/review.lua: a line in chat once a fight is valued (/dmr last opens the full review)
  { type = "toggle", key = "fightSummary", name = "Fight summary in chat after a fight",
    desc = "After a fight of 20s or more: presses that matched the plan and the top tip (/dmr last: the full review)",
    default = true },
}

-- options plus the extra ones not in it yet, as a new list: the build's list stays the aura's
function M.withExtra(options, extra)
  local list, have = {}, {}
  for i, o in ipairs(options) do list[i], have[o.key] = o, true end
  for _, o in ipairs(extra or {}) do
    if not have[o.key] then list[#list + 1], have[o.key] = o, true end
  end
  return list
end

function M.defaults(options)
  local c = {}
  for _, o in ipairs(options) do c[o.key] = o.default end
  return c
end

function M.valid(o, v)
  if o.type == "range" then return type(v) == "number" and v >= o.min and v <= o.max end
  if o.type == "select" then return type(v) == "number" and v >= 1 and v <= #o.values and v == math.floor(v) end
  if o.type == "toggle" then return type(v) == "boolean" end
  return false
end

-- a slider's value on its step inside the range (the slider itself gives any float)
function M.snap(o, v)
  local step = o.step or 1
  local x = math.floor((v - o.min) / step + 0.5) * step + o.min
  if x < o.min then x = o.min elseif x > o.max then x = o.max end
  return tonumber(("%.4f"):format(x))
end

function M.merge(options, saved)
  local c = {}
  for _, o in ipairs(options) do
    local v = saved and saved[o.key]
    if v ~= nil and M.valid(o, v) then c[o.key] = v else c[o.key] = o.default end
  end
  return c
end

local TOGGLE = { on = true, ["true"] = true, ["1"] = true, off = false, ["false"] = false, ["0"] = false }

function M.coerce(o, text)
  text = (text or ""):lower()
  if o.type == "range" then
    local n = tonumber(text)
    if n and M.valid(o, n) then return n end
    return nil, ("%s: a number from %s to %s"):format(o.name, tostring(o.min), tostring(o.max))
  end
  if o.type == "select" then
    local n = tonumber(text)
    if n and M.valid(o, n) then return n end
    for i, v in ipairs(o.values) do
      if v:lower() == text then return i end
    end
    return nil, ("%s: one of %s"):format(o.name, table.concat(o.values, ", "))
  end
  local b = TOGGLE[text]
  if b ~= nil then return b end
  return nil, o.name .. ": on or off"
end

local function shown(o, v)
  if o.type == "select" then return tostring(o.values[v]) end
  if o.type == "toggle" then return v and "on" or "off" end
  return tostring(v)
end

local function find(options, key)
  key = (key or ""):lower()
  for _, o in ipairs(options) do
    if o.key:lower() == key then return o end
  end
end

function M.command(options, config, msg)
  local words = {}
  for w in (msg or ""):gmatch("%S+") do words[#words + 1] = w end
  local cmd = (words[1] or ""):lower()
  local r = { lines = {}, changed = false }
  -- bare /dmr is for players who don't know the commands: the window, not a wall of text
  if cmd == "" then
    r.action = "open"
  elseif M.ACTIONS[cmd] then
    r.action = cmd
  elseif cmd == "list" then
    for _, o in ipairs(options) do
      local extra = o.type == "select" and (" (" .. table.concat(o.values, ", ") .. ")") or ""
      r.lines[#r.lines + 1] = ("%s: %s = %s%s"):format(o.key, o.name, shown(o, config[o.key]), extra)
    end
  elseif cmd == "set" then
    local o = find(options, words[2])
    if not o then
      r.lines[1] = ("unknown setting: %s (see /dmr list)"):format(tostring(words[2]))
    else
      local v, err = M.coerce(o, table.concat(words, " ", 3))
      if v == nil then
        r.lines[1] = err
      else
        config[o.key] = v
        r.changed = true
        r.lines[1] = ("%s = %s"):format(o.name, shown(o, v))
      end
    end
  elseif cmd == "reset" then
    for k in pairs(config) do config[k] = nil end
    for k, v in pairs(M.defaults(options)) do config[k] = v end
    r.changed = true
    r.lines[1] = "settings reset to defaults"
  else
    for i, line in ipairs(M.HELP) do r.lines[i] = line end
  end
  return r
end

return M
