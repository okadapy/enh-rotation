-- Profiles: whole sets of settings shared by the account's characters (DoubtMyRotationDB.profiles),
-- picked per character (DoubtMyRotationCharDB) by hand or by where the character is. Pure functions
-- over the two saved tables; the client's calls stay in addon/core.lua.
local settings = require("settings")

local M = {}
M.DEFAULT = "Default"
M.MAX_LEVEL = 80
M.NAME_MAX = 24
-- the addon's own look and chat, not the rotation: one value for the whole account
M.ACCOUNT = { updateCheck = true, minimap = true, levelCards = true, elvui = true }
-- the auto rules, the first that matches wins; in the open world the profile picked by hand
M.RULES = { "pvp", "raid", "party", "leveling" }
M.RULE_NAMES = { pvp = "Battleground or arena", raid = "In a raid", party = "In a dungeon",
                 leveling = "While leveling (below 80)" }
-- IsInInstance()'s second value -> rule
local WHERE = { pvp = "pvp", arena = "pvp", raid = "raid", party = "party" }

local function copy(t)
  local c = {}
  for k, v in pairs(t or {}) do c[k] = v end
  return c
end

-- Before profiles there was one account-wide config, place and hidden flag. The config becomes
-- the Default profile (a copy: db.config stays, an older version still finds its settings), the
-- place and the flag each character's own on its first login.
function M.migrate(db, char)
  local old = type(db.config) == "table" and db.config or nil
  if type(db.profiles) ~= "table" then db.profiles = { [M.DEFAULT] = copy(old) } end
  if type(db.profiles[M.DEFAULT]) ~= "table" then db.profiles[M.DEFAULT] = {} end
  if type(db.ui) ~= "table" then
    db.ui = {}
    for k in pairs(M.ACCOUNT) do
      if old and old[k] ~= nil then db.ui[k] = old[k] end
    end
  end
  if type(char.profile) ~= "string" or type(db.profiles[char.profile]) ~= "table" then char.profile = M.DEFAULT end
  if type(char.auto) ~= "table" then char.auto = {} end
  -- a profile deleted on another character: this one's rules for it go too
  for rule, name in pairs(char.auto) do
    if type(db.profiles[name]) ~= "table" then char.auto[rule] = nil end
  end
  if char.point == nil and type(db.point) == "table" then char.point = copy(db.point) end
  if char.hidden == nil then char.hidden = db.hidden == true end
  return db, char
end

function M.names(db)
  local list = {}
  for name in pairs(db.profiles) do
    if name ~= M.DEFAULT then list[#list + 1] = name end
  end
  table.sort(list)
  table.insert(list, 1, M.DEFAULT)
  return list
end

-- where: IsInInstance()'s second value ("none", "pvp", "arena", "party", "raid"); level: the player's
function M.pick(db, char, where, level)
  local auto = char.auto or {}
  local rule = WHERE[where or "none"]
  if rule and auto[rule] and db.profiles[auto[rule]] then return auto[rule], rule end
  if (level or M.MAX_LEVEL) < M.MAX_LEVEL and auto.leveling and db.profiles[auto.leveling] then
    return auto.leveling, "leveling"
  end
  -- migrate keeps char.profile valid, but a delete on another character may come after it
  if type(char.profile) ~= "string" or not db.profiles[char.profile] then return M.DEFAULT, "picked" end
  return char.profile, "picked"
end

-- what the engine and the window see: the profile's values, the account's for M.ACCOUNT keys,
-- each checked against its option
function M.view(options, db, name)
  local p, ui, c = db.profiles[name] or {}, db.ui or {}, {}
  for _, o in ipairs(options) do
    if M.ACCOUNT[o.key] then c[o.key] = ui[o.key] else c[o.key] = p[o.key] end
  end
  return settings.merge(options, c)
end

-- and back, each value to where it lives
function M.store(options, db, name, config)
  local p = db.profiles[name]
  if not p then return end
  db.ui = db.ui or {}
  for _, o in ipairs(options) do
    if M.ACCOUNT[o.key] then db.ui[o.key] = config[o.key] else p[o.key] = config[o.key] end
  end
end

local function clean(name)
  if type(name) ~= "string" then return nil end
  name = name:match("^%s*(.-)%s*$")
  if name == "" or #name > M.NAME_MAX then return nil end
  return name
end

-- from: the values to copy (the current profile's), or nil for the defaults
function M.create(db, name, from)
  local n = clean(name)
  if not n then return nil, ("a name of 1 to %d letters"):format(M.NAME_MAX) end
  if db.profiles[n] then return nil, n .. ": there is one already" end
  -- from may be the whole view: the account's keys live in db.ui, a copy of them would go stale
  local p = copy(from)
  for k in pairs(M.ACCOUNT) do p[k] = nil end
  db.profiles[n] = p
  return n
end

function M.delete(db, char, name)
  if name == M.DEFAULT then return nil, "Default stays" end
  if type(db.profiles[name]) ~= "table" then return nil, tostring(name) .. ": no such profile" end
  db.profiles[name] = nil
  if char.profile == name then char.profile = M.DEFAULT end
  for rule, n in pairs(char.auto or {}) do
    if n == name then char.auto[rule] = nil end
  end
  return true
end

function M.reset(db, name)
  if db.profiles[name] then db.profiles[name] = {} end
end

return M
