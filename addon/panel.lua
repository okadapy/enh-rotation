-- The settings window in Interface - AddOns: a main page and two under it, one control per option
-- (tools/aura.lua M.OPTIONS), applied at once through the host; Cancel puts back what was there
-- when the window was opened. Only 3.3.5a FrameXML templates and UIDropDownMenu_* functions.
local settings = require("settings")

local M = {}
M.ROW = 46       -- px per control row
M.LEFT, M.TOP = 16, -56
M.ACTIONS = { "lock", "export", "hide" }
M.TITLE = "DoubtMyRotation"

M.SECTIONS = {
  { key = "general", options = { "scale", "seconds", "icons", "showReason", "showLust",
                                 "highlightButtons", "showKeybind", "hoverTips" }, actions = true },
  { key = "combat", title = "Combat",
    options = { "mode", "cdFeralSpirit", "cdFireElemental", "cdShamanisticRage", "shield" } },
  { key = "advanced", title = "Advanced",
    options = { "weave", "manaPolicy", "record", "printDebug", "updateCheck", "readyCheck", "rankWarning" } },
}

local function copy(t)
  local c = {}
  for k, v in pairs(t) do c[k] = v end
  return c
end

local function slider(f, o, host)
  local s = CreateFrame("Slider", "DoubtMyRotationPanel_" .. o.key, f, "OptionsSliderTemplate")
  s.kind = "range"
  s:SetMinMaxValues(o.min, o.max)
  s:SetValueStep(o.step or 1)
  _G[s:GetName() .. "Low"]:SetText(tostring(o.min))
  _G[s:GetName() .. "High"]:SetText(tostring(o.max))
  local function label(x) _G[s:GetName() .. "Text"]:SetText(("%s: %s"):format(o.name, tostring(x))) end
  s:SetScript("OnValueChanged", function(_, v)
    local x = settings.snap(o, v)
    label(x)
    if not host.quiet() then host.set(o.key, x) end
  end)
  -- the client skips OnValueChanged when the value is already there: write the label anyway
  s.show = function(self, v) self:SetValue(v); label(v) end
  return s
end

local function toggle(f, o, host)
  local b = CreateFrame("CheckButton", "DoubtMyRotationPanel_" .. o.key, f, "InterfaceOptionsCheckButtonTemplate")
  b.kind = "toggle"
  _G[b:GetName() .. "Text"]:SetText(o.name)
  -- OnClick comes after the box has flipped; GetChecked gives 1 or nil
  b:SetScript("OnClick", function(self) host.set(o.key, self:GetChecked() and true or false) end)
  b.show = function(self, v) self:SetChecked(v) end
  return b
end

local function dropdown(f, o, host)
  local d = CreateFrame("Frame", "DoubtMyRotationPanel_" .. o.key, f, "UIDropDownMenuTemplate")
  d.kind = "select"
  d.label = d:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  d.label:SetPoint("BOTTOMLEFT", d, "TOPLEFT", 16, 3)
  d.label:SetText(o.name)
  UIDropDownMenu_SetWidth(d, 160)
  UIDropDownMenu_Initialize(d, function()
    local current = host.config()[o.key]
    for i, v in ipairs(o.values) do
      local info = UIDropDownMenu_CreateInfo()
      info.text, info.value, info.checked = v, i, i == current
      info.func = function()
        host.set(o.key, i)
        d:show(i)
      end
      UIDropDownMenu_AddButton(info)
    end
  end)
  -- the template reads no tooltipText: the description on the list and on its arrow button
  if o.desc then
    local function enter(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(o.desc, nil, nil, nil, nil, true)
    end
    local function leave() GameTooltip:Hide() end
    for _, target in ipairs({ d, _G[d:GetName() .. "Button"] }) do
      target:EnableMouse(true)
      target:SetScript("OnEnter", enter)
      target:SetScript("OnLeave", leave)
    end
  end
  -- the text after the value: SetSelectedValue may copy a stale label from another open menu
  d.show = function(self, v)
    UIDropDownMenu_SetSelectedValue(self, v)
    UIDropDownMenu_SetText(self, tostring(o.values[v]))
  end
  return d
end

local MAKE = { range = slider, toggle = toggle, select = dropdown }

-- the options of each section, in option order; one of no section goes to the last (Advanced),
-- so an option added to tools/aura.lua and forgotten here still shows up
local function sections(options)
  local where, out = {}, {}
  for i, sec in ipairs(M.SECTIONS) do
    out[i] = {}
    for _, k in ipairs(sec.options) do where[k] = i end
  end
  for _, opt in ipairs(options) do
    local i = where[opt.key] or #M.SECTIONS
    out[i][#out[i] + 1] = opt
  end
  return out
end

function M.new(o, host)
  local main
  local pages, controls, buttons = {}, {}, {}
  for i, list in ipairs(sections(o.options)) do
    local sec = M.SECTIONS[i]
    local f = CreateFrame("Frame", "DoubtMyRotationPanel" .. (sec.title or ""), UIParent)
    -- Interface Options shows the page when it is picked; until then it must not sit on screen
    f:Hide()
    f.name = sec.title or M.TITLE
    if main then f.parent = main.name end
    f.list = list
    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", M.LEFT, -16)
    title:SetText(sec.title and (M.TITLE .. " - " .. sec.title) or M.TITLE)
    for row, opt in ipairs(list) do
      local c = MAKE[opt.type](f, opt, host)
      c:SetPoint("TOPLEFT", f, "TOPLEFT", M.LEFT, M.TOP - (row - 1) * M.ROW)
      -- the slider and check box templates show tooltipText on hover
      if opt.desc then c.tooltipText = opt.desc end
      controls[opt.key] = c
    end
    if sec.actions then
      for j, act in ipairs(M.ACTIONS) do
        local b = CreateFrame("Button", "DoubtMyRotationPanel_" .. act, f, "UIPanelButtonTemplate")
        b:SetWidth(150)
        b:SetHeight(22)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", M.LEFT + (j - 1) * 160, M.TOP - #list * M.ROW - 8)
        b:SetScript("OnClick", function() host.action(act); main.refresh(main) end)
        buttons[act] = b
      end
    end
    pages[sec.key] = f
    main = main or f
  end
  main.pages, main.controls, main.buttons = pages, controls, buttons
  host.quiet = function() return main.refreshing end
  -- the client calls these on every page (refresh on open, okay / cancel on close):
  -- one shared state, kept on the main page, so Cancel puts things back once
  local function refresh()
    main.refreshing = true
    local c = host.config()
    for _, opt in ipairs(o.options) do controls[opt.key]:show(c[opt.key]) end
    for act, b in pairs(buttons) do b:SetText(host.label(act)) end
    main.refreshing = false
    main.opened = main.opened or copy(c)
  end
  local function okay() main.opened = nil end
  local function cancel()
    if main.opened then host.replace(main.opened) end
    main.opened = nil
  end
  -- "These settings" runs it on the shown page, "All settings" on every page: only the page's
  -- own options; through host.set, so all three pages still restart the engine once
  local function default(page)
    local c = host.config()
    for _, opt in ipairs(page.list) do
      if c[opt.key] ~= opt.default then host.set(opt.key, opt.default) end
    end
  end
  for _, sec in ipairs(M.SECTIONS) do
    local f = pages[sec.key]
    f.refresh, f.okay, f.cancel, f.default = refresh, okay, cancel, default
    InterfaceOptions_AddCategory(f)
  end
  -- Okay and Cancel run before the window hides; another center window hides it with neither:
  -- the snapshot goes with the window either way, the next open takes a fresh one
  if InterfaceOptionsFrame and InterfaceOptionsFrame.HookScript then
    InterfaceOptionsFrame:HookScript("OnHide", function() main.opened = nil end)
  end
  return main
end

return M
