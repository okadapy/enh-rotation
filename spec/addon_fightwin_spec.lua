local G = require("game_mock")
local P = require("panel_mock")
local fightwin = require("fightwin")
local history = require("history")

local function entry(over)
  local f = { name = "Marrowgar", key = "Marrowgar 25 Player", seconds = 95, rate = 0.87, delay = 0.21, lost = 3100,
              stale = 1, late = 2, unrated = 3, mw = { wasted = 4, idle = 6.2 }, gcdIdle = 3.4, swings = 5,
              fs = { seen = 90, up = 81 }, prep = { shield = 12, totems = 0, enchants = 0, autoAttack = 2 } }
  for k, v in pairs(over or {}) do f[k] = v end
  return { fight = f, trend = "better",
           tips = { { code = "mw_wasted", text = "4 Maelstrom stacks wasted - cast at 5 right away", detail = "A stack that comes at 5 is lost" } } }
end

describe("addon fight window", function()
  before_each(function() G.install(); P.install() end)

  it("a list line: name, time, share", function()
    assert.are.equal("Marrowgar 1:35 87%", fightwin.listLine(entry()))
  end)

  it("the detail of a fight", function()
    assert.are.equal(table.concat({
      "Marrowgar 25 Player  1:35  87% matched  ~0.21s delay  ~3.1k lost  (better than before)",
      "",
      "- 4 Maelstrom stacks wasted - cast at 5 right away",
      "|cff999999  A stack that comes at 5 is lost|r",
      "",
      "Maelstrom: 4 stacks wasted, 6s on 5 stacks",
      "GCD idle 3s, swings delayed by casts 5",
      "Flame Shock uptime 90%",
      "Without: shield 12s, fire totem 0s, enchants 0s, auto-attack 2s",
      "Not rated 3, stale plan 1, late 2",
    }, "\n"), fightwin.detail(entry()))
  end)

  it("no Flame Shock line when there was none to keep", function()
    assert.is_nil(fightwin.detail(entry({ fs = { seen = 0, up = 0 } })):find("Flame Shock"))
  end)

  it("the boss history: one line per fight", function()
    local list = { { date = 5, seconds = 95, rate = 0.87, lostPerSec = 32.6, tips = { "mw_wasted", "delay" } } }
    local date = function(fmt, t) return "d" .. t end
    assert.are.equal("Boss history: Marrowgar 25 Player\nd5  1:35  87%  ~33/s lost  mw_wasted, delay",
      fightwin.historyText("Marrowgar 25 Player", list, date))
  end)

  it("opens on the newest fight, selects another, shows the boss history", function()
    local H = history.new({}, function() return 7 end)
    H:add(entry({ name = "Old" }).fight, entry().tips)
    H:add(entry().fight, entry().tips)
    local W = fightwin.new({ history = H, date = function(_, t) return "d" .. t end })
    W:open("last")
    assert.is_true(W.frame:IsShown())
    assert.are.equal("Marrowgar 1:35 87%", W.rows[1].label:GetText())
    assert.is_truthy(W.text:GetText():find("^Marrowgar 25 Player"))
    W.rows[2]:Click()
    assert.are.equal(2, W.selected)
    W.historyButton:Click()
    assert.is_truthy(W.text:GetText():find("^Boss history: Marrowgar 25 Player"))
    W:hide()
    assert.is_false(W.frame:IsShown())
  end)

  it("registers for Esc", function()
    fightwin.new({ history = history.new({}, function() return 7 end), date = function() return "" end })
    local found
    for _, n in ipairs(UISpecialFrames) do if n == "DoubtMyRotationFightWindow" then found = true end end
    assert.is_true(found)
  end)

  it("boss history with an empty session shows the latest saved boss", function()
    local db = { fights = {
      ["Old 10 Player"] = { last = 1, list = { { date = 1, seconds = 30, tips = {} } } },
      ["New 25 Player"] = { last = 9, list = { { date = 9, seconds = 40, tips = {} } } } } }
    local W = fightwin.new({ history = history.new(db, function() return 7 end), date = function(_, t) return "d" .. t end })
    W:open("history")
    assert.is_truthy(W.text:GetText():find("^Boss history: New 25 Player\nd9"))
    W:open("last")
    assert.are.equal(fightwin.EMPTY, W.text:GetText())
  end)

  it("opens with no fights yet and says so", function()
    local W = fightwin.new({ history = history.new({}, function() return 7 end), date = function() return "" end })
    W:open("last")
    assert.are.equal("No fight reviewed yet - fight something for 20s or more", W.text:GetText())
  end)
end)
