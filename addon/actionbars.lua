-- Which action bar buttons carry which of our spells, and their keys. A source of buttons is
-- one entry in M.SOURCES: the standard Blizzard bars, and every bar built on LibActionButton-1.0
-- (ElvUI's own copy, Bartender4). Read only: nothing here changes a button (they are protected
-- frames; the overlays of addon/highlight.lua are frames of our own).
local M = {}

M.BLIZZARD = {
  { "ActionButton", "ACTIONBUTTON" },
  { "MultiBarBottomLeftButton", "MULTIACTIONBAR1BUTTON" },
  { "MultiBarBottomRightButton", "MULTIACTIONBAR2BUTTON" },
  { "MultiBarRightButton", "MULTIACTIONBAR3BUTTON" },
  { "MultiBarLeftButton", "MULTIACTIONBAR4BUTTON" },
}
M.LABS = { "LibActionButton-1.0", "LibActionButton-1.0-ElvUI" }
-- the order matters: the mouse wheel before BUTTON, modifiers first
M.SHORT = {
  { "SHIFT%-", "S-" }, { "CTRL%-", "C-" }, { "ALT%-", "A-" },
  { "MOUSEWHEELUP", "MwU" }, { "MOUSEWHEELDOWN", "MwD" }, { "BUTTON(%d+)", "M%1" },
  { "NUMPAD", "N" }, { "PAGEUP", "PgU" }, { "PAGEDOWN", "PgD" }, { "SPACE", "Spc" },
}

function M.short(key)
  if not key or key == "" then return nil end
  for _, r in ipairs(M.SHORT) do key = key:gsub(r[1], r[2]) end
  return key
end

-- The spell on an action slot, by name (the same for every rank and matched against the
-- engine's localized names). 3.3.5a: "spell", spellbook index, "spell", spell id; a macro:
-- "macro", its index. Items, empty slots and the rest: nil.
function M.spellOfSlot(slot)
  if not slot or not GetActionInfo then return nil end
  local kind, id, _, spellId = GetActionInfo(slot)
  if kind == "spell" then
    if type(spellId) == "number" and spellId > 0 then return (GetSpellInfo(spellId)) end
    if id and GetSpellName then return (GetSpellName(id, "spell")) end
  elseif kind == "macro" and id and GetMacroSpell then
    return (GetMacroSpell(id))
  end
  return nil
end

-- the first key bound to any of the commands
local function bound(a, b)
  if not GetBindingKey then return nil end
  return (a and GetBindingKey(a)) or (b and GetBindingKey(b)) or nil
end

M.blizzard = { name = "blizzard" }
function M.blizzard.buttons(out)
  for _, bar in ipairs(M.BLIZZARD) do
    for i = 1, 12 do
      local name = bar[1] .. i
      local b = _G[name]
      if b and b:IsVisible() then
        local slot = b.action or (ActionButton_GetPagedID and ActionButton_GetPagedID(b))
        out[#out + 1] = { frame = b, name = name, spell = M.spellOfSlot(slot),
                          binding = bound((b.buttonType or bar[2]) .. i, "CLICK " .. name .. ":LeftButton") }
      end
    end
  end
end

-- a LibActionButton button's current state: an action slot, a spell id or a macro index
local function labSpell(b)
  local kind, action = b._state_type, b._state_action
  if kind == nil and b.GetAction then kind, action = b:GetAction() end
  if kind == "action" then return M.spellOfSlot(action) end
  if kind == "spell" and action then return (GetSpellInfo(action)) end
  if kind == "macro" and action and GetMacroSpell then return (GetMacroSpell(action)) end
  return nil
end

M.lab = { name = "LibActionButton" }
function M.lab.buttons(out)
  if not LibStub then return end
  local seen, list = {}, {}
  for _, major in ipairs(M.LABS) do
    local lib = LibStub(major, true)
    for b in pairs(lib and lib.buttonRegistry or {}) do
      if not seen[b] then seen[b] = true; list[#list + 1] = b end
    end
  end
  -- by name: the same key wins every time (pairs has no order)
  table.sort(list, function(a, c) return (a:GetName() or "") < (c:GetName() or "") end)
  for _, b in ipairs(list) do
    if b:IsVisible() then
      local name = b:GetName()
      out[#out + 1] = { frame = b, name = name, spell = labSpell(b),
                        binding = bound(b.config and b.config.keyBoundTarget, name and ("CLICK " .. name .. ":LeftButton")) }
    end
  end
end

M.SOURCES = { M.blizzard, M.lab }

function M.scan(keyByName, sources)
  local list = {}
  for _, src in ipairs(sources or M.SOURCES) do src.buttons(list) end
  local map = {}
  for _, e in ipairs(list) do
    local key = e.spell and keyByName[e.spell]
    if key then
      local m = map[key]
      if not m then m = { buttons = {} }; map[key] = m end
      m.buttons[#m.buttons + 1] = e
      if not m.hotkey and e.binding then m.hotkey = M.short(e.binding) end
    end
  end
  return map
end

return M
