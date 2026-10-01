-- "What's new" cards: at levels 10, 20 ... 80 a short window, once per character - what the level
-- brought and how the rotation changes. The words are written by hand for 3.3.5a; which spells are
-- new and every number in the text (levels, cooldowns, durations) come from the spell data.
local data = require("spells_data")
local spells = require("spells")
local talents = require("talents")

local M = {}
M.NAME = "DoubtMyRotationCard"
M.WIDTH, M.HEIGHT = 400, 260
M.ICONS = 6
-- catalog spells that are talents: learned on the standard leveling path, not at their rank's level
M.TALENT_SPELLS = { stormstrike = true, lavaLash = true, shamanisticRage = true, feralSpirit = true }
-- names in the texts that are neither in spells.CATALOG nor talents: their trainer level (3.3.5a)
M.HAND_LEVELS = { ["Flametongue Weapon"] = 10, ["Water Shield"] = 20, ["Windfury Weapon"] = 30,
                  ["Bloodlust"] = 70, ["Heroism"] = 70 }

-- Every number in a text is a {field:key} substitution (M.FIELDS): spec/addon_cards_spec.lua fails
-- on a digit or a number word typed by hand, and on a spell or talent named before its level.
M.CARDS = {
  { level = 10, title = "Level 10: Flame Shock and totems",
    text = "Flame Shock burns the target for {dur:flameShock}. It shares one {cd:flameShock} cooldown with Earth Shock: "
      .. "you can use one shock at a time. Searing Totem shoots one enemy near it for {dur:searingTotem}. "
      .. "Put Flametongue Weapon on your weapon. From now on every level gives a talent point: "
      .. "this addon plays the Enhancement tree." },
  { level = 20, title = "Level 20: Frost Shock and Water Shield",
    text = "Frost Shock slows the target and shares the shock cooldown. Use it on an enemy that runs away; "
      .. "for damage the timeline keeps to Earth Shock. Water Shield gives you mana instead of damage: "
      .. "wear it when your mana runs low. With the Shield option on auto the addon follows the shield you wear. "
      .. "Fire Nova (since level {lvl:fireNova}) needs a fire totem down and hits the enemies near that totem." },
  { level = 30, title = "Level 30: Windfury Weapon and the totem bar",
    text = "Put Windfury Weapon on your main hand. Call of the Elements drops one totem of each element with one press: "
      .. "pick them on the totem bar that comes with it. Magma Totem (since level {lvl:magmaTotem}) burns the enemies "
      .. "near it for {dur:magmaTotem}. With Fire Nova it is your answer to a group of enemies." },
  { level = 40, title = "Level 40: Stormstrike",
    text = "Stormstrike (your talent at level {lvl:stormstrike}) is an instant weapon strike. For {dur:stormstrike} after it, "
      .. "your next {charges:stormstrike} Nature hits on the target deal {bonus:stormstrike}% more: an Earth Shock "
      .. "or a Lightning Bolt right after Stormstrike hits harder. Its cooldown is {cd:stormstrike}. "
      .. "Chain Lightning (since level {lvl:chainLightning}) jumps to up to {targets:chainLightning} enemies." },
  { level = 50, title = "Level 50: two weapons, Lava Lash, Shamanistic Rage",
    text = "The Dual Wield talent (level {lvl:dualWield}) lets you hold a weapon in your off hand: put Flametongue Weapon on it "
      .. "and keep Windfury Weapon on the main hand. Lava Lash (since level {lvl:lavaLash}) strikes with the off-hand weapon "
      .. "and hits harder when Flametongue is on it. Shamanistic Rage lasts {dur:shamanisticRage}: you take less damage "
      .. "and your melee hits can give you mana. Its cooldown is {cd:shamanisticRage}, so it is your mana tool. "
      .. "The Combat settings say when the timeline offers it." },
  { level = 60, title = "Level 60: Maelstrom Weapon and Feral Spirit",
    text = "Maelstrom Weapon (talent, from level {lvl:maelstromWeapon}): your melee hits can give you stacks of it. "
      .. "Each stack makes your next Lightning Bolt or Chain Lightning cast faster, and with full stacks the cast is instant. "
      .. "The dots on the timeline count the stacks. Feral Spirit calls spirit wolves to fight for you for {dur:feralSpirit}; "
      .. "its cooldown is {cd:feralSpirit}, so save it for a boss or a long fight." },
  { level = 70, title = "Level 70: Fire Elemental and Bloodlust",
    text = "Fire Elemental Totem (since level {lvl:fireElemental}) fights for you for {dur:fireElemental}, "
      .. "and its cooldown is {cd:fireElemental}: drop it early on a boss. Bloodlust (Heroism for the Alliance) makes "
      .. "your whole group attack and cast faster, but a player can get it only once in a long while, "
      .. "so in a group the leader says when. The addon can show when it is ready (General: Show Bloodlust ready in group)." },
  { level = 80, title = "Level 80: the full rotation",
    text = "Visit the trainer for your last ranks. Your main buttons now: Lightning Bolt when Maelstrom Weapon is full, "
      .. "Stormstrike, Flame Shock when it is not on the target, Earth Shock, Lava Lash, Fire Nova with a fire totem down, "
      .. "and Lightning Shield when its charges run out. Which one is best changes with your gear and the fight: "
      .. "the timeline weighs them every moment, so follow the big icon." },
}

function M.talentLevel(key)
  for level = 10, 80 do
    if (talents.standard(level)[key] or 0) > 0 then return level end
  end
  return nil
end

function M.learned(key)
  if M.TALENT_SPELLS[key] then return M.talentLevel(key) end
  local r = data[key] and data[key][1]
  return r and r.level
end

local function span(sec)
  if sec >= 60 and sec % 60 == 0 then return ("%d min"):format(sec / 60) end
  return ("%d s"):format(sec)
end

M.FIELDS = {
  lvl = function(key) return M.learned(key) or M.talentLevel(key) end,
  cd = function(key)
    local r = data[key]
    return r and span(r[#r].cdMs / 1000)
  end,
  dur = function(key)
    local s = spells.byKey[key]
    return s and s.duration and span(s.duration)
  end,
  charges = function(key) return spells.byKey[key] and spells.byKey[key].charges end,
  bonus = function(key) return spells.byKey[key] and spells.byKey[key].bonus end,
  targets = function(key) return spells.byKey[key] and spells.byKey[key].maxTargets end,
}

function M.text(s)
  return (s:gsub("{(%a+):(%a+)}", function(field, key)
    local f = M.FIELDS[field]
    local v = f and f(key)
    if v == nil then error(("cards: no %s for %s"):format(field, key)) end
    return tostring(v)
  end))
end

function M.newSince(from, to)
  local out = {}
  for _, s in ipairs(spells.CATALOG) do
    local l = M.learned(s.key)
    if l and l > from and l <= to then out[#out + 1] = { key = s.key, name = s.name, icon = s.icon, level = l } end
  end
  table.sort(out, function(a, b)
    if a.level ~= b.level then return a.level < b.level end
    return a.name < b.name
  end)
  return out
end

function M.previous(level)
  local prev = 0
  for _, c in ipairs(M.CARDS) do
    if c.level < level then prev = c.level end
  end
  return prev
end

-- one card at a time: levels skipped past (the option was off) are old news
function M.due(level, seen)
  local card
  for _, c in ipairs(M.CARDS) do
    if c.level <= level and not seen[c.level] then
      if card then seen[card.level] = true end
      card = c
    end
  end
  return card
end

-- the addon put on a grown character: the cards behind it are old news
function M.firstRun(level, seen)
  for _, c in ipairs(M.CARDS) do
    if c.level <= level then seen[c.level] = true end
  end
end

local BACKDROP = { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                   edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                   tile = true, tileSize = 32, edgeSize = 32, insets = { left = 8, right = 8, top = 8, bottom = 8 } }

local W = {}

function W:open(card, close)
  self.close = close
  self.title:SetText(card.title)
  self.text:SetText(M.text(card.text))
  local prev = M.previous(card.level)
  local new = M.newSince(prev, card.level)
  local names = {}
  for i, s in ipairs(new) do names[i] = s.name end
  self.names:SetText(((prev > 0 and "New since level %d: " or "Your spells so far: "):format(prev)) .. table.concat(names, ", "))
  for i, ic in ipairs(self.icons) do
    if new[i] then
      ic:SetTexture(new[i].icon)
      ic:Show()
    else
      ic:Hide()
    end
  end
  self.again:SetChecked(self.host.config().levelCards ~= false)
  self:Show()
end

-- a fight began (addon/guide.lua): away without closing, the queue shows it again after
function W:hide()
  self.close = nil
  self:Hide()
end

function W:finish()
  local close = self.close
  self.close = nil
  self:Hide()
  if close then close() end
end

function M.window(host)
  local w = M.frame
  if w then
    w.host = host
    return w
  end
  w = CreateFrame("Frame", M.NAME, UIParent)
  w.kind, w.widgets, w.host = "window", {}, host
  w:SetWidth(M.WIDTH)
  w:SetHeight(M.HEIGHT)
  w:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  w:SetFrameStrata("DIALOG")
  w:SetBackdrop(BACKDROP)
  w:SetMovable(true)
  w:EnableMouse(true)
  w:RegisterForDrag("LeftButton")
  w:SetScript("OnDragStart", function(self) self:StartMoving() end)
  w:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  w.title = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  w.title:SetPoint("TOP", w, "TOP", 0, -16)
  w.text = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  w.text:SetPoint("TOPLEFT", w, "TOPLEFT", 20, -44)
  w.text:SetWidth(M.WIDTH - 40)
  w.text:SetJustifyH("LEFT")
  w.icons = {}
  for i = 1, M.ICONS do
    local ic = w:CreateTexture(nil, "ARTWORK")
    ic:SetWidth(28)
    ic:SetHeight(28)
    ic:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 20 + (i - 1) * 32, 76)
    ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ic:Hide()
    w.icons[i] = ic
  end
  w.names = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  w.names:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 20, 62)
  w.names:SetWidth(M.WIDTH - 40)
  w.names:SetJustifyH("LEFT")
  local again = CreateFrame("CheckButton", M.NAME .. "Again", w, "InterfaceOptionsCheckButtonTemplate")
  again.kind = "toggle"
  again:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 16, 14)
  _G[again:GetName() .. "Text"]:SetText("Show a card at the next levels")
  -- OnClick comes after the box has flipped; GetChecked gives 1 or nil
  again:SetScript("OnClick", function(self) w.host.set("levelCards", self:GetChecked() and true or false) end)
  w.again = again
  local ok = CreateFrame("Button", M.NAME .. "OK", w, "UIPanelButtonTemplate")
  ok.kind = "button"
  ok:SetWidth(96)
  ok:SetHeight(22)
  ok:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -16, 16)
  ok:SetText("OK")
  ok:SetScript("OnClick", function() w:finish() end)
  w.ok = ok
  w.widgets = { again, ok }
  for k, fn in pairs(W) do w[k] = fn end
  -- Escape closes it like OK (the client hides the frames listed in UISpecialFrames)
  w:SetScript("OnHide", function(self) if self.close then self:finish() end end)
  if UISpecialFrames then table.insert(UISpecialFrames, M.NAME) end
  w:Hide()
  M.frame = w
  return w
end

return M
