local update = require("update")

-- a checker over fake deps: a clock, the guild and group state, and what it sent and said
local function rig(version, over)
  local w = { t = 100, guild = true, partyN = 0, raidN = 0, on = true, sent = {}, said = {}, db = {} }
  local deps = {
    db = w.db,
    send = function(prefix, text, distribution) w.sent[#w.sent + 1] = { prefix, text, distribution } end,
    say = function(line) w.said[#w.said + 1] = line end,
    enabled = function() return w.on end,
    now = function() return w.t end,
    inGuild = function() return w.guild end,
    party = function() return w.partyN end,
    raid = function() return w.raidN end,
    me = function() return "Thrall" end,
  }
  for k, v in pairs(over or {}) do deps[k] = v end
  w.c = update.new(version, deps)
  return w
end

local function hear(w, text, sender, prefix)
  w.c:onEvent("CHAT_MSG_ADDON", prefix or update.PREFIX, text, "GUILD", sender or "Jaina")
end

local NEWER = "a newer version is out: v1.1.0 (you have v1.0.6) - github.com/okadapy/enh-rotation/releases"

describe("addon update check", function()
  it("exports the prefix, the url, the throttle and the option", function()
    assert.are.equal("DoubtMyRotation", update.PREFIX)
    assert.are.equal("github.com/okadapy/enh-rotation/releases", update.URL)
    assert.are.equal(60, update.THROTTLE)
    assert.are.same({ type = "toggle", key = "updateCheck", name = "Tell me when a newer version is out", default = true },
      update.OPTION)
  end)

  it("parse reads v1.2.3 and 1.2.3", function()
    assert.are.same({ 1, 2, 3 }, update.parse("v1.2.3"))
    assert.are.same({ 1, 10, 0 }, update.parse("1.10.0"))
  end)

  it("parse gives nil for dev, two parts and junk", function()
    assert.is_nil(update.parse("dev"))
    assert.is_nil(update.parse("v1.2"))
    assert.is_nil(update.parse("v1.2.3.4"))
    assert.is_nil(update.parse("abc"))
    assert.is_nil(update.parse(""))
    assert.is_nil(update.parse(nil))
    assert.is_nil(update.parse(12))
  end)

  it("newer compares numbers, not text", function()
    assert.is_true(update.newer("1.10.0", "1.9.9"))
    assert.is_true(update.newer("v2.0.0", "v1.99.99"))
    assert.is_true(update.newer("v1.0.7", "1.0.6"))
    assert.is_false(update.newer("1.9.9", "1.10.0"))
    assert.is_false(update.newer("v1.0.6", "1.0.6"))
  end)

  it("newer is false when either side does not parse", function()
    assert.is_false(update.newer("dev", "v1.0.0"))
    assert.is_false(update.newer("v1.0.0", "dev"))
    assert.is_false(update.newer("V:abc", nil))
  end)

  it("start registers the events on the frame and routes them to onEvent", function()
    local events, script = {}, nil
    local frame = {
      RegisterEvent = function(_, e) events[#events + 1] = e end,
      SetScript = function(_, name, f) if name == "OnEvent" then script = f end end,
    }
    local w = rig("v1.0.6")
    w.c:start(frame)
    table.sort(events)
    assert.are.same({ "CHAT_MSG_ADDON", "PARTY_MEMBERS_CHANGED", "PLAYER_ENTERING_WORLD", "RAID_ROSTER_UPDATE" }, events)
    script(frame, "CHAT_MSG_ADDON", update.PREFIX, "V:v1.1.0", "GUILD", "Jaina")
    assert.are.same({ NEWER }, w.said)
  end)

  it("entering the world tells the guild our version", function()
    local w = rig("v1.0.6")
    w.c:onEvent("PLAYER_ENTERING_WORLD")
    assert.are.same({ { "DoubtMyRotation", "V:v1.0.6", "GUILD" } }, w.sent)
  end)

  it("no guild - nothing to the guild", function()
    local w = rig("v1.0.6")
    w.guild = false
    w.c:onEvent("PLAYER_ENTERING_WORLD")
    assert.are.same({}, w.sent)
  end)

  it("a party tells the party, a raid tells the raid and not the party", function()
    local w = rig("v1.0.6")
    w.c:onEvent("PARTY_MEMBERS_CHANGED")
    assert.are.same({}, w.sent)
    w.partyN = 2
    w.c:onEvent("PARTY_MEMBERS_CHANGED")
    assert.are.same({ { "DoubtMyRotation", "V:v1.0.6", "PARTY" } }, w.sent)
    w.raidN, w.partyN = 10, 4
    w.c:onEvent("RAID_ROSTER_UPDATE")
    assert.are.same({ "DoubtMyRotation", "V:v1.0.6", "RAID" }, w.sent[2])
    assert.are.equal(2, #w.sent)
  end)

  it("sends to one channel at most once per THROTTLE seconds, channels apart", function()
    local w = rig("v1.0.6")
    w.raidN = 10
    w.c:onEvent("PLAYER_ENTERING_WORLD")
    w.c:onEvent("RAID_ROSTER_UPDATE")
    w.t = w.t + 30
    w.c:onEvent("PLAYER_ENTERING_WORLD")
    w.c:onEvent("RAID_ROSTER_UPDATE")
    w.c:onEvent("PARTY_MEMBERS_CHANGED")
    assert.are.equal(2, #w.sent)
    w.t = w.t + 30
    w.c:onEvent("RAID_ROSTER_UPDATE")
    w.c:onEvent("PLAYER_ENTERING_WORLD")
    assert.are.same({ "GUILD", "RAID", "RAID", "GUILD" },
      { w.sent[1][3], w.sent[2][3], w.sent[3][3], w.sent[4][3] })
  end)

  it("a newer version heard: remembered and told once", function()
    local w = rig("v1.0.6")
    hear(w, "V:v1.1.0")
    assert.are.equal("v1.1.0", w.db.newest)
    assert.are.same({ NEWER }, w.said)
  end)

  it("the same or an older version heard: silence", function()
    local w = rig("v1.0.6")
    hear(w, "V:v1.0.6")
    hear(w, "V:1.0.5")
    assert.is_nil(w.db.newest)
    assert.are.same({}, w.said)
  end)

  it("several newer versions: one message with the newest at that moment, then silence", function()
    local w = rig("v1.0.6")
    hear(w, "V:v1.1.0")
    hear(w, "V:v1.2.0", "Uther")
    hear(w, "V:v1.1.5", "Arthas")
    w.c:onEvent("PLAYER_ENTERING_WORLD")
    assert.are.same({ NEWER }, w.said)
    assert.are.equal("v1.2.0", w.db.newest)
  end)

  it("after a relog the remembered newer version is told on entering the world", function()
    local w = rig("v1.0.6")
    w.db.newest = "v1.1.0"
    w.c:onEvent("PLAYER_ENTERING_WORLD")
    assert.are.same({ NEWER }, w.said)
    w.c:onEvent("PLAYER_ENTERING_WORLD")
    hear(w, "V:v1.3.0")
    assert.are.equal(1, #w.said)
  end)

  it("once we caught up the remembered version is dropped", function()
    local w = rig("v1.1.0")
    w.db.newest = "v1.1.0"
    w.c:onEvent("PLAYER_ENTERING_WORLD")
    assert.is_nil(w.db.newest)
    assert.are.same({}, w.said)
    w = rig("v1.2.0")
    w.db.newest = "v1.1.0"
    w.c:onEvent("PLAYER_ENTERING_WORLD")
    assert.is_nil(w.db.newest)
  end)

  it("a dev or unparsable own version sends and tells nothing", function()
    for _, v in ipairs({ "dev", "v1.2", "abc" }) do
      local w = rig(v)
      w.raidN = 10
      w.db.newest = "v9.0.0"
      w.c:onEvent("PLAYER_ENTERING_WORLD")
      w.c:onEvent("RAID_ROSTER_UPDATE")
      hear(w, "V:v9.9.9")
      assert.are.same({}, w.sent)
      assert.are.same({}, w.said)
    end
  end)

  it("the option off sends and tells nothing", function()
    local w = rig("v1.0.6")
    w.on = false
    w.raidN = 10
    w.db.newest = "v1.1.0"
    w.c:onEvent("PLAYER_ENTERING_WORLD")
    w.c:onEvent("RAID_ROSTER_UPDATE")
    hear(w, "V:v1.2.0")
    assert.are.same({}, w.sent)
    assert.are.same({}, w.said)
  end)

  it("our own message is ignored", function()
    local w = rig("v1.0.6")
    hear(w, "V:v1.1.0", "Thrall")
    hear(w, "V:v1.1.0", "Thrall-Whitemane")
    assert.is_nil(w.db.newest)
    assert.are.same({}, w.said)
  end)

  it("other prefixes and malformed texts are ignored without errors", function()
    local w = rig("v1.0.6")
    hear(w, "V:v1.1.0", "Jaina", "BigWigs")
    hear(w, "V:abc")
    hear(w, "X:1.2.3")
    hear(w, "V:")
    hear(w, nil)
    w.c:onEvent("CHAT_MSG_ADDON")
    w.c:onEvent("SOMETHING_ELSE", 1, 2)
    assert.is_nil(w.db.newest)
    assert.are.same({}, w.said)
  end)
end)
