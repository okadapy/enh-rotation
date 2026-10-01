-- The Profiles page under DoubtMyRotation in Interface - AddOns: this character's profile, the
-- auto rules, new / copy / delete / reset. Every change goes to the host at once: no Okay /
-- Cancel here, a profile is not a value to take back.
local profiles = require("profiles")

local M = {}
M.NAME = "DoubtMyRotationPanelProfiles"
M.TITLE = "Profiles"
M.PARENT = "DoubtMyRotation"
M.NONE = "(no change)"
M.LEFT, M.TOP, M.ROW = 16, -64, 46
M.WHY = { picked = "picked above", pvp = "battleground or arena", raid = "in a raid", party = "in a dungeon",
          leveling = "leveling" }

local function button(f, key, text, x, y, width, onClick)
  local b = CreateFrame("Button", M.NAME .. "_" .. key, f, "UIPanelButtonTemplate")
  b.kind = "button"
  b:SetWidth(width)
  b:SetHeight(22)
  b:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

-- a list of the profile names; with none, its first entry is "(no change)" (no rule)
local function picker(f, key, label, y, get, set, none)
  local d = CreateFrame("Frame", M.NAME .. "_" .. key, f, "UIDropDownMenuTemplate")
  d.kind = "select"
  d:SetPoint("TOPLEFT", f, "TOPLEFT", M.LEFT, y)
  d.label = d:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  d.label:SetPoint("BOTTOMLEFT", d, "TOPLEFT", 16, 3)
  d.label:SetText(label)
  UIDropDownMenu_SetWidth(d, 160)
  UIDropDownMenu_Initialize(d, function()
    local names = f.host.list()
    if none then table.insert(names, 1, false) end
    local current = get()
    for _, name in ipairs(names) do
      local info = UIDropDownMenu_CreateInfo()
      info.text, info.value = name or M.NONE, name or M.NONE
      info.checked = (name or nil) == current
      info.func = function()
        f.armed, f.message = nil, nil
        set(name or nil)
        f.refresh(f)
      end
      UIDropDownMenu_AddButton(info)
    end
  end)
  d.show = function(self, name)
    UIDropDownMenu_SetSelectedValue(self, name or M.NONE)
    UIDropDownMenu_SetText(self, name or M.NONE)
  end
  return d
end

function M.new(host)
  local f = CreateFrame("Frame", M.NAME, UIParent)
  -- Interface Options shows the page when it is picked; until then it must not sit on screen
  f:Hide()
  f.name, f.parent, f.host = M.TITLE, M.PARENT, host
  f.controls, f.widgets = {}, {}
  local function add(key, w)
    f.controls[key], f.widgets[#f.widgets + 1] = w, w
    return w
  end
  local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", M.LEFT, -16)
  title:SetText(M.PARENT .. " - " .. M.TITLE)
  f.status = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  f.status:SetPoint("TOPLEFT", f, "TOPLEFT", M.LEFT, -38)
  local y = M.TOP
  add("profile", picker(f, "profile", "This character's profile", y, host.current, host.pick))
  y = y - M.ROW
  local edit = CreateFrame("EditBox", M.NAME .. "_name", f, "InputBoxTemplate")
  edit.kind = "edit"
  edit:SetWidth(160)
  edit:SetHeight(20)
  edit:SetAutoFocus(false)
  edit:SetMaxLetters(profiles.NAME_MAX)
  edit:SetPoint("TOPLEFT", f, "TOPLEFT", M.LEFT + 22, y)
  add("name", edit)
  local function create(copyCurrent)
    f.armed = nil
    local ok, err = host.create(edit:GetText() or "", copyCurrent)
    f.message = (not ok) and err or nil
    if ok then
      edit:SetText("")
      edit:ClearFocus()
    end
    f.refresh(f)
  end
  edit:SetScript("OnEnterPressed", function() create(false) end)
  local hint = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  hint:SetPoint("BOTTOMLEFT", edit, "TOPLEFT", -6, 3)
  hint:SetText("New profile name")
  -- the page is about 413 px wide (Interface Options in 3.3.5a): the row ends by x = 402
  add("new", button(f, "new", "New", M.LEFT + 200, y, 80, function() create(false) end))
  add("copy", button(f, "copy", "Copy current", M.LEFT + 286, y, 100, function() create(true) end))
  y = y - 32
  add("delete", button(f, "delete", "Delete", M.LEFT + 22, y, 170, function()
    local cur = host.current()
    f.message = nil
    if cur == profiles.DEFAULT then
      f.armed, f.message = nil, "Default stays"
    elseif f.armed ~= cur then
      f.armed = cur -- a slip of the mouse must not lose a profile: the second click deletes
    else
      f.armed = nil
      local ok, err = host.delete(cur)
      if not ok then f.message = err end
    end
    f.refresh(f)
  end))
  add("reset", button(f, "reset", "Reset active profile", M.LEFT + 200, y, 170, function()
    f.armed, f.message = nil, nil
    host.reset()
    f.refresh(f)
  end))
  y = y - 48
  local head = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  head:SetPoint("TOPLEFT", f, "TOPLEFT", M.LEFT, y)
  head:SetText("Switch automatically (out of combat)")
  y = y - 34
  for i, rule in ipairs(profiles.RULES) do
    add("rule_" .. rule, picker(f, "rule_" .. rule, profiles.RULE_NAMES[rule], y - (i - 1) * M.ROW,
      function() return host.rule(rule) end, function(name) host.setRule(rule, name) end, true))
  end
  f.refresh = function()
    local cur = host.current()
    f.controls.profile:show(cur)
    for _, rule in ipairs(profiles.RULES) do f.controls["rule_" .. rule]:show(host.rule(rule)) end
    local active, why = host.active()
    f.status:SetText(f.message or ("Active now: %s (%s)"):format(tostring(active or cur), M.WHY[why] or tostring(why)))
    f.controls.delete:SetText(f.armed == cur and ("Click again: delete " .. tostring(cur)) or "Delete")
  end
  -- the page is made at login and shown much later: the profile, rules or zone may have changed;
  -- a first Delete click from the last visit must not delete on the next one
  f:SetScript("OnShow", function()
    f.armed, f.message = nil, nil
    f.refresh(f)
  end)
  InterfaceOptions_AddCategory(f)
  return f
end

return M
