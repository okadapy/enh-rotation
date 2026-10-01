-- A stand-in for ElvUI Rebuffed 6.10 (3.3.5a): the global ElvUI = { E, L, V, P, G }, its Skins
-- module recording each Handle* call, and SetTemplate, which ElvUI's Toolkit puts on every frame's
-- metatable (here: game_mock's G.FRAME). Call X.install(cfg) after G.install().
local G = require("game_mock")

local X = {}
X.HANDLERS = { "HandleSliderFrame", "HandleCheckBox", "HandleDropDownBox", "HandleButton", "HandleEditBox",
               "HandleCloseButton", "HandleScrollBar" }

-- cfg: initialized (default true: ElvUI loaded before us), fail = the name of a function that errors
function X.install(cfg)
  cfg = cfg or {}
  local S = { Initialized = cfg.initialized ~= false, calls = {}, callbacks = {}, added = 0 }
  for _, name in ipairs(X.HANDLERS) do
    S[name] = function(self, w, ...)
      if cfg.fail == name then error("ElvUI: " .. name .. " broke") end
      self.calls[#self.calls + 1] = { name, w, ... }
      w.elv = name
    end
  end
  -- ElvUI refuses a name twice (Skins.lua S:AddCallback prints and ignores it); here that is an
  -- error, so a test sees it
  function S:AddCallback(name, fn)
    if self.callbacks[name] then error("S:AddCallback: " .. name .. " is already registered") end
    self.callbacks[name] = fn
    self.added = self.added + 1
  end
  local E = { modules = { Skins = S } }
  function E:GetModule(name, silent)
    local m = self.modules[name]
    if not m and not silent then error("no module " .. name) end
    return m
  end
  _G.ElvUI = { E, {}, {}, {}, {} }
  G.FRAME.SetTemplate = function(self, template)
    if cfg.fail == "SetTemplate" then error("ElvUI: SetTemplate broke") end
    self.elvTemplate = template or "Default"
  end
  X.S, X.E = S, E
  return S
end

-- ElvUI's Skins module coming up (S:Initialize): Initialized first, then the callbacks, each once
function X.initialize()
  X.S.Initialized = true
  for name, fn in pairs(X.S.callbacks) do
    X.S.callbacks[name] = nil
    fn(name)
  end
end

function X.remove()
  _G.ElvUI = nil
  G.FRAME.SetTemplate = nil
  X.S, X.E = nil, nil
end

return X
