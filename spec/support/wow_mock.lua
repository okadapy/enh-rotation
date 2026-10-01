-- Minimal WoW 3.3.5a API mock for shaman tests.
-- cfg fields (all optional):
--   now, level, known = {[id]=true}, costs = {[id]=n}, castMs = {[id]=n},
--   cooldowns = {[nameOrId] = {start, duration}},
--   auras = {[unit] = {HELPFUL = {{name=, count=, duration=, expires=, id=}}, HARMFUL = {...}}},
--   ap = n, spNature = n, spFire = n, meleeCritPct = n, spellCritPct = n,
--   ratings = {[ratingIndex] = bonusPct}, weapons = {mh = {min, max, speed}, oh = {min, max, speed}},
--   enchants = {mh = "Windfury", oh = "Flametongue"}  -- text the tooltip scan will see,
--   totems = {[slot] = {name=, start=, duration=}}, talents = {[tab] = {{name=, rank=, max=}}},
--   latencyMs = n, mana, manaMax, hp, hpMax, moving, inCombat, party = n, raid = n,
--   units = {[unit] = {exists=, canAttack=, dead=, guid=, level=, hp=, hpMax=, player=, casting=}},
--   inRange = {[spellName] = 0|1}
local W = {}

W.NAMES = {
  [403] = "Lightning Bolt", [49238] = "Lightning Bolt", [421] = "Chain Lightning", [49271] = "Chain Lightning",
  [8042] = "Earth Shock", [49231] = "Earth Shock", [8050] = "Flame Shock", [49233] = "Flame Shock",
  [8056] = "Frost Shock", [49236] = "Frost Shock", [17364] = "Stormstrike", [60103] = "Lava Lash",
  [3599] = "Searing Totem", [58704] = "Searing Totem", [8190] = "Magma Totem", [58734] = "Magma Totem",
  [1535] = "Fire Nova", [61657] = "Fire Nova", [2894] = "Fire Elemental Totem", [66842] = "Call of the Elements",
  [324] = "Lightning Shield", [49281] = "Lightning Shield", [30823] = "Shamanistic Rage", [51533] = "Feral Spirit",
  [53817] = "Maelstrom Weapon", [16280] = "Flurry", [2825] = "Bloodlust", [32182] = "Heroism",
  [16166] = "Elemental Mastery", [6603] = "Attack",
}

local RANKS = { [49238] = "Rank 14", [49231] = "Rank 10", [49233] = "Rank 9", [49281] = "Rank 11" }

local function lookup(cfg, x)
  if type(x) == "number" then return x end
  for id, name in pairs(W.NAMES) do
    if name == x and (cfg.known or {})[id] then return id end
  end
  for id, name in pairs(W.NAMES) do
    if name == x then return id end
  end
  return nil
end

function W.install(cfg)
  cfg = cfg or {}
  W.cfg = cfg
  local function unit(u) return (cfg.units or {})[u] end

  _G.GetTime = function() return cfg.now or 100 end
  _G.debugprofilestop = function() return (cfg.profileMs or 0) end
  _G.GetSpellInfo = function(x)
    local id = lookup(cfg, x)
    local name = id and W.NAMES[id]
    if not name then return nil end
    return name, RANKS[id] or "Rank 1", "Interface\\Icons\\Spell_" .. id, (cfg.costs or {})[id] or 0,
      false, 0, (cfg.castMs or {})[id] or 0, 0, 30
  end
  _G.IsSpellKnown = function(id) return (cfg.known or {})[id] == true end
  _G.GetSpellCooldown = function(x)
    local c = (cfg.cooldowns or {})[x]
    if not c and type(x) == "number" then c = (cfg.cooldowns or {})[W.NAMES[x]] end
    if c then return c[1], c[2], 1 end
    return 0, 0, 1
  end
  _G.IsSpellInRange = function(name) local r = (cfg.inRange or {})[name]; if r == nil then return 1 end; return r end
  _G.UnitAura = function(u, i, filter)
    local a = (((cfg.auras or {})[u] or {})[filter or "HELPFUL"] or {})[i]
    if not a then return nil end
    return a.name, "", "icon", a.count or 0, nil, a.duration or 0, a.expires or 0, a.caster or "player",
      nil, nil, a.id or lookup(cfg, a.name)
  end
  _G.UnitBuff = function(u, i) return _G.UnitAura(u, i, "HELPFUL") end
  _G.UnitDebuff = function(u, i) return _G.UnitAura(u, i, "HARMFUL") end
  _G.UnitAttackPower = function() return cfg.ap or 4000, 0, 0 end
  _G.UnitDamage = function()
    local w = cfg.weapons or {}
    local mh, oh = w.mh or { 600, 900, 2.6 }, w.oh
    return mh[1], mh[2], oh and oh[1] or 0, oh and oh[2] or 0, 0, 0, 1
  end
  _G.UnitAttackSpeed = function()
    local w = cfg.weapons or {}
    local mh, oh = w.mh or { 600, 900, 2.6 }, w.oh
    return mh[3], oh and oh[3] or nil
  end
  _G.GetSpellBonusDamage = function(school)
    if school == 3 then return cfg.spFire or 1200 end
    if school == 4 then return cfg.spNature or 1200 end
    return 0
  end
  _G.GetCritChance = function() return cfg.meleeCritPct or 30 end
  _G.GetSpellCritChance = function() return cfg.spellCritPct or 20 end
  _G.GetCombatRatingBonus = function(r) return (cfg.ratings or {})[r] or 0 end
  _G.CR_HIT_MELEE, _G.CR_HIT_SPELL, _G.CR_HASTE_MELEE, _G.CR_HASTE_SPELL = 6, 8, 18, 20
  _G.GetWeaponEnchantInfo = function()
    local e = cfg.enchants or {}
    return e.mh ~= nil, e.mh and 1800000 or nil, 0, e.oh ~= nil, e.oh and 1800000 or nil, 0
  end
  _G.GetInventoryItemLink = function(_, slot)
    local w = cfg.weapons or {}
    if slot == 16 then return "item:1" end
    if slot == 17 and w.oh then return "item:2" end
    return nil
  end
  _G.GetTotemInfo = function(slot)
    local t = (cfg.totems or {})[slot]
    if not t then return false, "", 0, 0, "" end
    return true, t.name, t.start, t.duration, "icon"
  end
  _G.GetNumTalentTabs = function() return 3 end
  _G.GetNumTalents = function(tab) return #(((cfg.talents or {})[tab]) or {}) end
  _G.GetTalentInfo = function(tab, i)
    local t = (((cfg.talents or {})[tab]) or {})[i]
    if not t then return nil end
    return t.name, "icon", 1, 1, t.rank or 0, t.max or 5
  end
  _G.GetNetStats = function() return 0, 0, cfg.latencyMs or 50 end
  _G.UnitLevel = function(u)
    if u == "player" then return cfg.level or 80 end
    local x = unit(u); return x and x.level or 80
  end
  _G.UnitPower = function() return cfg.mana or 8000 end
  _G.UnitPowerMax = function() return cfg.manaMax or 10000 end
  _G.UnitHealth = function(u)
    if u == "player" then return cfg.hp or 20000 end
    local x = unit(u); return x and x.hp or 100
  end
  _G.UnitHealthMax = function(u)
    if u == "player" then return cfg.hpMax or 20000 end
    local x = unit(u); return x and x.hpMax or 100
  end
  _G.GetUnitSpeed = function() return cfg.moving and 7 or 0 end
  _G.UnitAffectingCombat = function(u)
    local x = u ~= "player" and unit(u)
    if x and x.inCombat ~= nil then return x.inCombat and 1 or nil end
    return cfg.inCombat and 1 or nil
  end
  _G.GetNumPartyMembers = function() return cfg.party or 0 end
  _G.GetNumRaidMembers = function() return cfg.raid or 0 end
  _G.UnitExists = function(u) if u == "player" then return 1 end local x = unit(u); return (x and x.exists ~= false) and 1 or nil end
  _G.UnitCanAttack = function(_, u) local x = unit(u); return (x and x.canAttack) and 1 or nil end
  _G.UnitIsDead = function(u) local x = unit(u); return (x and x.dead) and 1 or nil end
  _G.UnitIsDeadOrGhost = _G.UnitIsDead
  _G.UnitIsPlayer = function(u) local x = unit(u); return (x and x.player) and 1 or nil end
  _G.UnitGUID = function(u) if u == "player" then return "Player-1" end local x = unit(u); return x and x.guid end
  _G.UnitCastingInfo = function(u)
    local x = u == "player" and cfg.casting or (unit(u) and unit(u).casting)
    if not x then return nil end
    return x.name, nil, x.name, "icon", x.startMs or 0, x.endMs, false, 1, false
  end
  _G.UnitChannelInfo = function() return nil end
end

-- Frames, textures, font strings, WeakAuras and C_Timer for runtime/timeline tests.
W.timers = {}
function W.runTimers(now)
  local keep = {}
  for _, t in ipairs(W.timers) do
    if not t.cancelled and t.at <= now then t.fn() elseif not t.cancelled then keep[#keep + 1] = t end
  end
  W.timers = keep
end

local function region(kind)
  local r = { kind = kind, shown = true, points = {}, alpha = 1 }
  function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
  function r:ClearAllPoints() self.points = {} end
  function r:SetSize(w, h) self.w, self.h = w, h end
  function r:SetWidth(w) self.w = w end
  function r:SetHeight(h) self.h = h end
  function r:GetWidth() return self.w or 0 end
  function r:GetHeight() return self.h or 0 end
  function r:Show() self.shown = true end
  function r:Hide() self.shown = false end
  function r:IsShown() return self.shown end
  function r:SetAlpha(a) self.alpha = a end
  function r:SetTexture(t) self.texture = t end
  function r:SetTexCoord(...) self.texCoord = { ... } end
  function r:SetVertexColor(...) self.color = { ... } end
  function r:SetDesaturated(d) self.desaturated = d end
  function r:SetDrawLayer(l) self.layer = l end
  function r:SetBlendMode(m) self.blend = m end
  function r:SetFont(...) self.font = { ... } end
  function r:SetText(t) self.text = t end
  function r:GetText() return self.text end
  function r:SetTextColor(...) self.textColor = { ... } end
  function r:SetJustifyH(j) self.justify = j end
  return r
end

function W.frames()
  local sent = {}
  _G.CreateFrame = function(kind, name, parent)
    local f = region(kind)
    f.events, f.scripts, f.parent, f.children = {}, {}, parent, {}
    function f:RegisterEvent(e) self.events[e] = true end
    function f:UnregisterEvent(e) self.events[e] = nil end
    function f:UnregisterAllEvents() self.events = {} end
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:GetScript(k) return self.scripts[k] end
    function f:CreateTexture() local t = region("Texture"); self.children[#self.children + 1] = t; return t end
    function f:CreateFontString() local t = region("FontString"); self.children[#self.children + 1] = t; return t end
    function f:SetFrameStrata(s) self.strata = s end
    function f:SetOwner() end
    function f:SetInventoryItem(_, slot)
      local e = (W.cfg and W.cfg.enchants) or {}
      local text = slot == 16 and e.mh or slot == 17 and e.oh or nil
      self.lines = text and { "Weapon", text .. " (30 min)" } or { "Weapon" }
      for i, line in ipairs(self.lines) do
        local fs = region("FontString"); fs.text = line
        if name then _G[name .. "TextLeft" .. i] = fs end
      end
    end
    function f:NumLines() return #(self.lines or {}) end
    function f:ClearLines() self.lines = {} end
    if name then _G[name] = f end
    return f
  end
  _G.UIParent = region("Frame")
  _G.WeakAuras = { ScanEvents = function(event, ...) sent[#sent + 1] = { event = event, args = { ... } } end }
  _G.C_Timer = {
    After = function(d, fn) W.timers[#W.timers + 1] = { at = GetTime() + d, fn = fn } end,
    NewTimer = function(d, fn)
      local t = { at = GetTime() + d, fn = fn }
      function t:Cancel() self.cancelled = true end
      W.timers[#W.timers + 1] = t
      return t
    end,
  }
  _G.DEFAULT_CHAT_FRAME = { messages = {}, AddMessage = function(self, m) self.messages[#self.messages + 1] = m end }
  _G.print = function() end
  return sent
end

return W
