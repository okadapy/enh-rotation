local G = require("game_mock")
local B = require("bars_mock")
local spells = require("spells")
local actionbars = require("actionbars")

local function top(key) local r = spells.byKey[key].ranks; return r[#r] end
local NAMES = { ["Stormstrike"] = "stormstrike", ["Lava Lash"] = "lavaLash", ["Lightning Bolt"] = "lightningBolt" }

local function install(cfg)
  G.install({})
  B.install(cfg)
end

describe("action bar buttons", function()
  it("a standard bar button with a spell gives the spell's key and the button's key", function()
    install({ actions = { [3] = { "spell", 40, "spell", top("lightningBolt") } },
              bindings = { ACTIONBUTTON3 = "3" } })
    local b = B.blizzard("ActionButton3", 3)
    local map = actionbars.scan(NAMES)
    assert.are.equal(b, map.lightningBolt.buttons[1].frame)
    assert.are.equal("3", map.lightningBolt.hotkey)
  end)

  it("the bars ElvUI hides are skipped; its own buttons count, with ElvUI's binding target", function()
    install({ actions = { [1] = { "spell", 12, "spell", top("stormstrike") } },
              bindings = { ACTIONBUTTON1 = "SHIFT-E" } })
    B.blizzard("ActionButton1", 1, false)
    local e = B.elvui(1, 1, "action", 1, "ACTIONBUTTON1")
    local map = actionbars.scan(NAMES)
    assert.are.equal(1, #map.stormstrike.buttons)
    assert.are.equal(e, map.stormstrike.buttons[1].frame)
    assert.are.equal("S-E", map.stormstrike.hotkey)
  end)

  it("an ElvUI button with no key on its target takes its click binding", function()
    install({ actions = { [16] = { "spell", 9, "spell", top("lavaLash") } },
              bindings = { ["CLICK ElvUI_Bar2Button4:LeftButton"] = "CTRL-2" } })
    B.elvui(2, 4, "action", 16, "MULTIACTIONBAR2BUTTON4")
    assert.are.equal("C-2", actionbars.scan(NAMES).lavaLash.hotkey)
  end)

  it("LibActionButton spell and macro states are read too", function()
    install({ macros = { [2] = "Lava Lash" } })
    B.elvui(1, 5, "spell", top("stormstrike"))
    B.elvui(1, 6, "macro", 2)
    local map = actionbars.scan(NAMES)
    assert.is_truthy(map.stormstrike)
    assert.is_truthy(map.lavaLash)
  end)

  it("a macro on a slot counts as the spell it casts", function()
    install({ actions = { [5] = { "macro", 2 } }, macros = { [2] = "Lava Lash" } })
    B.blizzard("ActionButton5", 5)
    assert.is_truthy(actionbars.scan(NAMES).lavaLash)
  end)

  it("a spell slot without a spell id is read from the spellbook", function()
    install({ actions = { [7] = { "spell", 12, "spell" } }, book = { [12] = "Stormstrike" } })
    B.blizzard("ActionButton7", 7)
    assert.is_truthy(actionbars.scan(NAMES).stormstrike)
  end)

  it("items, empty slots and spells of no key are left out", function()
    install({ actions = { [1] = { "item", 33447 }, [2] = { "spell", 3, "spell", 6603 } } })
    B.blizzard("ActionButton1", 1)
    B.blizzard("ActionButton2", 2)
    B.blizzard("ActionButton4", 4)
    assert.are.same({}, actionbars.scan(NAMES))
  end)

  it("the same spell on two bars: both buttons, the first bound key", function()
    install({ actions = { [3] = { "spell", 40, "spell", top("lightningBolt") }, [27] = { "spell", 40, "spell", top("lightningBolt") } },
              bindings = { MULTIACTIONBAR2BUTTON3 = "F" } })
    B.blizzard("ActionButton3", 3)
    B.blizzard("MultiBarBottomRightButton3", 27)
    local m = actionbars.scan(NAMES).lightningBolt
    assert.are.equal(2, #m.buttons)
    assert.are.equal("F", m.hotkey)
  end)

  it("no bars and no LibStub: an empty map, no error", function()
    install({})
    _G.LibStub = nil
    assert.are.same({}, actionbars.scan(NAMES))
  end)

  it("another source is one more entry (Bartender, Dominos later)", function()
    install({})
    local f = CreateFrame("CheckButton", "OtherBarButton1", UIParent)
    local src = { name = "other", buttons = function(out) out[#out + 1] = { frame = f, name = "OtherBarButton1", spell = "Stormstrike", binding = "ALT-Q" } end }
    assert.are.equal("A-Q", actionbars.scan(NAMES, { src }).stormstrike.hotkey)
  end)

  it("short key names", function()
    local cases = { ["SHIFT-E"] = "S-E", ["CTRL-ALT-3"] = "C-A-3", BUTTON4 = "M4", ["SHIFT-BUTTON3"] = "S-M3",
                    MOUSEWHEELUP = "MwU", MOUSEWHEELDOWN = "MwD", NUMPAD1 = "N1", SPACE = "Spc", F = "F" }
    for long, short in pairs(cases) do assert.are.equal(short, actionbars.short(long), long) end
    assert.is_nil(actionbars.short(nil))
    assert.is_nil(actionbars.short(""))
  end)
end)
