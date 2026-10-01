-- The action bars of the 3.3.5a client on top of game_mock: Blizzard buttons, LibActionButton
-- buttons (ElvUI), the action / binding / macro API, frame levels and the mouse-over test.
-- Call B.install(cfg) after G.install().
local B = {}

B.BLIZZARD = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
               "MultiBarRightButton", "MultiBarLeftButton" }

function B.install(cfg)
  cfg = cfg or {}
  B.cfg = cfg
  local create = _G.CreateFrame
  _G.CreateFrame = function(kind, name, parent, template)
    local f = create(kind, name, parent, template)
    f.frameName, f.parent, f.level, f.strata = name, parent, 1, "MEDIUM"
    function f:GetName() return self.frameName end
    function f:SetFrameLevel(l) self.level = l end
    function f:GetFrameLevel() return self.level end
    function f:SetFrameStrata(s) self.strata = s end
    function f:GetFrameStrata() return self.strata end
    function f:GetEffectiveScale() return self.effScale or 1 end
    function f:IsMouseOver() return self.mouseOver and true or false end
    return f
  end
  local actions = cfg.actions or {}
  _G.GetActionInfo = function(slot)
    local a = actions[slot]
    if a then return a[1], a[2], a[3], a[4] end
  end
  _G.HasAction = function(slot) return actions[slot] and 1 or nil end
  _G.GetSpellName = function(i) return (cfg.book or {})[i] end
  _G.GetMacroSpell = function(i) return (cfg.macros or {})[i] end
  _G.GetBindingKey = function(cmd) return (cfg.bindings or {})[cmd] end
  _G.InCombatLockdown = function() return cfg.lockdown and 1 or nil end
  _G.IsShiftKeyDown = function() return cfg.shift and 1 or nil end
  _G.NUM_ACTIONBAR_PAGES = 6
  _G.GetMultiCastBarOffset = function() return 6 end
  _G.ActionButton_GetPagedID = function(b) return b.action end
  for _, bar in ipairs(B.BLIZZARD) do for i = 1, 12 do _G[bar .. i] = nil end end
  for n = 1, 10 do for i = 1, 12 do _G[("ElvUI_Bar%dButton%d"):format(n, i)] = nil end end
  B.labs = {}
  local stub = _G.LibStub
  _G.LibStub = function(name, silent)
    if B.labs[name] then return B.labs[name] end
    return stub and stub(name, silent)
  end
end

-- someone else's button: a protected frame in the client. A test can see whether it was moved
-- to another parent (points, children, scripts and hooks are on the game_mock frame already)
local function protected(b)
  local setParent = b.SetParent
  function b:SetParent(p) self.parentSet = true; setParent(self, p) end
  return b
end

-- a Blizzard bar button on slot (its action field, as ActionButton_UpdateAction leaves it)
function B.blizzard(name, slot, shown)
  local b = protected(CreateFrame("CheckButton", name, UIParent, "ActionBarButtonTemplate"))
  b.action, b.w, b.h = slot, 36, 36
  if shown == false then b:Hide() end
  return b
end

-- an ElvUI button: in LibActionButton-1.0-ElvUI's registry, with its state and binding target
function B.elvui(bar, i, kind, action, bindTarget)
  local b = protected(CreateFrame("CheckButton", ("ElvUI_Bar%dButton%d"):format(bar, i), UIParent))
  b._state_type, b._state_action = kind, action
  b.config = { keyBoundTarget = bindTarget }
  b.w, b.h = 30, 30
  local major = "LibActionButton-1.0-ElvUI"
  B.labs[major] = B.labs[major] or { buttonRegistry = {} }
  B.labs[major].buttonRegistry[b] = true
  return b
end

return B
