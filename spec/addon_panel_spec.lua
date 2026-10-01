local G = require("game_mock")
local P = require("panel_mock")
local panel = require("panel")
local settings = require("settings")

local OPTIONS = {
  { type = "range", key = "scale", name = "Scale", min = 0.5, max = 2, step = 0.05, default = 1 },
  { type = "select", key = "mode", name = "Mode", desc = "auto picks solo/group/raid by your group",
    values = { "auto", "solo", "group" }, default = 1 },
  { type = "toggle", key = "showReason", name = "Show reason under icon", default = true },
}

local function host()
  local h = { cfg = settings.defaults(OPTIONS), sets = {}, actions = {}, replaced = 0 }
  h.config = function() return h.cfg end
  h.set = function(k, v) h.cfg[k] = v; h.sets[#h.sets + 1] = { k, v } end
  h.replace = function(c) h.cfg = c; h.replaced = h.replaced + 1 end
  h.action = function(name) h.actions[#h.actions + 1] = name end
  h.label = function(name) return name == "lock" and "Unlock timeline" or name end
  return h
end

describe("settings window", function()
  before_each(function()
    G.install({})
    P.install()
  end)

  it("three pages in Interface - AddOns, every option on one of them", function()
    local f = panel.new({ options = OPTIONS }, host())
    assert.are.equal(3, #G.categories)
    assert.are.equal(f, G.categories[1])
    assert.are.equal(f, DoubtMyRotationPanel)
    assert.are.equal("DoubtMyRotation", f.name)
    assert.are.same({ "Combat", "DoubtMyRotation" }, { G.categories[2].name, G.categories[2].parent })
    assert.are.same({ "Advanced", "DoubtMyRotation" }, { G.categories[3].name, G.categories[3].parent })
    assert.are.equal(DoubtMyRotationPanelCombat, f.pages.combat)
    assert.are.equal(DoubtMyRotationPanelAdvanced, f.pages.advanced)
    assert.are.equal(f, f.pages.general)
    assert.are.equal("range", f.controls.scale.kind)
    assert.are.equal("select", f.controls.mode.kind)
    assert.are.equal("toggle", f.controls.showReason.kind)
    assert.are.equal(f, f.controls.scale:GetParent())
    assert.are.equal(f.pages.combat, f.controls.mode:GetParent())
  end)

  -- Interface Options shows a page itself; one left shown would sit in the middle of the screen
  it("the pages start hidden", function()
    local f = panel.new({ options = OPTIONS }, host())
    for _, page in pairs(f.pages) do assert.is_false(page:IsShown()) end
  end)

  it("every control is labelled with its option's name", function()
    local f = panel.new({ options = OPTIONS }, host())
    assert.are.equal("Show reason under icon", _G["DoubtMyRotationPanel_showReasonText"].text)
    assert.are.equal("Mode", f.controls.mode.label.text)
    assert.are.equal("auto picks solo/group/raid by your group", f.controls.mode.tooltipText)
  end)

  -- an option added to tools/aura.lua later and forgotten in SECTIONS must not vanish
  it("an option of no section goes to Advanced", function()
    local opts = { OPTIONS[1], { type = "toggle", key = "brandNew", name = "Brand new", default = false } }
    local f = panel.new({ options = opts }, host())
    assert.are.equal(f.pages.advanced, f.controls.brandNew:GetParent())
  end)

  -- updateCheck is the addon's own option (the update checker), not one of the aura's
  it("the real options all have a section", function()
    local aura = require("aura")
    local placed, where = {}, {}
    for _, sec in ipairs(panel.SECTIONS) do
      for _, k in ipairs(sec.options) do placed[k], where[k] = true, sec.key end
    end
    for _, o in ipairs(aura.OPTIONS) do
      if o.key ~= "export" then assert.is_true(placed[o.key], o.key) end
    end
    assert.are.equal("advanced", where.updateCheck)
    assert.is_nil(placed.export)
    -- the helpers' options (addon/helpers.lua) too
    for _, o in ipairs(require("helpers").options()) do assert.is_true(placed[o.key], o.key) end
    for _, k in ipairs({ "highlightButtons", "showKeybind", "hoverTips" }) do assert.are.equal("general", where[k], k) end
    for _, k in ipairs({ "readyCheck", "rankWarning" }) do assert.are.equal("advanced", where[k], k) end
  end)

  it("a section key with no such option is skipped", function()
    local f = panel.new({ options = OPTIONS }, host())
    assert.is_nil(f.controls.updateCheck)
    f.refresh(f)
  end)

  it("refresh shows the current values", function()
    local h = host()
    h.cfg.scale, h.cfg.mode, h.cfg.showReason = 1.5, 2, false
    local f = panel.new({ options = OPTIONS }, h)
    f.refresh(f)
    assert.are.equal(1.5, f.controls.scale:GetValue())
    assert.are.equal("Scale: 1.5", _G["DoubtMyRotationPanel_scaleText"].text)
    assert.are.equal(2, f.controls.mode.selected)
    assert.are.equal("solo", f.controls.mode.ddText)
    assert.is_nil(f.controls.showReason:GetChecked())
  end)

  it("a slider sets its value snapped to the step", function()
    local h = host()
    local f = panel.new({ options = OPTIONS }, h)
    f.refresh(f)
    f.controls.scale:SetValue(1.2690001)
    assert.are.same({ "scale", 1.25 }, h.sets[#h.sets])
  end)

  it("refresh itself sets nothing", function()
    local h = host()
    local f = panel.new({ options = OPTIONS }, h)
    f.refresh(f)
    f.pages.combat.refresh(f.pages.combat)
    assert.are.equal(0, #h.sets)
    assert.is_false(h.quiet())
  end)

  it("a dropdown lists the values and picking one sets it", function()
    local h = host()
    local f = panel.new({ options = OPTIONS }, h)
    local items = G.menu(f.controls.mode)
    assert.are.same({ "auto", "solo", "group" }, { items[1].text, items[2].text, items[3].text })
    assert.is_true(items[1].checked)
    assert.is_false(items[3].checked)
    items[3].func(items[3])
    assert.are.same({ "mode", 3 }, h.sets[#h.sets])
    assert.are.equal("group", f.controls.mode.ddText)
  end)

  it("a check box sets on and off", function()
    local h = host()
    local f = panel.new({ options = OPTIONS }, h)
    f.refresh(f)
    f.controls.showReason:SetChecked(false)
    f.controls.showReason:Click()
    assert.are.same({ "showReason", false }, h.sets[#h.sets])
    f.controls.showReason:SetChecked(true)
    f.controls.showReason:Click()
    assert.are.same({ "showReason", true }, h.sets[#h.sets])
  end)

  -- Interface Options: Okay keeps, Cancel restores what was there when the page was opened;
  -- the client calls refresh / okay / cancel on every page, so the three share one state
  it("cancel puts back the settings from when the page was opened", function()
    local h = host()
    local f = panel.new({ options = OPTIONS }, h)
    for _, page in ipairs(G.categories) do page.refresh(page) end
    f.controls.scale:SetValue(2)
    f.controls.showReason:SetChecked(false)
    f.controls.showReason:Click()
    for _, page in ipairs(G.categories) do page.cancel(page) end
    assert.are.same(settings.defaults(OPTIONS), h.cfg)
    assert.are.equal(1, h.replaced)
  end)

  -- InterfaceOptionsFrame is a UIPanelWindow: another center window hides it without Okay or Cancel
  it("a window closed without Okay or Cancel starts afresh on the next open", function()
    local h = host()
    local f = panel.new({ options = OPTIONS }, h)
    InterfaceOptionsFrame:Show()
    f.refresh(f)
    f.controls.scale:SetValue(2)
    InterfaceOptionsFrame:Hide()
    InterfaceOptionsFrame:Show()
    f.refresh(f)
    f.controls.scale:SetValue(1.5)
    f.cancel(f)
    assert.are.equal(2, h.cfg.scale)
  end)

  it("a drop-down shows its description on hover, on the list and on its arrow", function()
    local f = panel.new({ options = OPTIONS }, host())
    local d = f.controls.mode
    for _, target in ipairs({ d, _G[d:GetName() .. "Button"] }) do
      target.scripts.OnEnter(target)
      assert.are.equal("auto picks solo/group/raid by your group", G.tooltip.text)
      assert.is_true(G.tooltip.shown)
      target.scripts.OnLeave(target)
      assert.is_false(G.tooltip.shown)
    end
  end)

  it("okay keeps the changes, a later cancel does not undo them", function()
    local h = host()
    local f = panel.new({ options = OPTIONS }, h)
    f.refresh(f)
    f.controls.scale:SetValue(2)
    for _, page in ipairs(G.categories) do page.okay(page) end
    f.refresh(f)
    f.cancel(f)
    assert.are.equal(2, h.cfg.scale)
  end)

  it("defaults puts the defaults in", function()
    local h = host()
    h.cfg.scale = 2
    local f = panel.new({ options = OPTIONS }, h)
    f.default(f)
    assert.are.same(settings.defaults(OPTIONS), h.cfg)
  end)

  -- "Defaults - These settings" runs default on the shown page only
  it("defaults on one page leaves the other pages' settings alone", function()
    local h = host()
    h.cfg.scale, h.cfg.mode = 2, 3
    local f = panel.new({ options = OPTIONS }, h)
    f.pages.combat.default(f.pages.combat)
    assert.are.same({ 2, 1 }, { h.cfg.scale, h.cfg.mode })
  end)

  it("the action buttons call the host and show its label", function()
    local h = host()
    local f = panel.new({ options = OPTIONS }, h)
    f.refresh(f)
    assert.are.equal("Unlock timeline", f.buttons.lock.text)
    for _, name in ipairs({ "lock", "export", "hide" }) do f.buttons[name]:Click() end
    assert.are.same({ "lock", "export", "hide" }, h.actions)
    assert.are.equal(f, f.buttons.lock:GetParent())
  end)
end)
