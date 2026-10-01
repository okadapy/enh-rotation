local G = require("game_mock")
local B = require("bars_mock")
local spells = require("spells")
local highlight = require("highlight")

local function top(key) local r = spells.byKey[key].ranks; return r[#r] end

local now, cfg, v, scans, map
local function setup(over)
  G.install({})
  B.install({})
  now, cfg, scans = 100, { highlightButtons = true, showKeybind = true }, 0
  local b1, b2 = B.blizzard("ActionButton3", 3), B.elvui(1, 2, "action", 2)
  map = { stormstrike = { buttons = { { frame = b1 }, { frame = b2 } }, hotkey = "S-E" },
          lavaLash = { buttons = { { frame = b1 } }, hotkey = "2" } }
  local tl = CreateFrame("Frame")
  v = { plan = { steps = { { key = "stormstrike", at = 0 } } }, at = 100, active = true,
        S = { target = { exists = true, enemy = true } }, cache = { keyByName = {} },
        frame = tl, icon = G.texture() }
  for k, x in pairs(over or {}) do v[k] = x end
  local h = highlight.new({ view = function() return v end, config = function() return cfg end,
                            now = function() return now end,
                            scan = function() scans = scans + 1; return map end })
  return h, b1, b2
end

-- the button mocks keep what B.blizzard / B.elvui gave them: nothing set on a protected frame
local function untouched(b)
  assert.are.same({}, b.points)
  assert.are.same({}, b.children)
  assert.is_nil(b.allPoints)
  assert.is_nil(b.scripts.OnUpdate)
  assert.are.same({}, b.hooks)
  assert.is_nil(b.parentSet)
end

describe("highlight: when", function()
  it("the first button, once due within 0.3 s, with an enemy targeted", function()
    local _ = setup()
    assert.are.equal("stormstrike", highlight.due(v, 100))
    v.plan.steps[1].at = 1.0
    assert.is_nil(highlight.due(v, 100))
    assert.are.equal("stormstrike", highlight.due(v, 100.75))
    v.S.target.enemy = false
    assert.is_nil(highlight.due(v, 100.75))
  end)

  it("waits and empty plans light nothing", function()
    setup()
    v.plan.steps[1].key = "wait"
    assert.is_nil(highlight.due(v, 100))
    v.plan.steps = {}
    assert.is_nil(highlight.due(v, 100))
  end)

  it("a step that is not a spell is skipped, as the timeline's big icon skips it", function()
    setup()
    v.plan.steps = { { key = "wait", at = 0 }, { key = "lavaLash", at = 0.2 } }
    assert.are.equal("lavaLash", highlight.due(v, 100))
  end)
end)

describe("highlight: on the bars", function()
  it("an overlay of our own over every button with the spell; the buttons are not touched", function()
    local h, b1, b2 = setup()
    B.cfg.lockdown = true -- the same in combat
    h:tick(0.016)
    for _, b in ipairs({ b1, b2 }) do
      local o = h.overlays[b]
      assert.is_true(o:IsShown())
      assert.are.same({ "CENTER", b, "CENTER", 0, 0 }, o.point)
      assert.are.equal(UIParent, o.parent)
      assert.is_true(o.level > b.level)
      assert.is_falsy(o.mouse)
      untouched(b)
    end
  end)

  it("the next button: the old overlays go out", function()
    local h, b1, b2 = setup()
    h:tick(0.016)
    v.plan.steps[1].key = "lavaLash"
    h:tick(0.016)
    assert.is_true(h.overlays[b1]:IsShown())
    assert.is_false(h.overlays[b2]:IsShown())
  end)

  it("one overlay per button for the session", function()
    local h, b1 = setup()
    for _ = 1, 5 do
      v.plan.steps[1].key = "lavaLash"; h:tick(0.016)
      v.plan.steps[1].key = "stormstrike"; h:tick(0.016)
    end
    local n = 0
    for _ in pairs(h.overlays) do n = n + 1 end
    assert.are.equal(2, n)
    assert.is_truthy(h.overlays[b1])
  end)

  it("option off, engine asleep, or nothing due: nothing lit", function()
    local h, b1 = setup()
    cfg.highlightButtons = false
    h:tick(0.016)
    assert.is_true(h.overlays[b1] == nil or not h.overlays[b1]:IsShown())
    cfg.highlightButtons = true
    v.active = false
    h:tick(0.016)
    assert.is_true(h.overlays[b1] == nil or not h.overlays[b1]:IsShown())
  end)

  it("bars are read on an event and once a second, not every frame", function()
    local h = setup()
    local f = CreateFrame("Frame")
    h:start(f)
    for _ = 1, 30 do f.scripts.OnUpdate(f, 0.016); now = now + 0.016 end
    assert.are.equal(1, scans)
    f.scripts.OnEvent(f, "ACTIONBAR_SLOT_CHANGED", 3)
    f.scripts.OnUpdate(f, 0.016)
    assert.are.equal(2, scans)
    now = now + 1.01
    f.scripts.OnUpdate(f, 0.016)
    assert.are.equal(3, scans)
    assert.is_true(f.events.UPDATE_BINDINGS)
  end)
end)

describe("highlight: the key on the big icon", function()
  it("the first button's key at the bottom of the big icon", function()
    local h = setup()
    v.plan.steps[1].at = 2 -- shown whatever the time to it
    h:tick(0.016)
    assert.are.equal("S-E", h.keyText.text)
    assert.is_true(h.keyText:IsShown())
    assert.are.equal(v.icon, h.keyText.point[2])
    assert.are.equal("S-E", h:hotkey("stormstrike"))
  end)

  it("no key, the icon hidden, or the option off: no text", function()
    local h = setup()
    h:tick(0.016)
    assert.is_true(h.keyText:IsShown())
    map.stormstrike.hotkey = nil
    h:tick(0.016)
    assert.is_false(h.keyText:IsShown())
    map.stormstrike.hotkey = "S-E"
    v.icon:Hide()
    h:tick(0.016)
    assert.is_false(h.keyText:IsShown())
    v.icon:Show()
    cfg.showKeybind = false
    h:tick(0.016)
    assert.is_false(h.keyText:IsShown())
  end)
end)

describe("highlight: a restarted engine", function()
  it("the key moves to the new big icon; the old text goes out", function()
    local h = setup()
    h:tick(0.016)
    local old = h.keyText
    v.frame, v.icon = CreateFrame("Frame"), G.texture()
    h:tick(0.016)
    assert.is_false(old:IsShown())
    assert.is_true(h.keyText:IsShown())
    assert.are.equal(v.icon, h.keyText.point[2])
  end)
end)

describe("highlight with the real bars #integration", function()
  it("an ElvUI button with Stormstrike lights up", function()
    G.install({})
    B.install({ actions = { [1] = { "spell", 12, "spell", top("stormstrike") } }, bindings = { ACTIONBUTTON1 = "E" } })
    local e = B.elvui(1, 1, "action", 1, "ACTIONBUTTON1")
    local view = { plan = { steps = { { key = "stormstrike", at = 0 } } }, at = 100, active = true,
                   S = { target = { exists = true, enemy = true } }, cache = { keyByName = { Stormstrike = "stormstrike" } },
                   frame = CreateFrame("Frame"), icon = G.texture() }
    local h = highlight.new({ view = function() return view end, config = function() return {} end, now = function() return 100 end })
    h:tick(0.016)
    assert.is_true(h.overlays[e]:IsShown())
    assert.are.equal("E", h.keyText.text)
  end)
end)
