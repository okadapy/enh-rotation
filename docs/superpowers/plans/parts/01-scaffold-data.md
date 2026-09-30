## Contract additions

Дополнения к контракту из шапки плана (остальные части обязаны их учитывать):

1. **`spells_data[key][i]`** — кроме `id, level, min, max, coef, tick, tickCoef, ticks` ещё:
   - `castMs` — базовое время каста ранга в мс (0 — мгновенное);
   - `gcdMs` — общая перезарядка из DBC (`StartRecoveryTime`);
   - `cdMs` — собственная перезарядка (`max(RecoveryTime, CategoryRecoveryTime)`);
   - `weaponPct` — процент урона оружием: Stormstrike, Lava Lash; иначе 0.

   Поля, которых у заклинания нет, равны `0` (не `nil`). Исключение — `tick`/`tickCoef`/`ticks`: они есть только у `flameShock`.
2. **`spells.CATALOG[i]`** — кроме полей контракта:
   - `hands = "both"|"oh"|nil` — какими руками бьёт оружейный удар;
   - `duration` — длительность эффекта в секундах: дебафф, тотем, щит;
   - `period` — период тиков или атак тотема;
   - `charges` — заряды дебаффа или щита;
   - `maxTargets` — потолок целей для AoE;
   - `requiresFireTotem = true` — у Fire Nova;
   - `bonus` — бонус Stormstrike к природному урону в процентах.

   Поле `ranks` строится из `spells_data` и не пишется руками.
3. **`talents.KEYS[i]`** = `{ key, name }` (без `tab`/`index`). Таланты ищутся **по английскому имени** при чтении: так не нужно угадывать номер вкладки и позицию, а клиент пользователя — enGB.
4. **`talents.read(numTabs, numTalents, info) -> { [key] = rank }`**:
   - аргументы — функции с сигнатурами `GetNumTalentTabs()`, `GetNumTalents(tab)`, `GetTalentInfo(tab, i)`;
   - в результате есть **все** ключи из `KEYS`, для отсутствующих — `0`.
5. **Мок `spec/support/wow_mock.lua`** — `W.install(cfg)`, `W.frames()`, `W.runTimers(now)`, `W.NAMES`. Формат `cfg` описан в начале файла мока.
6. **`spec/support/fixtures.lua`**:
   - `F.state(patch)` — полный `S` по контракту (80 уровень, WF/FT, одна цель-босс);
   - `F.merge(dst, patch)`;
   - `F.only(S, ...keys)` — оставить в `S.spells` только перечисленные ключи;
   - `F.SPELLS80` — значения по умолчанию для `S.spells`.

---

### Task 1: Каркас проекта, мок API игры, фикстуры

**Files:**
- Create: `Dockerfile`, `docker-compose.yml`, `.busted`, `AGENTS.md`, `.claude/CLAUDE.md` (симлинк на `../AGENTS.md`)
- Create: `vendor/LibDeflate.lua`, `vendor/LibSerialize.lua` (копии из `frost-rotation`)
- Create: `tools/encode.lua` (копия из `frost-rotation`)
- Create: `spec/support/wow_mock.lua`, `spec/support/fixtures.lua`
- Test: `spec/encode_spec.lua`, `spec/smoke_spec.lua`

**Interfaces:**
- Consumes: ничего.
- Produces:
  - `encode.encode(t) -> "!WA:2!..."`, `encode.decode(str) -> t | nil, err`;
  - мок: `W.install(cfg)`, `W.frames() -> sent`, `W.runTimers(now)`, `W.NAMES`;
  - фикстуры: `F.state(patch)`, `F.merge`, `F.only`, `F.SPELLS80`.

- [ ] **Step 1: Скопировать инструменты и библиотеки из `frost-rotation`**

```bash
cd /home/okada/whitemane/enh-rotation
mkdir -p vendor tools src spec/support .claude
cp /home/okada/whitemane/frost-rotation/vendor/LibDeflate.lua vendor/
cp /home/okada/whitemane/frost-rotation/vendor/LibSerialize.lua vendor/
cp /home/okada/whitemane/frost-rotation/tools/encode.lua tools/
cp /home/okada/whitemane/frost-rotation/spec/encode_spec.lua spec/
```

- [ ] **Step 2: Написать `Dockerfile`, `docker-compose.yml`, `.busted`**

`Dockerfile`:
```dockerfile
FROM nickblah/lua:5.1-luarocks-alpine
RUN apk add --no-cache build-base unzip curl git python3 && luarocks install busted 2.2.0-1
WORKDIR /work
```

`docker-compose.yml`:
```yaml
services:
  test:
    build: .
    volumes:
      - .:/work
    working_dir: /work
```

`.busted`:
```lua
return {
  default = {
    ROOT = { "spec" },
    pattern = "_spec",
    lpath = "src/?.lua;spec/support/?.lua;tools/?.lua;vendor/?.lua",
  },
}
```

- [ ] **Step 3: Написать `AGENTS.md` и симлинк**

`AGENTS.md`:
```markdown
# EnhRot

WeakAura-подсказчик для энх-шамана под WotLK 3.3.5a (WeakAuras 5.22 backport): мини-симулятор боя на 6 с вперёд, лента времени, часы ударов.

- Тесты: `docker compose run --rm test busted`
- Один файл: `docker compose run --rm test busted spec/<name>_spec.lua`
- Сборка строки импорта: `docker compose run --rm test lua tools/build.lua` → `dist/EnhRot.txt`
- Декодировать чужую строку: `docker compose run --rm test lua tools/build.lua decode path/to/file.txt`
- Перегенерировать данные рангов: `docker compose run --rm test python3 tools/spelldata.py data/Spell.dbc src/spells_data.lua`
  (`data/Spell.dbc` — из `rebuffed.mpq` клиента, в git не хранится)
- Дизайн: `docs/superpowers/specs/2026-09-30-enh-rotation-design.md`
- План: `docs/superpowers/plans/2026-09-30-enh-rotation.md`

Конвенции:
- Lua 5.1.
- В `src/` нельзя `pcall`, `loadstring`, `setfenv`, `getfenv`, `_G` (песочница WeakAuras).
- API игры читают только `snapshot`, `runtime`, `timeline`; остальные модули — чистая логика.
- Тексты в игре — на английском.
- `src/spells_data.lua` не править руками.
```

```bash
cd /home/okada/whitemane/enh-rotation && ln -s ../AGENTS.md .claude/CLAUDE.md
```

- [ ] **Step 4: Написать мок API игры `spec/support/wow_mock.lua`**

```lua
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
  _G.UnitAffectingCombat = function() return cfg.inCombat and 1 or nil end
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
```

- [ ] **Step 5: Написать фикстуры `spec/support/fixtures.lua`**

```lua
local F = {}

-- level-80 defaults for S.spells (id = top rank, cost in mana, cast in seconds, cd remaining)
F.SPELLS80 = {
  stormstrike     = { id = 17364, rank = 1,  cd = 0, cost = 351, cast = 0 },
  lavaLash        = { id = 60103, rank = 1,  cd = 0, cost = 176, cast = 0 },
  earthShock      = { id = 49231, rank = 10, cd = 0, cost = 791, cast = 0 },
  flameShock      = { id = 49233, rank = 9,  cd = 0, cost = 747, cast = 0 },
  frostShock      = { id = 49236, rank = 7,  cd = 0, cost = 791, cast = 0 },
  lightningBolt   = { id = 49238, rank = 14, cd = 0, cost = 440, cast = 2.5 },
  chainLightning  = { id = 49271, rank = 8,  cd = 0, cost = 1143, cast = 2.0 },
  searingTotem    = { id = 58704, rank = 10, cd = 0, cost = 308, cast = 0 },
  magmaTotem      = { id = 58734, rank = 7,  cd = 0, cost = 1187, cast = 0 },
  fireNova        = { id = 61657, rank = 9,  cd = 0, cost = 967, cast = 0 },
  fireElemental   = { id = 2894,  rank = 1,  cd = 0, cost = 1011, cast = 0 },
  callOfElements  = { id = 66842, rank = 1,  cd = 0, cost = 0,   cast = 0 },
  lightningShield = { id = 49281, rank = 11, cd = 0, cost = 0,   cast = 0 },
  shamanisticRage = { id = 30823, rank = 1,  cd = 0, cost = 0,   cast = 0 },
  feralSpirit     = { id = 51533, rank = 1,  cd = 0, cost = 527, cast = 0 },
}

function F.copy(t)
  if type(t) ~= "table" then return t end
  local o = {}
  for k, v in pairs(t) do o[k] = F.copy(v) end
  return o
end

function F.merge(dst, patch)
  for k, v in pairs(patch) do
    if type(v) == "table" and type(dst[k]) == "table" then F.merge(dst[k], v) else dst[k] = F.copy(v) end
  end
  return dst
end

-- Level-80 enhancement shaman (WF main hand, FT off hand) on a single raid boss.
function F.state(patch)
  local S = {
    now = 100.0, gcdRemains = 0, castRemains = 0, gcd = 1.5, latency = 0.15, mode = "raid",
    player = {
      level = 80, mana = 8000, manaMax = 10000, baseMana = 4396, hpPct = 1.0,
      ap = 4000, spNature = 1200, spFire = 1200, meleeCrit = 0.30, spellCrit = 0.20,
      meleeHit = 0.08, spellHit = 0.10, spellHaste = 1.10, meleeHaste = 1.25,
      moving = false, inCombat = true,
    },
    weapons = {
      mh = { speed = 2.6, min = 600, max = 900, enchant = "wf" },
      oh = { speed = 2.6, min = 600, max = 900, enchant = "ft" },
    },
    talents = {
      convection = 5, concussion = 5, callOfFlame = 3, elementalDevastation = 3,
      enhancingTotems = 3, ancestralKnowledge = 2, thunderingStrikes = 5, improvedShields = 3,
      elementalWeapons = 3, shamanisticFocus = 1, flurry = 5, weaponMastery = 3,
      dualWieldSpecialization = 3, dualWield = 1, stormstrike = 1, staticShock = 3,
      lavaLash = 1, improvedStormstrike = 2, mentalQuickness = 3, mentalDexterity = 3,
      unleashedRage = 2, shamanisticRage = 1, maelstromWeapon = 5, feralSpirit = 1,
      spiritWeapons = 1, improvedFireNova = 0, reverberation = 0, elementalFury = 0,
      elementalFocus = 0, elementalPrecision = 0, stormEarthAndFire = 0,
    },
    spells = F.copy(F.SPELLS80),
    buffs = {
      mw = { stacks = 0, remains = 0 }, ls = { charges = 3, remains = 600 },
      flurry = { charges = 0, remains = 0 }, rage = 0, lust = 0, em = 0,
    },
    target = {
      exists = true, enemy = true, level = 83, hp = 1e7, hpMax = 1e7, hpPct = 1.0, ttd = 300,
      range = "melee", fs = 10, ss = { charges = 0, remains = 0 }, guessed = false,
    },
    totems = { fire = { kind = "magma", remains = 15 }, water = { remains = 200 } },
    swing = {
      attacking = true,
      mh = { next = 1.2, speed = 2.6 }, oh = { next = 0.4, speed = 2.6 },
      resetByInstant = {},
    },
    enemies = { melee = 1, nearby = 1 },
    inflight = {},
  }
  return F.merge(S, patch or {})
end

-- keep only the listed spell keys in S.spells (for leveling scenarios)
function F.only(S, ...)
  local keep = {}
  for _, k in ipairs({ ... }) do keep[k] = S.spells[k] or F.copy(F.SPELLS80[k]) end
  S.spells = keep
  return S
end

return F
```

- [ ] **Step 6: Написать smoke-тест `spec/smoke_spec.lua`**

```lua
local W = require("wow_mock")
local F = require("fixtures")

describe("test harness", function()
  it("mock returns shaman spell info with 3.3.5 layout", function()
    W.install({ known = { [49238] = true }, castMs = { [49238] = 2500 } })
    local name, rank, icon, cost, _, _, castMs = GetSpellInfo(49238)
    assert.are.equal("Lightning Bolt", name)
    assert.are.equal("Rank 14", rank)
    assert.are.equal(2500, castMs)
    assert.is_true(IsSpellKnown(49238))
    assert.is_false(IsSpellKnown(403))
  end)

  it("mock tooltip exposes weapon enchant text", function()
    W.install({ enchants = { mh = "Windfury", oh = "Flametongue" }, weapons = { mh = { 1, 2, 2.6 }, oh = { 1, 2, 2.6 } } })
    W.frames()
    local tip = CreateFrame("GameTooltip", "EnhRotScan")
    tip:SetInventoryItem("player", 17)
    assert.are.equal("Flametongue (30 min)", _G["EnhRotScanTextLeft2"]:GetText())
  end)

  it("fixture state has every contract field and merges patches deeply", function()
    local S = F.state({ buffs = { mw = { stacks = 5 } }, target = { fs = 0 } })
    assert.are.equal(5, S.buffs.mw.stacks)
    assert.are.equal(0, S.buffs.mw.remains)
    assert.are.equal(0, S.target.fs)
    assert.are.equal(83, S.target.level)
    for _, k in ipairs({ "now", "gcdRemains", "castRemains", "gcd", "latency", "mode", "player", "weapons",
                         "talents", "spells", "buffs", "target", "totems", "swing", "enemies", "inflight" }) do
      assert.is_not_nil(S[k], k)
    end
  end)

  it("F.only keeps just the given spells", function()
    local S = F.only(F.state(), "earthShock", "lightningBolt")
    assert.is_not_nil(S.spells.earthShock)
    assert.is_nil(S.spells.stormstrike)
  end)
end)
```

- [ ] **Step 7: Собрать образ и прогнать тесты**

Run: `cd /home/okada/whitemane/enh-rotation && docker compose build && docker compose run --rm test busted`
Expected: PASS — `encode_spec` (2) и `smoke_spec` (4), `0 failures`.

- [ ] **Step 8: Commit**

```bash
cd /home/okada/whitemane/enh-rotation
git add Dockerfile docker-compose.yml .busted .gitignore AGENTS.md .claude/CLAUDE.md vendor tools/encode.lua spec
git commit -m "Каркас EnhRot: Docker, тесты, мок API шамана, фикстуры"
```

---

### Task 2: Генератор данных рангов из `Spell.dbc`

**Files:**
- Create: `tools/spelldata.py`
- Create (генерируется): `src/spells_data.lua`
- Delete: `tools/dbc_probe.py` (разовый скрипт исследования, заменён генератором)
- Test: `spec/spells_data_spec.lua`

**Interfaces:**
- Consumes: `data/Spell.dbc` (3.3.5a, 234 поля, 936 байт на запись; копия уже лежит в `data/`, в git не хранится).
- Produces: `require("spells_data")[key]` — массив рангов по возрастанию `level`:
  `{ id, level, castMs, gcdMs, cdMs, min, max, coef, weaponPct, tick, tickCoef, ticks }`.

Как читается DBC:
- Заголовок: `"WDBC"`, `n`, `fields`, `recordSize`, `stringSize`.
- Поля — `uint32`. Индексы: `0` id, `28` CastingTimeIndex, `29` RecoveryTime, `30` CategoryRecoveryTime, `39` spellLevel, `71–73` Effect, `74–76` DieSides, `80–82` BasePoints (знаковое), `95–97` ApplyAuraName, `98–100` Amplitude, `206` StartRecoveryTime, `229–231` EffectBonusMultiplier (float).
- Урон эффекта: `min = BasePoints + 1`, `max = BasePoints + DieSides`.

Ранги выписаны явно (пары «ID для изучения → ID, откуда брать урон»). Автоподбор по имени ненадёжен: у Lightning Bolt есть «Rank N»-копии для Lightning Overload (45284–45296) с тем же GCD. Пары взяты из выгрузки DBC в этой сессии.

- [ ] **Step 1: Написать падающий тест `spec/spells_data_spec.lua`**

```lua
local data = require("spells_data")

local function byId(key, id)
  for _, r in ipairs(data[key]) do if r.id == id then return r end end
  return nil
end

describe("spells_data (generated from client Spell.dbc)", function()
  it("has Lightning Bolt ranks 1 and 14 with real numbers", function()
    local r1 = byId("lightningBolt", 403)
    assert.are.same({ 1, 1500, 13, 15, 0.125 }, { r1.level, r1.castMs, r1.min, r1.max, r1.coef })
    local r14 = byId("lightningBolt", 49238)
    assert.are.same({ 79, 2500, 715, 815, 0.714, 1500 }, { r14.level, r14.castMs, r14.min, r14.max, r14.coef, r14.gcdMs })
    assert.are.equal(14, #data.lightningBolt)
  end)

  it("has shocks with the shared 6 s category cooldown", function()
    local es = byId("earthShock", 49231)
    assert.are.same({ 79, 849, 895, 0.386, 6000 }, { es.level, es.min, es.max, es.coef, es.cdMs })
    local fs = byId("flameShock", 49233)
    assert.are.same({ 80, 500, 500, 0.214, 139, 0.1, 4 }, { fs.level, fs.min, fs.max, fs.coef, fs.tick, fs.tickCoef, fs.ticks })
    local frs = byId("frostShock", 49236)
    assert.are.same({ 78, 802, 848 }, { frs.level, frs.min, frs.max })
  end)

  it("takes totem and Fire Nova damage from the child spells", function()
    local mt = byId("magmaTotem", 58734)
    assert.are.same({ 78, 371, 371, 0.1, 1000 }, { mt.level, mt.min, mt.max, mt.coef, mt.gcdMs })
    local st = byId("searingTotem", 58704)
    assert.are.same({ 80, 90, 120, 0.167 }, { st.level, st.min, st.max, st.coef })
    local fn = byId("fireNova", 61657)
    assert.are.same({ 80, 893, 997, 0.214, 10000 }, { fn.level, fn.min, fn.max, fn.coef, fn.cdMs })
    local ls = byId("lightningShield", 49281)
    assert.are.same({ 80, 380, 380, 0.267 }, { ls.level, ls.min, ls.max, ls.coef })
  end)

  it("has weapon strikes and single-rank talents", function()
    local ll = byId("lavaLash", 60103)
    assert.are.same({ 41, 100, 6000 }, { ll.level, ll.weaponPct, ll.cdMs })
    local ss = byId("stormstrike", 17364)
    assert.are.same({ 40, 100, 8000 }, { ss.level, ss.weaponPct, ss.cdMs })
    assert.are.equal(60000, byId("shamanisticRage", 30823).cdMs)
    assert.are.equal(180000, byId("feralSpirit", 51533).cdMs)
    assert.are.equal(600000, byId("fireElemental", 2894).cdMs)
    assert.are.equal(30, byId("callOfElements", 66842).level)
    assert.are.equal(8, #data.chainLightning)
  end)

  it("sorts ranks by level and fills absent numbers with 0", function()
    for key, ranks in pairs(data) do
      for i = 2, #ranks do assert.is_true(ranks[i - 1].level <= ranks[i].level, key) end
      for _, r in ipairs(ranks) do
        for _, f in ipairs({ "id", "level", "castMs", "gcdMs", "cdMs", "min", "max", "coef", "weaponPct" }) do
          assert.are.equal("number", type(r[f]), key .. "." .. f)
        end
      end
    end
  end)
end)
```

- [ ] **Step 2: Запустить — тест падает**

Run: `docker compose run --rm test busted spec/spells_data_spec.lua`
Expected: FAIL — `module 'spells_data' not found`.

- [ ] **Step 3: Написать генератор `tools/spelldata.py`**

```python
#!/usr/bin/env python3
"""Generate src/spells_data.lua from the 3.3.5a client Spell.dbc.

Usage: python3 tools/spelldata.py data/Spell.dbc src/spells_data.lua
"""
import struct
import sys

F_ID, F_CAST_IDX, F_RECOVERY, F_CAT_RECOVERY, F_LEVEL = 0, 28, 29, 30, 39
F_EFFECT, F_DIE, F_BASE, F_AURA, F_AMPL = 71, 74, 80, 95, 98
F_GCD, F_BONUS = 206, 229
EFFECT_SCHOOL_DAMAGE, EFFECT_APPLY_AURA, EFFECT_WEAPON_PERCENT = 2, 6, 31
AURA_PERIODIC_DAMAGE = 3

# SpellCastTimes.dbc index -> base cast time in ms (only indexes used by these spells)
CAST_MS = {1: 0, 5: 2000, 16: 1500, 19: 2500}

# DoT durations in seconds (SpellDuration.dbc is not extracted; values from the 3.3.5 tooltips)
DOT_DURATION = {"flameShock": 12.0}

# weapon strikes whose percent is not in an effect of the learn spell
WEAPON_PCT = {"stormstrike": 100}


def pairs(learn, dmg=None):
    """Zip learn-spell ids with damage-spell ids (same id when dmg is None)."""
    return list(zip(learn, dmg if dmg else learn))


RANKS = {
    "lightningBolt": pairs([403, 529, 548, 915, 943, 6041, 10391, 10392, 15207, 15208, 25448, 25449, 49237, 49238]),
    "chainLightning": pairs([421, 930, 2860, 10605, 25439, 25442, 49270, 49271]),
    "earthShock": pairs([8042, 8044, 8045, 8046, 10412, 10413, 10414, 25454, 49230, 49231]),
    "flameShock": pairs([8050, 8052, 8053, 10447, 10448, 29228, 25457, 49232, 49233]),
    "frostShock": pairs([8056, 8058, 10472, 10473, 25464, 49235, 49236]),
    "stormstrike": pairs([17364]),
    "lavaLash": pairs([60103]),
    "searingTotem": pairs([3599, 6363, 6364, 6365, 10437, 10438, 25533, 58699, 58703, 58704],
                          [3606, 6350, 6351, 6352, 10435, 10436, 25530, 58700, 58701, 58702]),
    "magmaTotem": pairs([8190, 10585, 10586, 10587, 25552, 58731, 58734],
                        [8187, 10579, 10580, 10581, 25550, 58732, 58735]),
    "fireNova": pairs([1535, 8498, 8499, 11314, 11315, 25546, 25547, 61649, 61657],
                      [8349, 8502, 8503, 11306, 11307, 25535, 25537, 61650, 61654]),
    "fireElemental": pairs([2894]),
    "callOfElements": pairs([66842]),
    "lightningShield": pairs([324, 325, 905, 945, 8134, 10431, 10432, 25469, 25472, 49280, 49281],
                             [26364, 26365, 26366, 26367, 26369, 26370, 26363, 26371, 26372, 49278, 49279]),
    "shamanisticRage": pairs([30823]),
    "feralSpirit": pairs([51533]),
}


def load(path):
    data = open(path, "rb").read()
    magic, count, fields, size, _ = struct.unpack("<4s4I", data[:20])
    if magic != b"WDBC" or fields != 234:
        raise SystemExit("unexpected Spell.dbc layout: %r %d" % (magic, fields))
    rows = {}
    for i in range(count):
        row = struct.unpack("<%dI" % fields, data[20 + i * size:20 + (i + 1) * size])
        rows[row[F_ID]] = row
    return rows


def f32(u):
    return round(struct.unpack("<f", struct.pack("<I", u))[0], 4)


def signed(u):
    return u - 2 ** 32 if u >= 2 ** 31 else u


def effect(row, kind, aura=None):
    for k in range(3):
        if row[F_EFFECT + k] == kind and (aura is None or row[F_AURA + k] == aura):
            base = signed(row[F_BASE + k])
            return {"min": base + 1, "max": base + max(row[F_DIE + k], 1),
                    "coef": f32(row[F_BONUS + k]), "ampl": row[F_AMPL + k]}
    return None


def entry(key, learn, dmg):
    cast_idx = learn[F_CAST_IDX]
    if cast_idx not in CAST_MS:
        raise SystemExit("unknown cast index %d for %s %d" % (cast_idx, key, learn[F_ID]))
    e = {"id": learn[F_ID], "level": learn[F_LEVEL], "castMs": CAST_MS[cast_idx], "gcdMs": learn[F_GCD],
         "cdMs": max(learn[F_RECOVERY], learn[F_CAT_RECOVERY]),
         "min": 0, "max": 0, "coef": 0, "weaponPct": WEAPON_PCT.get(key, 0)}
    direct = effect(dmg, EFFECT_SCHOOL_DAMAGE)
    if direct:
        e.update(min=direct["min"], max=direct["max"], coef=direct["coef"])
    weapon = effect(learn, EFFECT_WEAPON_PERCENT)
    if weapon:
        e["weaponPct"] = weapon["min"]
    dot = effect(dmg, EFFECT_APPLY_AURA, AURA_PERIODIC_DAMAGE)
    if dot and key in DOT_DURATION:
        e.update(tick=dot["min"], tickCoef=dot["coef"], ticks=int(round(DOT_DURATION[key] * 1000 / dot["ampl"])))
    return e


FIELD_ORDER = ["id", "level", "castMs", "gcdMs", "cdMs", "min", "max", "coef", "weaponPct", "tick", "tickCoef", "ticks"]


def lua_num(v):
    return repr(v) if isinstance(v, float) else str(v)


def render(table):
    out = ["-- GENERATED by tools/spelldata.py from the client Spell.dbc. Do not edit by hand.", "return {"]
    for key in sorted(table):
        out.append("  %s = {" % key)
        for e in table[key]:
            parts = ["%s = %s" % (f, lua_num(e[f])) for f in FIELD_ORDER if f in e]
            out.append("    { %s }," % ", ".join(parts))
        out.append("  },")
    out.append("}")
    return "\n".join(out) + "\n"


def main(src, dst):
    rows = load(src)
    table = {}
    for key, ids in RANKS.items():
        entries = []
        for learn_id, dmg_id in ids:
            if learn_id not in rows or dmg_id not in rows:
                raise SystemExit("spell %d/%d for %s not found in DBC" % (learn_id, dmg_id, key))
            entries.append(entry(key, rows[learn_id], rows[dmg_id]))
        table[key] = sorted(entries, key=lambda e: (e["level"], e["id"]))
    open(dst, "w").write(render(table))
    print("%s: %d spells, %d ranks" % (dst, len(table), sum(len(v) for v in table.values())))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
```

- [ ] **Step 4: Сгенерировать данные**

Run: `docker compose run --rm test python3 tools/spelldata.py data/Spell.dbc src/spells_data.lua`
Expected: `src/spells_data.lua: 15 spells, 91 ranks` (проверено пробным прогоном генератора на `data/Spell.dbc`).

Если генератор падает с `unknown cast index`, это не ошибка DBC. Посмотреть индекс в сообщении и добавить его в `CAST_MS`: 1 → 0, 5 → 2000, 16 → 1500, 19 → 2500 — другие индексы у этих ID в выгрузке не встречались.

- [ ] **Step 5: Запустить тест — проходит**

Run: `docker compose run --rm test busted spec/spells_data_spec.lua`
Expected: PASS, 5 successes.

- [ ] **Step 6: Commit**

```bash
git rm --cached -q tools/dbc_probe.py 2>/dev/null; rm -f tools/dbc_probe.py
git add tools/spelldata.py src/spells_data.lua spec/spells_data_spec.lua
git commit -m "Генератор данных рангов шамана из Spell.dbc клиента"
```

---

### Task 3: Каталог заклинаний и таланты

**Files:**
- Create: `src/spells.lua`, `src/talents.lua`
- Test: `spec/spells_spec.lua`, `spec/talents_spec.lua`

**Interfaces:**
- Consumes: `spells_data` (Task 2); мок `W.install` (Task 1) — только в тесте талантов.
- Produces:
  - `spells.CATALOG`, `spells.byKey[key]`, `spells.rank(key, id)`, `spells.KEYS` (массив ключей в порядке каталога);
  - `talents.KEYS`, `talents.read(numTabs, numTalents, info)`.

Решения:
- **Длительности**, которых нет в выгрузке (нужен `SpellDuration.dbc`), взяты из подсказок 3.3.5:
  - Flame Shock — 12 с;
  - дебафф Stormstrike — 12 с, 4 заряда, +20% к природному урону;
  - Lightning Shield — 600 с, 3 заряда;
  - Magma Totem — 20 с, удар каждые 2 с;
  - Searing Totem — 60 с, выстрел каждые 2,5 с;
  - Fire Elemental — 120 с.

  Период Searing Totem проверить в игре по боевому логу первым же прогоном и поправить в каталоге.
- **Общая перезарядка:**
  - тотемы (Searing, Magma, Fire Elemental) — 1,0 с;
  - Call of the Elements, Shamanistic Rage — 1,5 с (в DBC `StartRecoveryCategory = 133`, то есть на общем кулдауне).

  Значения берутся из `gcdMs` данных, а не пишутся вручную.

- [ ] **Step 1: Написать падающие тесты**

`spec/spells_spec.lua`:
```lua
local spells = require("spells")

describe("spells catalog", function()
  it("contains exactly the 15 contract action keys", function()
    local expected = { "stormstrike", "lavaLash", "earthShock", "flameShock", "frostShock", "lightningBolt",
      "chainLightning", "searingTotem", "magmaTotem", "fireNova", "fireElemental", "callOfElements",
      "lightningShield", "shamanisticRage", "feralSpirit" }
    assert.are.equal(#expected, #spells.CATALOG)
    for _, k in ipairs(expected) do assert.is_not_nil(spells.byKey[k], k) end
    assert.are.same(expected, spells.KEYS)
  end)

  it("builds rank id lists from generated data", function()
    local lb = spells.byKey.lightningBolt
    assert.are.equal(403, lb.ranks[1])
    assert.are.equal(49238, lb.ranks[#lb.ranks])
    assert.are.equal(49238, spells.rank("lightningBolt", 49238).id)
    assert.is_nil(spells.rank("lightningBolt", 12345))
  end)

  it("marks shocks as sharing one cooldown and weapon strikes by hand", function()
    for _, k in ipairs({ "earthShock", "flameShock", "frostShock" }) do
      assert.are.equal("shock", spells.byKey[k].sharedCd, k)
      assert.are.equal(6, spells.byKey[k].cd, k)
    end
    assert.are.equal("both", spells.byKey.stormstrike.hands)
    assert.are.equal("oh", spells.byKey.lavaLash.hands)
    assert.is_true(spells.byKey.stormstrike.weapon)
    assert.is_nil(spells.byKey.earthShock.weapon)
  end)

  it("takes gcd and cooldown from the client data", function()
    assert.are.equal(1.0, spells.byKey.magmaTotem.gcd)
    assert.are.equal(1.0, spells.byKey.searingTotem.gcd)
    assert.are.equal(1.5, spells.byKey.shamanisticRage.gcd)
    assert.are.equal(8, spells.byKey.stormstrike.cd)
    assert.are.equal(10, spells.byKey.fireNova.cd)
    assert.are.equal(0, spells.byKey.lightningBolt.cd)
    assert.are.equal(2.5, spells.byKey.lightningBolt.castBase)
    assert.are.equal(2.0, spells.byKey.chainLightning.castBase)
  end)

  it("describes totems, dots and shields for the model", function()
    assert.are.equal("fire", spells.byKey.magmaTotem.totem)
    assert.are.same({ 20, 2 }, { spells.byKey.magmaTotem.duration, spells.byKey.magmaTotem.period })
    assert.are.same({ 12, 3 }, { spells.byKey.flameShock.duration, spells.byKey.flameShock.period })
    assert.are.same({ 12, 4, 20 }, { spells.byKey.stormstrike.duration, spells.byKey.stormstrike.charges, spells.byKey.stormstrike.bonus })
    assert.are.equal(3, spells.byKey.lightningShield.charges)
    assert.is_true(spells.byKey.fireNova.requiresFireTotem)
    assert.are.equal(3, spells.byKey.chainLightning.maxTargets)
  end)

  it("uses 3.3.5 icon paths only", function()
    for _, s in ipairs(spells.CATALOG) do
      assert.is_truthy(s.icon:match("^Interface\\Icons\\[%w_]+$"), s.key)
    end
  end)
end)
```

`spec/talents_spec.lua`:
```lua
local W = require("wow_mock")
local talents = require("talents")

describe("talents", function()
  it("reads ranks by talent name from any tab and position", function()
    W.install({ talents = {
      [1] = { { name = "Convection", rank = 5 }, { name = "Concussion", rank = 5 }, { name = "Call of Flame", rank = 3 } },
      [2] = { { name = "Ancestral Knowledge", rank = 2 }, { name = "Maelstrom Weapon", rank = 5 }, { name = "Flurry", rank = 5 } },
      [3] = { { name = "Improved Healing Wave", rank = 5 } },
    } })
    local t = talents.read(GetNumTalentTabs, GetNumTalents, GetTalentInfo)
    assert.are.equal(5, t.concussion)
    assert.are.equal(3, t.callOfFlame)
    assert.are.equal(5, t.maelstromWeapon)
    assert.are.equal(5, t.flurry)
    assert.are.equal(0, t.stormstrike)
    assert.is_nil(t.improvedHealingWave)
  end)

  it("returns zero for every known key when nothing is learned", function()
    W.install({ talents = {} })
    local t = talents.read(GetNumTalentTabs, GetNumTalents, GetTalentInfo)
    for _, k in ipairs(talents.KEYS) do assert.are.equal(0, t[k.key], k.key) end
  end)

  it("has unique keys and names", function()
    local keys, names = {}, {}
    for _, k in ipairs(talents.KEYS) do
      assert.is_nil(keys[k.key], k.key); keys[k.key] = true
      assert.is_nil(names[k.name], k.name); names[k.name] = true
    end
  end)
end)
```

- [ ] **Step 2: Запустить — тесты падают**

Run: `docker compose run --rm test busted spec/spells_spec.lua spec/talents_spec.lua`
Expected: FAIL — `module 'spells' not found`, `module 'talents' not found`.

- [ ] **Step 3: Написать `src/spells.lua`**

```lua
local data = require("spells_data")

local M = {}

local I = "Interface\\Icons\\"

-- Static facts the client data does not carry. Numbers from the 3.3.5a tooltips.
M.CATALOG = {
  { key = "stormstrike", name = "Stormstrike", school = "physical", weapon = true, hands = "both",
    duration = 12, charges = 4, bonus = 20, icon = I .. "Ability_Shaman_Stormstrike" },
  { key = "lavaLash", name = "Lava Lash", school = "fire", weapon = true, hands = "oh",
    icon = I .. "Ability_Shaman_Lavalash" },
  { key = "earthShock", name = "Earth Shock", school = "nature", sharedCd = "shock",
    icon = I .. "Spell_Nature_EarthShock" },
  { key = "flameShock", name = "Flame Shock", school = "fire", sharedCd = "shock", duration = 12, period = 3,
    icon = I .. "Spell_Fire_FlameShock" },
  { key = "frostShock", name = "Frost Shock", school = "frost", sharedCd = "shock",
    icon = I .. "Spell_Frost_FrostShock" },
  { key = "lightningBolt", name = "Lightning Bolt", school = "nature", castBase = 2.5,
    icon = I .. "Spell_Nature_Lightning" },
  { key = "chainLightning", name = "Chain Lightning", school = "nature", castBase = 2.0, maxTargets = 3,
    icon = I .. "Spell_Nature_ChainLightning" },
  { key = "searingTotem", name = "Searing Totem", school = "fire", totem = "fire", duration = 60, period = 2.5,
    icon = I .. "Spell_Fire_SearingTotem" },
  { key = "magmaTotem", name = "Magma Totem", school = "fire", totem = "fire", duration = 20, period = 2,
    maxTargets = 20, icon = I .. "Spell_Fire_SelfDestruct" },
  { key = "fireNova", name = "Fire Nova", school = "fire", requiresFireTotem = true, maxTargets = 20,
    icon = I .. "Spell_Fire_SealOfFire" },
  { key = "fireElemental", name = "Fire Elemental Totem", school = "fire", totem = "fire", duration = 120,
    icon = I .. "Spell_Fire_Elemental_Totem" },
  { key = "callOfElements", name = "Call of the Elements", school = "nature",
    icon = I .. "Spell_Shaman_DropAll_01" },
  { key = "lightningShield", name = "Lightning Shield", school = "nature", duration = 600, charges = 3,
    icon = I .. "Spell_Nature_LightningShield" },
  { key = "shamanisticRage", name = "Shamanistic Rage", school = "physical", duration = 15,
    icon = I .. "Spell_Nature_ShamanRage" },
  { key = "feralSpirit", name = "Feral Spirit", school = "physical", duration = 45,
    icon = I .. "Spell_Shaman_FeralSpirit" },
}

M.byKey = {}
M.KEYS = {}

for i, s in ipairs(M.CATALOG) do
  local ranks = assert(data[s.key], "no spells_data for " .. s.key)
  local top = ranks[#ranks]
  s.ranks = {}
  for j, r in ipairs(ranks) do s.ranks[j] = r.id end
  s.gcd = top.gcdMs / 1000
  s.cd = top.cdMs / 1000
  s.castBase = s.castBase or 0
  M.byKey[s.key] = s
  M.KEYS[i] = s.key
end

function M.rank(key, id)
  for _, r in ipairs(data[key] or {}) do
    if r.id == id then return r end
  end
  return nil
end

return M
```

- [ ] **Step 4: Написать `src/talents.lua`**

```lua
local M = {}

-- Talents that change enhancement damage, costs or cooldowns. Matched by English name,
-- so tab and position do not matter (the client is enGB).
M.KEYS = {
  { key = "convection", name = "Convection" },
  { key = "concussion", name = "Concussion" },
  { key = "callOfFlame", name = "Call of Flame" },
  { key = "elementalDevastation", name = "Elemental Devastation" },
  { key = "reverberation", name = "Reverberation" },
  { key = "elementalFocus", name = "Elemental Focus" },
  { key = "elementalFury", name = "Elemental Fury" },
  { key = "improvedFireNova", name = "Improved Fire Nova" },
  { key = "elementalPrecision", name = "Elemental Precision" },
  { key = "stormEarthAndFire", name = "Storm, Earth and Fire" },
  { key = "enhancingTotems", name = "Enhancing Totems" },
  { key = "ancestralKnowledge", name = "Ancestral Knowledge" },
  { key = "thunderingStrikes", name = "Thundering Strikes" },
  { key = "improvedShields", name = "Improved Shields" },
  { key = "elementalWeapons", name = "Elemental Weapons" },
  { key = "shamanisticFocus", name = "Shamanistic Focus" },
  { key = "flurry", name = "Flurry" },
  { key = "weaponMastery", name = "Weapon Mastery" },
  { key = "dualWieldSpecialization", name = "Dual Wield Specialization" },
  { key = "dualWield", name = "Dual Wield" },
  { key = "stormstrike", name = "Stormstrike" },
  { key = "staticShock", name = "Static Shock" },
  { key = "lavaLash", name = "Lava Lash" },
  { key = "improvedStormstrike", name = "Improved Stormstrike" },
  { key = "mentalQuickness", name = "Mental Quickness" },
  { key = "mentalDexterity", name = "Mental Dexterity" },
  { key = "unleashedRage", name = "Unleashed Rage" },
  { key = "shamanisticRage", name = "Shamanistic Rage" },
  { key = "maelstromWeapon", name = "Maelstrom Weapon" },
  { key = "feralSpirit", name = "Feral Spirit" },
  { key = "spiritWeapons", name = "Spirit Weapons" },
}

local byName = {}
for _, k in ipairs(M.KEYS) do byName[k.name] = k.key end

function M.read(numTabs, numTalents, info)
  local out = {}
  for _, k in ipairs(M.KEYS) do out[k.key] = 0 end
  for tab = 1, numTabs() or 0 do
    for i = 1, numTalents(tab) or 0 do
      local name, _, _, _, rank = info(tab, i)
      local key = name and byName[name]
      if key then out[key] = rank or 0 end
    end
  end
  return out
end

return M
```

- [ ] **Step 5: Запустить тесты — проходят**

Run: `docker compose run --rm test busted spec/spells_spec.lua spec/talents_spec.lua`
Expected: PASS, 9 successes.

- [ ] **Step 6: Прогнать всё, что есть**

Run: `docker compose run --rm test busted`
Expected: PASS, `0 failures`.

- [ ] **Step 7: Commit**

```bash
git add src/spells.lua src/talents.lua spec/spells_spec.lua spec/talents_spec.lua
git commit -m "Каталог заклинаний шамана и чтение талантов по имени"
```
