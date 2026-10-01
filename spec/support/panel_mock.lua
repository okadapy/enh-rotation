-- The bits of the 3.3.5a client the settings window uses, on top of game_mock: sliders, check
-- boxes, buttons, drop-down menus and Interface Options. Call P.install() after G.install().
local G = require("game_mock")

local P = {}

local function widgets(f)
  function f:SetMinMaxValues(lo, hi) self.min, self.max = lo, hi end
  function f:SetValueStep(s) self.step = s end
  function f:SetValue(v)
    self.value = v
    if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end
  end
  function f:GetValue() return self.value end
  function f:SetChecked(c) self.checked = c and true or false end
  -- the 3.3.5a client gives 1 or nil, not a boolean
  function f:GetChecked() return self.checked and 1 or nil end
  function f:Click() if self.scripts.OnClick then self.scripts.OnClick(self, "LeftButton") end end
  -- not self.name: an options page uses that field for its title in the list
  function f:GetName() return self.frameName end
end

function P.install()
  local create = _G.CreateFrame
  _G.CreateFrame = function(kind, name, parent, template)
    local f = create(kind, name, parent, template)
    f.parent, f.frameName = parent, name
    widgets(f)
    -- FrameXML templates make named font strings: $parentText, and on a slider $parentLow / $parentHigh
    if name and template then
      for _, suffix in ipairs({ "Text", "Low", "High" }) do _G[name .. suffix] = G.fontString() end
      -- a drop-down's arrow button covers its right part: $parentButton
      if template == "UIDropDownMenuTemplate" then _G[name .. "Button"] = create("Button", name .. "Button", f) end
    end
    return f
  end
  G.categories = {}
  _G.InterfaceOptions_AddCategory = function(panel) G.categories[#G.categories + 1] = panel end
  G.dropdowns, G.menuButtons = {}, {}
  _G.UIDropDownMenu_Initialize = function(frame, init) G.dropdowns[frame] = { init = init } end
  _G.UIDropDownMenu_CreateInfo = function() return {} end
  _G.UIDropDownMenu_AddButton = function(info) G.menuButtons[#G.menuButtons + 1] = info end
  _G.UIDropDownMenu_SetSelectedValue = function(frame, v) frame.selected = v end
  _G.UIDropDownMenu_SetWidth = function(frame, w) frame.ddWidth = w end
  _G.UIDropDownMenu_SetText = function(frame, t) frame.ddText = t end
  _G.DoubtMyRotationPanel, _G.DoubtMyRotationPanelCombat, _G.DoubtMyRotationPanelAdvanced = nil, nil, nil
  -- the Interface Options window itself: shown on /dmr, hidden by Okay, Cancel, Escape or another window
  _G.InterfaceOptionsFrame = create("Frame", "InterfaceOptionsFrame", UIParent)
  G.tooltip = { shown = false }
  _G.GameTooltip = {
    SetOwner = function(self, owner) G.tooltip.owner = owner end,
    SetText = function(self, text) G.tooltip.text = text; G.tooltip.shown = true end,
    Hide = function(self) G.tooltip.shown = false end,
  }
end

-- "opens" a drop-down the way the client does: runs its initializer, returns the menu items
function G.menu(frame)
  G.menuButtons = {}
  G.dropdowns[frame].init(frame)
  return G.menuButtons
end

return P
