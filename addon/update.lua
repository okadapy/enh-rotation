-- The update check: the 3.3.5a client has no internet, so players with the addon swap their
-- versions in hidden addon messages (as DBM / BigWigs do). Client calls come through deps.
local M = {}

M.PREFIX = "DoubtMyRotation"
M.URL = "github.com/okadapy/enh-rotation/releases"
M.THROTTLE = 60
M.OPTION = { type = "toggle", key = "updateCheck", name = "Tell me when a newer version is out", default = true }

local EVENTS = { "PLAYER_ENTERING_WORLD", "PARTY_MEMBERS_CHANGED", "RAID_ROSTER_UPDATE", "CHAT_MSG_ADDON" }

function M.parse(v)
  if type(v) ~= "string" then return nil end
  local a, b, c = v:match("^v?(%d+)%.(%d+)%.(%d+)$")
  if not a then return nil end
  return { tonumber(a), tonumber(b), tonumber(c) }
end

function M.newer(a, b)
  local x, y = M.parse(a), M.parse(b)
  if not x or not y then return false end
  for i = 1, 3 do
    if x[i] ~= y[i] then return x[i] > y[i] end
  end
  return false
end

local function shown(v)
  local p = M.parse(v)
  return ("v%d.%d.%d"):format(p[1], p[2], p[3])
end

local Checker = {}
Checker.__index = Checker

-- client defaults are looked up at call time: the module loads before the client is ready in tests
local function call(f, fallback, ...)
  if f then return f(...) end
  return fallback(...)
end

function M.new(version, deps)
  deps = deps or {}
  return setmetatable({ version = version, deps = deps, db = deps.db or {}, last = {}, told = false }, Checker)
end

-- a dev build or a disabled option takes no part at all: it neither announces nor listens
function Checker:active()
  if not M.parse(self.version) then return false end
  local enabled = self.deps.enabled
  return not enabled or enabled() ~= false
end

function Checker:now() return call(self.deps.now, GetTime) end

function Checker:send(distribution)
  local t, last = self:now(), self.last[distribution]
  if last and t - last < M.THROTTLE then return end
  self.last[distribution] = t
  call(self.deps.send, SendAddonMessage, M.PREFIX, "V:" .. self.version, distribution)
end

function Checker:tell()
  if self.told then return end
  self.told = true
  local line = ("a newer version is out: %s (you have %s) - %s"):format(shown(self.db.newest), shown(self.version), M.URL)
  call(self.deps.say, print, line)
end

function Checker:me()
  return call(self.deps.me, function() return UnitName("player") end)
end

function Checker:hear(prefix, message, sender)
  if prefix ~= M.PREFIX or type(message) ~= "string" or type(sender) ~= "string" then return end
  -- cross-realm senders come as Name-Realm
  local me = self:me()
  if sender == me or sender:match("^([^%-]+)") == me then return end
  local v = message:match("^V:(.+)$")
  if not M.newer(v, self.version) then return end
  if not self.db.newest or M.newer(v, self.db.newest) then self.db.newest = shown(v) end
  self:tell()
end

function Checker:onEvent(event, ...)
  if not self:active() then return end
  if event == "PLAYER_ENTERING_WORLD" then
    if self.db.newest then
      -- the player updated since the version was heard: nothing to remind of any more
      if M.newer(self.db.newest, self.version) then self:tell() else self.db.newest = nil end
    end
    if call(self.deps.inGuild, IsInGuild) then self:send("GUILD") end
  elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
    if (call(self.deps.raid, GetNumRaidMembers) or 0) > 0 then
      self:send("RAID")
    elseif (call(self.deps.party, GetNumPartyMembers) or 0) > 0 then
      self:send("PARTY")
    end
  elseif event == "CHAT_MSG_ADDON" then
    local prefix, message, _, sender = ...
    self:hear(prefix, message, sender)
  end
end

function Checker:start(frame)
  for _, e in ipairs(EVENTS) do frame:RegisterEvent(e) end
  frame:SetScript("OnEvent", function(_, event, ...) self:onEvent(event, ...) end)
end

return M
