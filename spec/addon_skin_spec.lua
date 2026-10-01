local G = require("game_mock")
local X = require("elvui_mock")
local skin = require("skin")

local function widget(kind, objectType, parent)
  local w = CreateFrame(objectType or "Frame", nil, parent or UIParent)
  w.kind = kind
  return w
end

-- a window as the addon's modules make them: kind and widgets
local function window()
  local f = widget("window")
  f.widgets = { widget("range", "Slider"), widget("toggle", "CheckButton"), widget("select"), widget("button", "Button"),
                widget("edit", "EditBox") }
  return f
end

local function names(S)
  local out = {}
  for i, c in ipairs(S.calls) do out[i] = c[1] end
  return out
end

local function closeOf(w)
  for _, c in ipairs({ w:GetChildren() }) do
    if c.template == "UIPanelCloseButton" then return c end
  end
end

describe("ElvUI style", function()
  local said, on
  local function new() return skin.new({ enabled = function() return on end, say = function(l) said[#said + 1] = l end }) end
  before_each(function()
    G.install({})
    X.remove()
    said, on = {}, true
  end)

  it("names its one S:AddCallback", function()
    assert.are.equal("DoubtMyRotation", skin.CALLBACK)
    for _, kind in ipairs({ "range", "toggle", "select", "button", "edit", "close", "scroll", "window", "minimap",
                            "timeline" }) do
      assert.are.equal("function", type(skin.HANDLE[kind]))
    end
  end)

  it("without ElvUI nothing is touched", function()
    local f = window()
    local sk = new()
    sk:frame(f)
    sk:refresh()
    assert.is_nil(f.elvTemplate)
    for _, w in ipairs(f.widgets) do assert.is_nil(w.elv) end
    assert.are.equal(0, #said)
  end)

  it("an ElvUI without a Skins module: nothing, no Lua error", function()
    X.install()
    X.E.modules.Skins = nil
    local f = window()
    assert.has_no.errors(function() new():frame(f) end)
    assert.is_nil(f.widgets[1].elv)
    assert.are.equal(0, #said)
  end)

  -- ElvUI loaded first (OptionalDeps): its Skins module is up by our PLAYER_LOGIN
  it("ElvUI up: each widget gets its ElvUI function at once, a frame only once", function()
    local S = X.install()
    local f = window()
    local sk = new()
    sk:frame(f)
    sk:frame(f)
    sk:refresh()
    assert.are.same({ "HandleSliderFrame", "HandleCheckBox", "HandleDropDownBox", "HandleButton", "HandleEditBox" }, names(S))
    assert.are.equal(180, S.calls[3][3])
    assert.are.equal("Transparent", f.elvTemplate)
    assert.are.equal(0, S.added)
  end)

  it("a list keeps its own width", function()
    local S = X.install()
    local f = widget("window")
    local d = widget("select")
    d.skinWidth = 220
    f.widgets = { d }
    new():frame(f)
    assert.are.equal(220, S.calls[1][3])
  end)

  -- ElvUI loaded after us: Skins initializes later, its callbacks fire then (and only then)
  it("ElvUI not up yet: everything waits for one callback", function()
    local S = X.install({ initialized = false })
    local a, b = window(), window()
    local sk = new()
    sk:frame(a)
    sk:frame(b)
    sk:refresh()
    assert.are.same({}, S.calls)
    assert.are.equal(1, S.added)
    X.initialize()
    assert.are.equal(10, #S.calls)
    assert.are.equal("Transparent", a.elvTemplate)
    assert.are.equal("Transparent", b.elvTemplate)
    -- a window made after ElvUI came up: at once
    local c = window()
    sk:frame(c)
    assert.are.equal(15, #S.calls)
    assert.are.equal(1, S.added)
  end)

  it("the option off: nothing; turned on: all known frames at once", function()
    local S = X.install()
    on = false
    local sk = new()
    local f = window()
    sk:frame(f)
    assert.are.same({}, S.calls)
    assert.is_nil(f.elvTemplate)
    on = true
    sk:refresh()
    assert.are.equal(5, #S.calls)
    assert.are.equal("Transparent", f.elvTemplate)
  end)

  it("the option off while ElvUI is not up: no callback is even asked for", function()
    local S = X.install({ initialized = false })
    on = false
    new():frame(window())
    assert.are.equal(0, S.added)
  end)

  it("a broken ElvUI function: one line, no Lua error, the standard look for the rest", function()
    local S = X.install({ fail = "HandleCheckBox" })
    local sk = new()
    assert.has_no.errors(function()
      sk:frame(window())
      sk:frame(window())
      sk:refresh()
    end)
    assert.are.equal(1, #said)
    assert.truthy(said[1]:find("ElvUI style failed, the standard look stays", 1, true))
    assert.are.same({ "HandleSliderFrame" }, names(S))
  end)

  it("a broken callback registration: one line, no Lua error", function()
    local S = X.install({ initialized = false })
    S.AddCallback = function() error("ElvUI: AddCallback broke") end
    local sk = new()
    assert.has_no.errors(function()
      sk:frame(window())
      sk:frame(window())
    end)
    assert.are.equal(1, #said)
  end)

  -- options pages: Interface Options frames them already, so only their own controls are styled
  it("a page without kind or widgets: the controls it holds, found by their kind", function()
    local S = X.install()
    local page = CreateFrame("Frame", "DoubtMyRotationPanel", UIParent)
    widget("range", "Slider", page)
    widget("toggle", "CheckButton", page)
    CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    new():frame(page)
    assert.are.same({ "HandleSliderFrame", "HandleCheckBox" }, names(S))
    assert.is_nil(page.elvTemplate)
  end)

  it("the export window: the engine's frame, its buttons and scroll bar found by kind", function()
    local S = X.install()
    local w = require("timeline").exportWindow("text", function() return "text" end)
    _G.EnhRotExportScrollScrollBar = CreateFrame("Slider", "EnhRotExportScrollScrollBar")
    local sk = new()
    sk:export(w)
    sk:export(w)
    assert.are.equal("Transparent", w.elvTemplate)
    assert.are.equal("HandleButton", w.again.elv)
    assert.are.equal("HandleCloseButton", closeOf(w).elv)
    assert.are.equal("HandleScrollBar", EnhRotExportScrollScrollBar.elv)
    assert.are.equal(3, #S.calls)
  end)

  it("the ready-to-fight window: the frame and its close button", function()
    local S = X.install()
    local w = require("ready").window({ { key = "a", ok = true, label = "Lightning Shield" } })
    local sk = new()
    sk:ready(w)
    sk:ready(w)
    assert.are.equal("Transparent", w.elvTemplate)
    assert.are.equal("HandleCloseButton", closeOf(w).elv)
    assert.are.same({ "HandleCloseButton" }, names(S))
  end)

  -- core keeps calling frame.bg:Show() / Hide() on lock and unlock
  it("the timeline's backdrop while unlocked becomes ElvUI's panel, shown as it was", function()
    X.install()
    local f = CreateFrame("Frame", "DoubtMyRotationFrame", UIParent)
    f.kind = "timeline"
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:Hide()
    local plain = f.bg
    f:SetFrameLevel(5)
    new():frame(f)
    assert.are_not.equal(plain, f.bg)
    assert.are.equal("Transparent", f.bg.elvTemplate)
    assert.is_false(f.bg:IsShown())
    assert.is_false(plain:IsShown())
    -- below the timeline, as ElvUI's own backdrops: its icons are the timeline's textures
    assert.are.equal(4, f.bg:GetFrameLevel())
    f.bg:Show()
    assert.is_true(f.bg:IsShown())
  end)

  it("the timeline unlocked: the new backdrop shows, the plain one hides", function()
    X.install()
    local f = CreateFrame("Frame", nil, UIParent)
    f.kind = "timeline"
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    local plain = f.bg
    new():frame(f)
    assert.is_true(f.bg:IsShown())
    assert.is_false(plain:IsShown())
  end)

  it("a broken SetTemplate leaves the plain backdrop in place", function()
    X.install({ fail = "SetTemplate" })
    local f = CreateFrame("Frame", nil, UIParent)
    f.kind = "timeline"
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    local plain = f.bg
    assert.has_no.errors(function() new():frame(f) end)
    assert.are.equal(plain, f.bg)
    assert.is_true(plain:IsShown())
    assert.are.equal(1, #said)
  end)

  it("the minimap button: its round border goes, ElvUI's square frame instead", function()
    X.install()
    local b = CreateFrame("Button", nil, UIParent)
    b.kind = "minimap"
    b.icon, b.border = b:CreateTexture(), b:CreateTexture()
    new():frame(b)
    assert.is_false(b.border:IsShown())
    assert.are.equal("Default", b.elvTemplate)
    assert.are.same({ 0.08, 0.92, 0.08, 0.92 }, b.icon.coords)
    assert.are.equal(2, #b.icon.points)
  end)
end)
