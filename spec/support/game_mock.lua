local spells = require("spells")

local G = {}

G.EXTRA_NAMES = {
  [53817] = "Maelstrom Weapon", [49281] = "Lightning Shield", [16280] = "Flurry",
  [30823] = "Shamanistic Rage", [2825] = "Bloodlust", [32182] = "Heroism", [16166] = "Elemental Mastery",
  [52127] = "Water Shield",
  [8050] = "Flame Shock", [17364] = "Stormstrike",
  [3599] = "Searing Totem", [8190] = "Magma Totem", [2894] = "Fire Elemental Totem",
  [8232] = "Windfury Weapon", [8024] = "Flametongue Weapon", [8017] = "Rockbiter Weapon",
  -- raid.lua: target debuffs, the player's buffs, our own earth / air totems
  [7386] = "Sunder Armor", [8647] = "Expose Armor", [55749] = "Acid Spit", [770] = "Faerie Fire",
  [16857] = "Faerie Fire (Feral)", [56631] = "Sting", [702] = "Curse of Weakness", [53598] = "Spore Cloud",
  [1490] = "Curse of the Elements", [51726] = "Ebon Plague", [60431] = "Earth and Moon", [30708] = "Totem of Wrath",
  [21183] = "Heart of the Crusader", [58410] = "Master Poisoner", [30069] = "Blood Frenzy", [58683] = "Savage Combat",
  [22959] = "Improved Scorch", [12579] = "Winter's Chill", [17800] = "Shadow Mastery", [33198] = "Misery",
  [57330] = "Horn of Winter", [8076] = "Strength of Earth", [8512] = "Windfury Totem", [55610] = "Improved Icy Talons",
  [8075] = "Strength of Earth Totem",
}

function G.names()
  local byId, rankOf = {}, {}
  for _, meta in ipairs(spells.CATALOG) do
    for i, id in ipairs(meta.ranks) do
      byId[id] = meta.name
      rankOf[id] = i
    end
  end
  for id, name in pairs(G.EXTRA_NAMES) do byId[id] = byId[id] or name end
  return byId, rankOf
end

local function region(kind)
  local r = { kind = kind, shown = true, points = {}, w = 0, h = 0, alpha = 1 }
  function r:SetPoint(...) self.point = { ... }; self.points[#self.points + 1] = self.point end
  function r:GetPoint() local p = self.point or {}; return p[1], p[2], p[3], p[4], p[5] end
  function r:ClearAllPoints() self.points = {}; self.point = nil end
  function r:SetWidth(w) self.w = w end
  function r:SetHeight(h) self.h = h end
  function r:GetWidth() return self.w end
  function r:GetHeight() return self.h end
  function r:Show() self.shown = true end
  function r:Hide() self.shown = false end
  function r:IsShown() return self.shown end
  function r:SetAlpha(a) self.alpha = a end
  function r:SetAllPoints(other) self.allPoints = other or true end
  function r:SetClampedToScreen(c) self.clamped = c end
  function r:GetObjectType() return kind end
  function r:SetFrameLevel(l) self.level = l end
  function r:GetFrameLevel() return self.level or 1 end
  return r
end

function G.texture()
  local t = region("Texture")
  function t:SetTexture(p) self.texture = p end
  function t:SetVertexColor(...) self.color = { ... } end
  function t:SetTexCoord(...) self.coords = { ... } end
  function t:SetBlendMode(m) self.blend = m end
  function t:SetDesaturated(d) self.desat = d end
  return t
end

function G.fontString()
  local f = region("FontString")
  function f:SetText(s) self.text = s end
  function f:GetText() return self.text end
  function f:SetTextColor(...) self.textColor = { ... } end
  function f:SetJustifyH(j) self.justify = j end
  function f:SetJustifyV(j) self.justifyV = j end
  return f
end

-- methods a UI addon puts on every frame's metatable (ElvUI's SetTemplate); emptied by G.install
G.FRAME = {}

function G.frame(kind, name)
  local f = region(kind or "Frame")
  f.name, f.events, f.scripts, f.children = name, {}, {}, {}
  f.kids = {}
  function f:RegisterEvent(e)
    if e == "UNIT_POWER" then error("Attempt to register unknown event UNIT_POWER") end
    self.events[e] = true
  end
  function f:UnregisterAllEvents() self.events = {} end
  function f:SetScript(k, fn) self.scripts[k] = fn end
  f.hooks = {}
  function f:HookScript(k, fn)
    self.hooks[k] = self.hooks[k] or {}
    table.insert(self.hooks[k], fn)
  end
  local function fire(self, k)
    if self.scripts[k] then self.scripts[k](self) end
    for _, fn in ipairs(self.hooks[k] or {}) do fn(self) end
  end
  function f:Show() if not self.shown then self.shown = true; fire(self, "OnShow") end end
  function f:Hide() if self.shown then self.shown = false; fire(self, "OnHide") end end
  function f:IsVisible() return self.shown end
  function f:SetParent(p) self.parent = p end
  function f:GetParent() return self.parent end
  function f:GetScript(k) return self.scripts[k] end
  function f:SetScale(s) self.scale = s end
  function f:CreateTexture() local t = G.texture(); self.children[#self.children + 1] = t; return t end
  function f:CreateFontString() local t = G.fontString(); self.children[#self.children + 1] = t; return t end
  function f:GetRegions() return unpack(self.children) end
  -- dialog frames (export window): backdrop, dragging, edit box, scroll frame, buttons
  function f:SetBackdrop(b) self.backdrop = b end
  function f:SetFrameStrata(s) self.strata = s end
  function f:SetMovable(m) self.movable = m end
  function f:EnableMouse(m) self.mouse = m end
  function f:IsMouseEnabled() return self.mouse and true or false end
  function f:RegisterForDrag(...) self.drag = { ... } end
  function f:StartMoving() self.moving = true end
  function f:StopMovingOrSizing() self.moving = false end
  function f:SetMultiLine(m) self.multiLine = m end
  function f:SetMaxLetters(n) self.maxLetters = n end
  function f:SetAutoFocus(a) self.autoFocus = a end
  function f:SetFontObject(o) self.font = o end
  function f:SetText(s) self.text = s end
  function f:GetText() return self.text end
  function f:HighlightText() self.highlighted = true end
  function f:SetFocus() self.focused = true end
  function f:SetScrollChild(c) self.scrollChild = c end
  function f:SetOwner(owner, anchor) self.owner = owner; self.anchor = anchor end
  function f:ClearLines() self.children = {} end
  function f:SetInventoryItem(_, slot)
    for _, line in ipairs(((G.cfg.tooltip or {})[slot]) or {}) do
      local fs = G.fontString()
      fs.text = line
      self.children[#self.children + 1] = fs
    end
  end
  -- the windows of stage 3: child frames, the minimap button, edit boxes, buttons
  function f:GetChildren() return unpack(self.kids) end
  function f:GetCenter() local c = self.center or { 0, 0 }; return c[1], c[2] end
  function f:GetEffectiveScale() return self.scale or 1 end
  function f:RegisterForClicks(...) self.clicks = { ... } end
  function f:SetNormalTexture(p) self.normalTexture = p end
  function f:SetHighlightTexture(p) self.highlightTexture = p end
  function f:SetPushedTexture(p) self.pushedTexture = p end
  function f:ClearFocus() self.focused = false end
  function f:SetToplevel(t) self.toplevel = t end
  function f:Enable() self.disabled = false end
  function f:Disable() self.disabled = true end
  -- the 3.3.5a client gives 1 or nil
  function f:IsEnabled() return (not self.disabled) and 1 or nil end
  return setmetatable(f, { __index = G.FRAME })
end

-- cfg: now, level, mana, manaMax, int, hp, hpMax, ap, sp={[school]=n}, crit, spellCrit, ratings={[cr]=n}, hitMod,
-- speed={mh,oh}, damage={minMH,maxMH,minOH,maxOH}, latencyMs, raid, party, moving, inCombat,
-- playerDead, taxi, vehicle, mounted,
-- known={[id]=true}, bookOnly={[id]=true}, costs={[name]=n}, castMs={[name]=ms}, cooldowns={[name]={start,dur}},
-- inRange={[name]=0|1}, interact, auras={[unit]={HELPFUL={...},HARMFUL={...}}} (name,count,expires,caster,id),
-- target={exists,enemy,level,hp,hpMax,guid,classification,dead,player}, totems={[slot]={name,start,dur}},
-- enchants={mh=bool,oh=bool}, tooltip={[16]={lines},[17]={lines}}, links={[slot]=itemLink}, casting={name,startMs,endMs}, talents={[tab]={{name,rank}}}
-- inventory={[slot]=itemId}, glyphs={[socket]={spellId,glyphType}}
-- lockdown, instance="none"|"pvp"|"arena"|"party"|"raid", zone, cursor={x,y}, minimapShape, minimapCenter={x,y}
function G.install(cfg)
  cfg = cfg or {}
  G.cfg = cfg
  G.sent, G.printed = {}, {}
  for k in pairs(G.FRAME) do G.FRAME[k] = nil end
  local byId, rankOf = G.names()
  local known, book = cfg.known or {}, cfg.bookOnly or {}
  local function inBook(name)
    local best
    for id, n in pairs(byId) do
      if n == name and (known[id] or book[id]) and (not best or rankOf[id] > rankOf[best]) then best = id end
    end
    return best
  end
  local function tgt()
    local t = cfg.target
    if t and t.exists ~= false then return t end
    return nil
  end

  _G.GetTime = function() return cfg.now or 100 end
  _G.debugprofilestop = function() return os.clock() * 1000 end
  _G.GetSpellInfo = function(x)
    local id = x
    if type(x) ~= "number" then
      id = inBook(x)
      if not id then return nil end
    end
    local name = (cfg.spellNames or {})[id] or byId[id]
    if not name then return nil end
    return name, "Rank " .. (rankOf[id] or 1), "Interface\\Icons\\" .. id, (cfg.costs or {})[name] or 0,
      false, 0, (cfg.castMs or {})[name] or 0, 0, 30
  end
  _G.IsSpellKnown = function(id) return known[id] == true end
  _G.GetSpellCooldown = function(name)
    local c = (cfg.cooldowns or {})[name]
    if c then return c[1], c[2], 1 end
    return 0, 0, 1
  end
  _G.IsSpellInRange = function(name) return (cfg.inRange or {})[name] end
  _G.CheckInteractDistance = function() return cfg.interact and 1 or nil end
  _G.GetNumTalentTabs = function() return 3 end
  _G.GetNumTalents = function(tab) return #(((cfg.talents or {})[tab]) or {}) end
  _G.GetTalentInfo = function(tab, i)
    local t = (((cfg.talents or {})[tab]) or {})[i]
    if not t then return nil end
    return t[1], "icon", 1, 1, t[2], 5
  end
  _G.UnitAura = function(u, i, filter)
    local a = ((((cfg.auras or {})[u]) or {})[filter] or {})[i]
    if not a then return nil end
    return a.name, "", "icon", a.count or 0, nil, a.duration or 0, a.expires or 0, a.caster or "player", nil, nil, a.id
  end
  _G.UnitLevel = function(u)
    if u == "player" then return cfg.level or 80 end
    local t = tgt()
    return t and t.level or 0
  end
  _G.UnitPower = function() return cfg.mana or 8000 end
  _G.UnitPowerMax = function() return cfg.manaMax or 10000 end
  _G.UnitStat = function(_, i)
    if i == 4 then return cfg.int or 800, cfg.int or 800 end
    return 100, 100
  end
  _G.UnitHealth = function(u)
    if u == "player" then return cfg.hp or 20000 end
    local t = tgt()
    return t and t.hp or 0
  end
  _G.UnitHealthMax = function(u)
    if u == "player" then return cfg.hpMax or 20000 end
    local t = tgt()
    return t and t.hpMax or 0
  end
  _G.UnitExists = function(u)
    if u == "player" then return 1 end
    return tgt() and 1 or nil
  end
  _G.UnitCanAttack = function()
    local t = tgt()
    return (t and t.enemy ~= false) and 1 or nil
  end
  _G.UnitIsDeadOrGhost = function(u)
    if u == "player" then return cfg.playerDead and 1 or nil end
    local t = tgt()
    return (t and t.dead) and 1 or nil
  end
  _G.UnitIsPlayer = function(u)
    if u == "player" then return 1 end
    local t = tgt()
    return (t and t.player) and 1 or nil
  end
  _G.UnitGUID = function(u)
    if u == "player" then return "Player-1" end
    local t = tgt()
    return t and (t.guid or "Creature-1") or nil
  end
  _G.UnitClassification = function()
    local t = tgt()
    return t and t.classification or "normal"
  end
  _G.UnitClass = function() return "Shaman", cfg.class or "SHAMAN" end
  _G.UnitAttackPower = function() return cfg.ap or 4000, 0, 0 end
  _G.GetSpellBonusDamage = function(school) return ((cfg.sp or {})[school]) or 1000 end
  _G.GetCritChance = function() return cfg.crit or 30 end
  _G.GetSpellCritChance = function() return cfg.spellCrit or 20 end
  _G.GetCombatRatingBonus = function(cr) return ((cfg.ratings or {})[cr]) or 0 end
  _G.GetHitModifier = function() return cfg.hitMod or 0 end
  _G.UnitAttackSpeed = function()
    local s = cfg.speed or { 2.6, 2.6 }
    return s[1], s[2]
  end
  _G.UnitDamage = function()
    local d = cfg.damage or { 600, 900, 300, 450 }
    return d[1], d[2], d[3], d[4], 0, 0, 1
  end
  _G.GetNetStats = function() return 0, 0, cfg.latencyMs or 50 end
  _G.GetNumRaidMembers = function() return cfg.raid or 0 end
  _G.GetNumPartyMembers = function() return cfg.party or 0 end
  _G.GetInventoryItemLink = function(_, slot) return ((cfg.links or {})[slot]) end
  _G.GetInventoryItemID = function(_, slot) return ((cfg.inventory or {})[slot]) end
  -- 3.3.5a: enabled, glyphType (1 major, 2 minor), glyphSpell, icon (Blizzard_GlyphUI.lua)
  _G.GetGlyphSocketInfo = function(i)
    local g = (cfg.glyphs or {})[i]
    if not g then return true, i % 2 == 0 and 2 or 1, nil, nil end
    return true, g[2] or 1, g[1], "icon"
  end
  _G.GetUnitSpeed = function() return cfg.moving and 7 or 0 end
  _G.UnitAffectingCombat = function(u)
    local t = u == "target" and tgt()
    if t and t.inCombat ~= nil then return t.inCombat and 1 or nil end
    return cfg.inCombat ~= false and 1 or nil
  end
  _G.UnitOnTaxi = function() return cfg.taxi and 1 or nil end
  _G.UnitInVehicle = function() return cfg.vehicle and 1 or nil end
  _G.UnitHasVehicleUI = function() return cfg.vehicle and 1 or nil end
  _G.IsMounted = function() return cfg.mounted and 1 or nil end
  _G.UnitCastingInfo = function(u)
    local c = u == "player" and cfg.casting
    if not c then return nil end
    return c.name, nil, nil, "icon", c.startMs, c.endMs, false, c.castID or 1, false
  end
  _G.GetTotemInfo = function(slot)
    local t = (cfg.totems or {})[slot]
    if not t then return false, "", 0, 0, "" end
    return true, t[1], t[2], t[3], "icon"
  end
  _G.GetWeaponEnchantInfo = function()
    local e = cfg.enchants or {}
    return e.mh and 1 or nil, 1000, 0, e.oh and 1 or nil, 1000, 0
  end
  _G.CreateFrame = function(kind, name, parent, template)
    local f = G.frame(kind, name)
    f.template = template
    -- not f.parent: on an options page that field names the parent category (panel_mock sets it)
    if parent and parent.kids then parent.kids[#parent.kids + 1] = f end
    if name then _G[name] = f end
    return f
  end
  _G.UIParent = G.frame("Frame", "UIParent")
  _G.WorldFrame = G.frame("Frame", "WorldFrame")
  _G.InCombatLockdown = function() return cfg.lockdown and 1 or nil end
  -- IsInInstance's second value: "none", "pvp", "arena", "party", "raid" (FrameXML WorldStateFrame.lua)
  _G.IsInInstance = function()
    local kind = cfg.instance or "none"
    return (kind ~= "none") and 1 or nil, kind
  end
  _G.GetInstanceInfo = function()
    local kind = cfg.instance or "none"
    return cfg.zone or "Northrend", kind, 1, "", kind == "raid" and 25 or 5, 0, false
  end
  _G.GetCursorPosition = function() local c = cfg.cursor or { 0, 0 }; return c[1], c[2] end
  _G.Minimap = G.frame("Frame", "Minimap")
  Minimap.center = cfg.minimapCenter or { 1000, 700 }
  -- the client has no GetMinimapShape; addons that reshape the minimap (ElvUI) define it
  _G.GetMinimapShape = cfg.minimapShape and function() return cfg.minimapShape end or nil
  _G.UISpecialFrames = {}
  _G.WeakAuras = { ScanEvents = function(...) G.sent[#G.sent + 1] = { ... } end }
  _G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    G.printed[#G.printed + 1] = table.concat(parts, " ")
  end
  _G.EnhRotEngineFrame = nil
  _G.EnhRotScanTip = nil
  _G.EnhRotExportFrame = nil
  -- the libraries WeakAuras brings (its import strings use them)
  local libs = { LibSerialize = require("LibSerialize"), LibDeflate = require("LibDeflate") }
  if cfg.noLibs then _G.LibStub = nil else _G.LibStub = function(name) return libs[name] end end
  -- the addon (addon/core.lua): slash commands, its options page, addon messages, its globals
  _G.SlashCmdList = {}
  _G.SLASH_DOUBTMYROTATION1 = nil
  G.opened, G.opens = nil, 0
  _G.InterfaceOptionsFrame_OpenToCategory = function(panel) G.opened = panel; G.opens = G.opens + 1 end
  G.addonSent = {}
  _G.SendAddonMessage = function(...) G.addonSent[#G.addonSent + 1] = { ... } end
  for _, k in ipairs({ "Addon", "DB", "CharDB", "Loader", "Frame", "Timer", "Updates", "Panel", "PanelCombat",
                       "PanelAdvanced", "PanelProfiles", "Highlight", "Explain", "Checks", "Ready", "Wizard", "Card",
                       "MinimapButton", "Guide", "Coach", "Events" }) do
    _G["DoubtMyRotation" .. k] = nil
  end
  return cfg
end

return G
