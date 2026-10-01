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
    -- on Combat: General has no room left for them (see the page size test)
    for _, k in ipairs({ "highlightButtons", "showKeybind", "hoverTips" }) do assert.are.equal("combat", where[k], k) end
    for _, k in ipairs({ "readyCheck", "rankWarning" }) do assert.are.equal("advanced", where[k], k) end
    -- and the addon's own (settings.ADDON_OPTIONS)
    for _, o in ipairs(settings.ADDON_OPTIONS) do assert.is_true(placed[o.key], o.key) end
    for _, k in ipairs({ "compact", "minimap", "levelCards" }) do assert.are.equal("general", where[k], k) end
    assert.are.equal("advanced", where.elvui)
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

  it("the action buttons call the host and show its label, two in a row", function()
    local h = host()
    local f = panel.new({ options = OPTIONS }, h)
    f.refresh(f)
    assert.are.equal("Unlock timeline", f.buttons.lock.text)
    assert.are.equal("guide", f.buttons.guide.text)
    for _, name in ipairs({ "lock", "export", "hide", "guide" }) do
      f.buttons[name]:Click()
      assert.are.equal("button", f.buttons[name].kind)
    end
    assert.are.same({ "lock", "export", "hide", "guide" }, h.actions)
    assert.are.equal(f, f.buttons.lock:GetParent())
    assert.are.equal(2, panel.PER_ROW)
    -- the third starts the second row, under the first
    assert.are.equal(f.buttons.lock.point[4], f.buttons.hide.point[4])
    assert.is_true(f.buttons.hide.point[5] < f.buttons.lock.point[5])
    assert.are.equal(f.buttons.lock.point[5], f.buttons.export.point[5])
    assert.are.equal(f.buttons.hide.point[5], f.buttons.guide.point[5])
    assert.are.equal(f.buttons.export.point[4], f.buttons.guide.point[4])
  end)

  -- a check box has no label above it, a slider or a list does: a run of check boxes sits closer
  it("check boxes in a run take a shorter row", function()
    local opts = { OPTIONS[1], OPTIONS[3],
                   { type = "toggle", key = "showLust", name = "Lust", default = true },
                   { type = "range", key = "icons", name = "Icons", min = 1, max = 5, default = 3 } }
    local f = panel.new({ options = opts }, host())
    local function y(k) return f.controls[k].point[5] end
    assert.is_true(panel.TOGGLE_ROW < panel.ROW)
    assert.are.equal(panel.TOP, y("scale"))
    assert.are.equal(panel.TOP - panel.ROW, y("showReason"))
    assert.are.equal(y("showReason") - panel.TOGGLE_ROW, y("showLust"))
    assert.are.equal(y("showLust") - panel.ROW, y("icons"))
  end)

  -- Interface Options in 3.3.5a (InterfaceOptionsFrame.xml): a 648 x 520 window, the category
  -- list 175 x 429 on its left; a page gets the rest, about 413 x 429. What sticks out of it is
  -- cut off or lies over the window's border and buttons.
  local PAGE_W, PAGE_H = 413, 429
  -- the templates' own sizes (OptionsSliderTemplate 144 x 17 with its min / max under it,
  -- InterfaceOptionsCheckButtonTemplate 26 x 26 with its text to the right, UIDropDownMenu_SetWidth
  -- adds 25 px on each side, 32 tall); the text's width is a guess: 6 px a letter of GameFontHighlight
  local function box(w)
    local p = w.point
    assert.are.equal("TOPLEFT", p[1])
    assert.are.equal("TOPLEFT", p[3])
    local x, y, width, height = p[4], p[5], w.w, w.h
    if w.kind == "range" then width, height = 144, 17 + 14
    elseif w.kind == "toggle" then width, height = 26 + 2 + 6 * #(_G[w:GetName() .. "Text"].text or ""), 26
    elseif w.kind == "select" then width, height = (w.ddWidth or 0) + 50, 32 end
    return x, y, x + width, y - height
  end

  local function fits(page, list)
    assert.is_true(#list > 0, page.name)
    for _, w in ipairs(list) do
      local left, top, right, bottom = box(w)
      local what = page.name .. ": " .. tostring(w:GetName())
      assert.is_true(left >= 0 and top <= 0, what)
      assert.is_true(right <= PAGE_W, what .. " ends at x = " .. right)
      assert.is_true(bottom >= -PAGE_H, what .. " ends at y = " .. bottom)
    end
  end

  it("every page, Profiles too, fits in Interface Options' page area", function()
    local list = settings.withExtra(require("build").addonOptions().list, { require("update").OPTION })
    list = settings.withExtra(settings.withExtra(list, require("helpers").options()), settings.ADDON_OPTIONS)
    local f = panel.new({ options = list }, host())
    -- the real labels: the longest check box text is the one to measure
    for _, opt in ipairs(list) do
      local c = f.controls[opt.key]
      if opt.type == "toggle" then assert.are.equal(opt.name, _G[c:GetName() .. "Text"].text) end
    end
    for _, sec in ipairs(panel.SECTIONS) do
      local page, mine = f.pages[sec.key], {}
      for _, w in ipairs(f.widgets) do
        if w:GetParent() == page then mine[#mine + 1] = w end
      end
      fits(page, mine)
    end
    local names = function() return { "Default" } end
    local p = require("profilepage").new({ list = names, current = function() return "Default" end,
      active = function() return "Default", "picked" end, rule = function() end })
    fits(p, p.widgets)
  end)

  -- addon/skin.lua styles what is listed here, by kind
  it("lists every control and button of all pages in widgets", function()
    local f = panel.new({ options = OPTIONS }, host())
    local seen = {}
    for _, w in ipairs(f.widgets) do
      assert.is_string(w.kind)
      seen[w] = true
    end
    for _, c in pairs(f.controls) do assert.is_true(seen[c]) end
    for _, b in pairs(f.buttons) do assert.is_true(seen[b]) end
    assert.are.equal(#OPTIONS + #panel.ACTIONS, #f.widgets)
  end)

  -- another profile came in (addon/core.lua): Cancel goes back to it, not to the old profile
  it("reload takes a fresh snapshot for Cancel only when the window had one", function()
    local h = host()
    local f = panel.new({ options = OPTIONS }, h)
    panel.reload(f)
    assert.is_nil(f.opened)
    f.refresh(f)
    h.cfg = { scale = 2, mode = 2, showReason = false } -- the new profile's values
    panel.reload(f)
    assert.are.equal(2, f.controls.scale:GetValue())
    f.controls.scale:SetValue(1.5)
    f.cancel(f)
    assert.are.same({ scale = 2, mode = 2, showReason = false }, h.cfg)
  end)
end)
