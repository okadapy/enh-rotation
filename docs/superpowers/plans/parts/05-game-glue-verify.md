# Часть 5. Связь с игрой, лента, сборка, проверка (задачи 12–16)

## Contract additions

Добавления к контракту из основного файла плана. Остальные части плана должны им не противоречить.

1. **`snapshot`**
   - `snapshot.scan() -> cache` — кэш имён, выученных рангов и талантов. `cache.known[key] = { id, rank }`, `cache.names[key]`, `cache.keyByName[name]`, `cache.buffNames`, `cache.debuffNames`, `cache.totemNames`, `cache.enchantNames`, `cache.talents`. `snapshot.build(ctx)` берёт `ctx.cache`; если его нет, вызывает `scan()` и кладёт результат в `ctx.cache`.
   - `snapshot.auras(unit, filter, names, mineOnly, now) -> { [key] = { count, remains } }` — нужен `runtime`, чтобы узнать стаки Maelstrom в момент начала каста.
   - `ctx.attacking` (`true`/`false`/`nil`) переопределяет `S.swing.attacking`. Флаг ставит `runtime` по `PLAYER_ENTER_COMBAT`/`PLAYER_LEAVE_COMBAT`. Если `nil`, берётся значение из `swing:state`.
2. **`S.totems.fire.kind`** может быть `"other"` — стоит огненный тотем, но не Searing, не Magma и не Fire Elemental (например Flametongue Totem). Fire Nova при нём доступна.
3. **`S.weapons.*.min/max`** — ровно то, что отдаёт `UnitDamage("player")`. **Бонус силы атаки уже включён, у левой руки уже учтён штраф.** Модуль `damage` не должен добавлять `AP/14*speed` и штраф левой руки повторно.
4. **`spells.CATALOG[i]`**
   - `ranks` — строго по возрастанию ранга, `ranks[1]` — ранг 1;
   - `name` — английское базовое имя, как его отдаёт `GetSpellInfo`;
   - `icon` — путь `Interface\\Icons\\...`.
5. **`runtime`**
   - `runtime.start(config, env)` кладёт состояние в `env.rt`.
   - Публичные функции (их используют тесты): `runtime.validPlan(plan)`, `runtime.alert(S)`, `runtime.lustReady(S, now)`, `runtime.signature(plan, counters)`, `runtime.onEvent(rt, event, ...)`, `runtime.update(rt, dt)`, `runtime.mark(rt, kind, key)`.
   - `runtime.MODES = { "auto", "solo", "group", "raid", "pvp" }` — индексы опции `mode`.
6. **`timeline`**
   - Чистые функции: `timeline.options(opts)`, `timeline.xOf(t, o)`, `timeline.swingTimes(S, seconds)`, `timeline.castWindow(S, swings) -> a, b | nil`, `timeline.layout(plan, S, opts, elapsed)`.
   - Поля объекта: `tl.frame`, `tl.icons[i]`, `tl.glow`, `tl.alert`, `tl.reason`, `tl.cur[key] = x`, `tl:tick(dt)`.
7. **`recorder`**: `recorder.KEY = "enhrotSnapshots"`, `recorder.MIN_GAP = 2`.
8. **`talents.standard(level) -> { key = rank }`** — необязательная функция: типовой энх-билд на этом уровне. Её использует `spec/support/scenario.lua`. Если функции нет, `S.talents = {}`.
9. **`swing`**: `runtime` присваивает `c.saved = env.saved.swing` сразу после `swing.new()`. Модуль `swing` должен читать `self.saved` при каждом обращении, а не копировать его в `new()`.
10. **Команды `/enhrot debug` не будет.** WeakAuras в своей песочнице блокирует `SlashCmdList` (`blockedTables`). Вместо неё — опция `printDebug`: при каждой смене первого действия в чат печатаются план и счётчики. Это отступление от спецификации §9.
11. **Аура:**
    - группа `EnhRot`, хост `EnhRot Timeline` (регион `texture`, прозрачный);
    - событие показа хоста — `ENHROT_SHOW`, его шлёт `runtime` при первом обновлении и после `PLAYER_ENTERING_WORLD`.
12. **Моки тестов:**
    - `spec/support/game_mock.lua` — API клиента 3.3.5a и объекты интерфейса для `snapshot`, `timeline`, `runtime` и сборки;
    - `spec/support/scenario.lua` — сборщик контрактного `S` по уровню для проверочных спеков.

    Оба независимы от `wow_mock.lua` из части 1: имена его функций здесь не используются.
13. **`build.MODULES`** — порядок загрузки: `spells_data, spells, talents, swing, enemies, ttd, damage, model, value, search, planner, snapshot, timeline, recorder, runtime`. Если в других частях появились ещё модули (например `util`), их вставляют перед первым модулем, который их использует. Тест `build_spec` падает, если файл в `src/` не попал в список.
14. **`UNIT_POWER` не регистрируется.** В 3.3.5a его нет, и `RegisterEvent` падает с ошибкой. Вместо него — `UNIT_MANA`.
15. **`UNIT_SPELLCAST_SENT` не используется.** «Летящее» заклинание отмечается по `UNIT_SPELLCAST_SUCCEEDED`: у мгновенных он приходит примерно через время пинга. Снимается по `SPELL_AURA_APPLIED/REFRESH/APPLIED_DOSE` от игрока или через 1 с.

---

### Task 12: Снимок ситуации из API игры (`snapshot`)

**Files:**
- Create: `spec/support/game_mock.lua`
- Create: `src/snapshot.lua`
- Test: `spec/snapshot_spec.lua`

**Interfaces:**
- Consumes:
  - `spells.CATALOG` (`key`, `name`, `ranks` по возрастанию), `spells.byKey`;
  - `talents.read(getTalentInfo) -> { key = rank }`;
  - `ctx.swing:state(now)`, `ctx.enemies:counts(now) -> melee, nearby`, `ctx.ttd:add(now, guid, hpPct)`, `ctx.ttd:estimate(now, guid)`.
- Produces:
  - `snapshot.scan() -> cache`, `snapshot.build(ctx) -> S` (контрактный `S`);
  - `snapshot.auras(unit, filter, names, mineOnly, now)`;
  - вспомогательные `snapshot.guessHealth(level, classification)`, `snapshot.mode(override)`, `snapshot.range(cache)`, `snapshot.totem(slot, names, now)`;
  - константы `snapshot.SLOT = { fire = 1, earth = 2, water = 3, air = 4 }`.
  - Мок `game_mock`: `G.install(cfg)`, `G.frame(kind, name)`, `G.sent`, `G.printed`, `G.cfg`.

Проверенные факты API 3.3.5a, на которые опирается код:
- `UnitAura(unit, i, filter)` → `name, rank, icon, count, debuffType, duration, expirationTime, unitCaster, isStealable, shouldConsolidate, spellId`.
- `GetTotemInfo(slot)` → `haveTotem, totemName, startTime, duration, icon`. Слоты: огонь 1, земля 2, вода 3, воздух 4.
- `GetWeaponEnchantInfo()` → `hasMH, mhExpiration, mhCharges, hasOH, ohExpiration, ohCharges`. ID чар в 3.3.5a не отдаётся, поэтому вид чар читается из подсказки оружия. Строки подсказки ищем через `tip:GetRegions()` — без `_G`.
- `GetNetStats()` → `bandwidthIn, bandwidthOut, latency`: три значения, задержка в мс.
- `UnitCastingInfo("player")` → `name, subText, text, texture, startTime(ms), endTime(ms), isTradeSkill, castID, notInterruptible`.
- `GetCombatRatingBonus`: `CR_HIT_MELEE = 6`, `CR_HIT_SPELL = 8`, `CR_HASTE_MELEE = 18`, `CR_HASTE_SPELL = 20`. `UnitSpellHaste` в 3.3.5a нет. Поэтому хаст заклинаний считается по фактическому времени каста Lightning Bolt (учитывает баффы), а если это невозможно — по рейтингу.
- `GetSpellInfo("Имя")` в 3.3.5a возвращает данные, только если заклинание есть в книге, и отдаёт его высший ранг.

- [ ] **Step 1: Мок API клиента**

Создать `spec/support/game_mock.lua`:

```lua
local spells = require("spells")

local G = {}

G.EXTRA_NAMES = {
  [53817] = "Maelstrom Weapon", [49281] = "Lightning Shield", [16280] = "Flurry",
  [30823] = "Shamanistic Rage", [2825] = "Bloodlust", [32182] = "Heroism", [16166] = "Elemental Mastery",
  [8050] = "Flame Shock", [17364] = "Stormstrike",
  [3599] = "Searing Totem", [8190] = "Magma Totem", [2894] = "Fire Elemental Totem",
  [8232] = "Windfury Weapon", [8024] = "Flametongue Weapon", [8017] = "Rockbiter Weapon",
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
  function r:ClearAllPoints() self.points = {}; self.point = nil end
  function r:SetWidth(w) self.w = w end
  function r:SetHeight(h) self.h = h end
  function r:GetWidth() return self.w end
  function r:GetHeight() return self.h end
  function r:Show() self.shown = true end
  function r:Hide() self.shown = false end
  function r:IsShown() return self.shown end
  function r:SetAlpha(a) self.alpha = a end
  function r:GetObjectType() return kind end
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
  return f
end

function G.frame(kind, name)
  local f = region(kind or "Frame")
  f.name, f.events, f.scripts, f.children = name, {}, {}, {}
  function f:RegisterEvent(e)
    if e == "UNIT_POWER" then error("Attempt to register unknown event UNIT_POWER") end
    self.events[e] = true
  end
  function f:UnregisterAllEvents() self.events = {} end
  function f:SetScript(k, fn) self.scripts[k] = fn end
  function f:GetScript(k) return self.scripts[k] end
  function f:SetScale(s) self.scale = s end
  function f:CreateTexture() local t = G.texture(); self.children[#self.children + 1] = t; return t end
  function f:CreateFontString() local t = G.fontString(); self.children[#self.children + 1] = t; return t end
  function f:GetRegions() return unpack(self.children) end
  function f:SetOwner(owner, anchor) self.owner = owner; self.anchor = anchor end
  function f:ClearLines() self.children = {} end
  function f:SetInventoryItem(_, slot)
    for _, line in ipairs(((G.cfg.tooltip or {})[slot]) or {}) do
      local fs = G.fontString()
      fs.text = line
      self.children[#self.children + 1] = fs
    end
  end
  return f
end

-- cfg: now, level, mana, manaMax, int, hp, hpMax, ap, sp={[school]=n}, crit, spellCrit, ratings={[cr]=n}, hitMod,
-- speed={mh,oh}, damage={minMH,maxMH,minOH,maxOH}, latencyMs, raid, party, moving, inCombat,
-- known={[id]=true}, bookOnly={[id]=true}, costs={[name]=n}, castMs={[name]=ms}, cooldowns={[name]={start,dur}},
-- inRange={[name]=0|1}, interact, auras={[unit]={HELPFUL={...},HARMFUL={...}}} (name,count,expires,caster,id),
-- target={exists,enemy,level,hp,hpMax,guid,classification,dead,player}, totems={[slot]={name,start,dur}},
-- enchants={mh=bool,oh=bool}, tooltip={[16]={lines},[17]={lines}}, casting={name,startMs,endMs}, talents={[tab]={{name,rank}}}
function G.install(cfg)
  cfg = cfg or {}
  G.cfg = cfg
  G.sent, G.printed = {}, {}
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
    local name = byId[id]
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
    if u == "player" then return nil end
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
  _G.GetUnitSpeed = function() return cfg.moving and 7 or 0 end
  _G.UnitAffectingCombat = function() return cfg.inCombat ~= false and 1 or nil end
  _G.UnitCastingInfo = function(u)
    local c = u == "player" and cfg.casting
    if not c then return nil end
    return c.name, nil, nil, "icon", c.startMs, c.endMs, false, 1, false
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
  _G.CreateFrame = function(kind, name)
    local f = G.frame(kind, name)
    if name then _G[name] = f end
    return f
  end
  _G.UIParent = G.frame("Frame", "UIParent")
  _G.WorldFrame = G.frame("Frame", "WorldFrame")
  _G.WeakAuras = { ScanEvents = function(...) G.sent[#G.sent + 1] = { ... } end }
  _G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    G.printed[#G.printed + 1] = table.concat(parts, " ")
  end
  _G.EnhRotEngineFrame = nil
  _G.EnhRotScanTip = nil
  return cfg
end

return G
```

- [ ] **Step 2: Написать падающие тесты**

Создать `spec/snapshot_spec.lua`:

```lua
local G = require("game_mock")
local snapshot = require("snapshot")
local spells = require("spells")

local function ranks(key) return spells.byKey[key].ranks end
local function top(key) local r = ranks(key); return r[#r] end

local function ctx(extra)
  local c = {
    swing = { state = function() return { attacking = true, mh = { next = 1.1, speed = 2.6 }, oh = { next = 0.3, speed = 2.6 }, resetByInstant = {} } end },
    enemies = { counts = function() return 0, 2 end },
    ttd = { add = function() end, estimate = function() return 42 end },
    inflight = {}, mode = "auto",
  }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end

local function install(cfg)
  cfg.target = cfg.target or { level = 80, hp = 5000, hpMax = 10000, guid = "Creature-7" }
  return G.install(cfg)
end

describe("snapshot", function()
  it("picks the highest known rank and skips unknown spells", function()
    local lb = ranks("lightningBolt")
    install({ known = { [lb[1]] = true, [lb[2]] = true, [lb[3]] = true } })
    local S = snapshot.build(ctx())
    assert.are.equal(lb[3], S.spells.lightningBolt.id)
    assert.are.equal(3, S.spells.lightningBolt.rank)
    assert.is_nil(S.spells.stormstrike)
  end)

  it("falls back to the spellbook when IsSpellKnown misses a talent spell", function()
    install({ bookOnly = { [17364] = true } })
    local S = snapshot.build(ctx())
    assert.are.equal(17364, S.spells.stormstrike.id)
  end)

  it("reads Maelstrom stacks, shield charges and only the player's debuffs", function()
    install({
      known = { [top("lightningBolt")] = true },
      auras = {
        player = { HELPFUL = { { name = "Maelstrom Weapon", count = 4, expires = 106 }, { name = "Lightning Shield", count = 3, expires = 700 } } },
        target = { HARMFUL = { { name = "Flame Shock", expires = 109, caster = "player" },
                               { name = "Stormstrike", count = 2, expires = 110, caster = "raid3" } } },
      },
    })
    local S = snapshot.build(ctx())
    assert.are.equal(4, S.buffs.mw.stacks)
    assert.are.near(6, S.buffs.mw.remains, 1e-9)
    assert.are.equal(3, S.buffs.ls.charges)
    assert.are.near(9, S.target.fs, 1e-9)
    assert.are.equal(0, S.target.ss.charges)
  end)

  it("reads weapon imbues from the weapon tooltip", function()
    install({ enchants = { mh = true, oh = true },
              tooltip = { [16] = { "Some Axe", "Windfury 8 (30 min)" }, [17] = { "Other Axe", "Flametongue 10 (30 min)" } } })
    local S = snapshot.build(ctx())
    assert.are.equal("wf", S.weapons.mh.enchant)
    assert.are.equal("ft", S.weapons.oh.enchant)
  end)

  it("has no off-hand with a two-hander and no imbue without an enchant", function()
    install({ speed = { 3.5, nil }, enchants = {} })
    local S = snapshot.build(ctx({ swing = { state = function() return { attacking = true, mh = { next = 1, speed = 3.5 } } end } }))
    assert.is_nil(S.weapons.oh)
    assert.is_nil(S.weapons.mh.enchant)
    assert.is_nil(S.swing.oh)
    assert.are.same({}, S.swing.resetByInstant)
  end)

  it("classifies fire totems and reads the water totem", function()
    install({ totems = { [1] = { "Magma Totem VII", 95, 20 }, [3] = { "Mana Spring Totem VIII", 50, 300 } } })
    local S = snapshot.build(ctx())
    assert.are.equal("magma", S.totems.fire.kind)
    assert.are.near(15, S.totems.fire.remains, 1e-9)
    assert.are.near(250, S.totems.water.remains, 1e-9)
    install({ totems = { [1] = { "Fire Elemental Totem", 90, 120 } } })
    assert.are.equal("fireElemental", snapshot.build(ctx()).totems.fire.kind)
    install({ totems = { [1] = { "Totem of Wrath IV", 90, 300 } } })
    assert.are.equal("other", snapshot.build(ctx()).totems.fire.kind)
    install({})
    assert.is_nil(snapshot.build(ctx()).totems.fire.kind)
  end)

  it("guesses mob health when the client only gives percent", function()
    install({ target = { level = 80, hp = 50, hpMax = 100 } })
    local S = snapshot.build(ctx())
    assert.is_true(S.target.guessed)
    assert.are.equal(12000, S.target.hpMax)
    assert.are.equal(6000, S.target.hp)
    install({ target = { level = 80, hp = 5000, hpMax = 20000 } })
    S = snapshot.build(ctx())
    assert.is_false(S.target.guessed)
    assert.are.equal(20000, S.target.hpMax)
    assert.are.equal(42, S.target.ttd)
  end)

  it("guesses the level of skull targets", function()
    install({ level = 80, target = { level = -1, hp = 1e6, hpMax = 1e6 } })
    local S = snapshot.build(ctx())
    assert.are.equal(83, S.target.level)
    assert.is_true(S.target.guessed)
  end)

  it("returns an empty target when there is none", function()
    G.install({})
    local S = snapshot.build(ctx())
    assert.is_false(S.target.exists)
    assert.are.equal("far", S.target.range)
  end)

  it("picks the mode from the group and honours the override", function()
    install({ raid = 10 }); assert.are.equal("raid", snapshot.build(ctx()).mode)
    install({ party = 2 }); assert.are.equal("group", snapshot.build(ctx()).mode)
    install({}); assert.are.equal("solo", snapshot.build(ctx()).mode)
    install({}); assert.are.equal("group", snapshot.build(ctx({ mode = "group" })).mode)
  end)

  it("measures range with the shortest spell that reaches", function()
    local known = { [top("stormstrike")] = true, [top("earthShock")] = true, [top("lightningBolt")] = true }
    install({ known = known, inRange = { Stormstrike = 0, ["Earth Shock"] = 1, ["Lightning Bolt"] = 1 } })
    assert.are.equal("20", snapshot.build(ctx()).target.range)
    install({ known = known, inRange = { Stormstrike = 1 } })
    assert.are.equal("melee", snapshot.build(ctx()).target.range)
    install({ known = known, inRange = { Stormstrike = 0, ["Earth Shock"] = 0, ["Lightning Bolt"] = 0 } })
    assert.are.equal("far", snapshot.build(ctx()).target.range)
    install({ known = { [top("earthShock")] = true, [top("lightningBolt")] = true }, interact = true, inRange = {} })
    assert.are.equal("melee", snapshot.build(ctx()).target.range)
  end)

  it("derives spell haste from the real Lightning Bolt cast time", function()
    install({ known = { [top("lightningBolt")] = true }, castMs = { ["Lightning Bolt"] = 2000 } })
    local S = snapshot.build(ctx())
    assert.are.near(1.25, S.player.spellHaste, 1e-9)
    assert.are.near(1.2, S.gcd, 1e-9)
    install({ known = { [top("lightningBolt")] = true }, castMs = { ["Lightning Bolt"] = 1200 },
              auras = { player = { HELPFUL = { { name = "Maelstrom Weapon", count = 2, expires = 110 } } } } })
    assert.are.near(1.25, snapshot.build(ctx()).player.spellHaste, 1e-9)
    install({ known = { [top("lightningBolt")] = true }, castMs = { ["Lightning Bolt"] = 0 }, ratings = { [20] = 10 },
              auras = { player = { HELPFUL = { { name = "Maelstrom Weapon", count = 5, expires = 110 } } } } })
    assert.are.near(1.10, snapshot.build(ctx()).player.spellHaste, 1e-9)
  end)

  it("separates spell cooldowns from the global cooldown", function()
    install({ known = { [top("stormstrike")] = true, [top("earthShock")] = true, [top("lightningBolt")] = true },
              castMs = { ["Lightning Bolt"] = 2500 },
              cooldowns = { Stormstrike = { 98, 8 }, ["Earth Shock"] = { 99.5, 1.5 }, ["Lightning Bolt"] = { 99.5, 1.5 } } })
    local S = snapshot.build(ctx())
    assert.are.near(6, S.spells.stormstrike.cd, 1e-9)
    assert.are.equal(0, S.spells.earthShock.cd)
    assert.are.near(1.0, S.gcdRemains, 1e-9)
  end)

  it("reads the current cast, latency and player stats", function()
    install({ known = { [top("lightningBolt")] = true }, casting = { name = "Lightning Bolt", startMs = 99500, endMs = 101000 },
              latencyMs = 80, ap = 3000, sp = { [3] = 500, [4] = 700 }, crit = 25, spellCrit = 15, ratings = { [6] = 3 }, hitMod = 2 })
    local S = snapshot.build(ctx())
    assert.are.near(1.0, S.castRemains, 1e-9)
    assert.are.near(0.18, S.latency, 1e-9)
    assert.are.equal(3000, S.player.ap)
    assert.are.equal(700, S.player.spNature)
    assert.are.equal(500, S.player.spFire)
    assert.are.near(0.25, S.player.meleeCrit, 1e-9)
    assert.are.near(0.05, S.player.meleeHit, 1e-9)
    assert.are.equal(4396, S.player.baseMana)
  end)

  it("turns in-flight deadlines into remains and drops expired ones", function()
    install({})
    local c = ctx({ inflight = { flameShock = 100.6, earthShock = 99.0 } })
    local S = snapshot.build(c)
    assert.are.near(0.6, S.inflight.flameShock, 1e-9)
    assert.is_nil(S.inflight.earthShock)
    assert.is_nil(c.inflight.earthShock)
  end)

  it("lets the runtime override the auto-attack flag and counts the target as an enemy", function()
    install({ known = { [top("stormstrike")] = true }, inRange = { Stormstrike = 1 } })
    local S = snapshot.build(ctx({ attacking = false }))
    assert.is_false(S.swing.attacking)
    assert.are.equal(1, S.enemies.melee)
    assert.are.equal(2, S.enemies.nearby)
  end)

  it("reuses the scan cache between builds", function()
    install({})
    local c = ctx()
    snapshot.build(c)
    local cache = c.cache
    snapshot.build(c)
    assert.are.equal(cache, c.cache)
  end)
end)
```

- [ ] **Step 3: Убедиться, что тесты падают**

Run: `docker compose run --rm test busted spec/snapshot_spec.lua`
Expected: FAIL — `module 'snapshot' not found`.

- [ ] **Step 4: Реализация**

Создать `src/snapshot.lua`:

```lua
local spells = require("spells")
local talents = require("talents")

local M = {}

M.BUFFS = { [53817] = "mw", [49281] = "ls", [16280] = "flurry", [30823] = "rage", [2825] = "lust", [32182] = "lust", [16166] = "em" }
M.DEBUFFS = { [8050] = "fs", [17364] = "ss" }
M.TOTEMS = { [2894] = "fireElemental", [8190] = "magma", [3599] = "searing" }
M.ENCHANTS = { [8232] = "wf", [8024] = "ft", [8017] = "rb" }
M.SLOT = { fire = 1, earth = 2, water = 3, air = 4 }
M.LB_BASE = { 1.5, 2.0 }
M.ENCHANT_RESCAN = 5
M.RANGE_PROBES = { { "stormstrike", "melee" }, { "lavaLash", "melee" }, { "earthShock", "20" }, { "lightningBolt", "30" } }
M.HP_BY_LEVEL = { { 1, 42 }, { 10, 200 }, { 20, 600 }, { 30, 1200 }, { 40, 2000 }, { 50, 3500 }, { 60, 4500 }, { 70, 7000 }, { 80, 12000 }, { 83, 14000 } }
M.BASE_MANA = { { 1, 55 }, { 10, 185 }, { 20, 410 }, { 30, 635 }, { 40, 860 }, { 50, 1085 }, { 60, 1520 }, { 70, 2678 }, { 80, 4396 } }
M.CLASS_MULT = { normal = 1, trivial = 1, minus = 0.5, rare = 1.5, elite = 3, rareelite = 3, worldboss = 100 }

local CR_HIT_MELEE, CR_HIT_SPELL, CR_HASTE_MELEE, CR_HASTE_SPELL = 6, 8, 18, 20

local function interp(t, x)
  if x <= t[1][1] then return t[1][2] end
  for i = 2, #t do
    if x <= t[i][1] then
      local a, b = t[i - 1], t[i]
      return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1])
    end
  end
  return t[#t][2]
end

local function namesOf(ids, strip)
  local out = {}
  for id, key in pairs(ids) do
    local name = GetSpellInfo(id)
    if name then
      if strip then name = (name:gsub(" Weapon$", "")) end
      out[name] = key
    end
  end
  return out
end

function M.scan()
  local c = {
    names = {}, keyByName = {}, known = {},
    buffNames = namesOf(M.BUFFS), debuffNames = namesOf(M.DEBUFFS),
    totemNames = namesOf(M.TOTEMS), enchantNames = namesOf(M.ENCHANTS, true),
    enchant = {}, enchantAt = -math.huge, enchantSig = nil,
  }
  for _, meta in ipairs(spells.CATALOG) do
    local name = GetSpellInfo(meta.ranks[1])
    if name then
      c.names[meta.key] = name
      c.keyByName[name] = meta.key
      for i = #meta.ranks, 1, -1 do
        if IsSpellKnown(meta.ranks[i]) then
          c.known[meta.key] = { id = meta.ranks[i], rank = i }
          break
        end
      end
      if not c.known[meta.key] then
        local _, rankText = GetSpellInfo(name)
        if rankText then
          local r = math.min(#meta.ranks, tonumber(rankText:match("%d+")) or 1)
          c.known[meta.key] = { id = meta.ranks[r], rank = r }
        end
      end
    end
  end
  c.talents = talents.read(GetTalentInfo)
  return c
end

function M.auras(unit, filter, names, mineOnly, now)
  local out = {}
  for i = 1, 40 do
    local name, _, _, count, _, _, expires, caster = UnitAura(unit, i, filter)
    if not name then break end
    local key = names[name]
    if key and (not mineOnly or caster == "player") then
      local remains = (expires and expires > 0) and math.max(0, expires - now) or 600
      local prev = out[key]
      if not prev or remains > prev.remains then out[key] = { count = count or 0, remains = remains } end
    end
  end
  return out
end

function M.tooltip()
  return EnhRotScanTip or CreateFrame("GameTooltip", "EnhRotScanTip", nil, "GameTooltipTemplate")
end

function M.enchantOf(tip, slot, names)
  tip:SetOwner(WorldFrame, "ANCHOR_NONE")
  tip:ClearLines()
  tip:SetInventoryItem("player", slot)
  local regions = { tip:GetRegions() }
  for _, r in ipairs(regions) do
    if r:GetObjectType() == "FontString" and r:IsShown() then
      local text = r:GetText()
      if text then
        for base, kind in pairs(names) do
          if text:find(base, 1, true) then return kind end
        end
      end
    end
  end
  return nil
end

function M.enchants(c, now)
  local hasMH, _, _, hasOH = GetWeaponEnchantInfo()
  local sig = tostring(hasMH) .. "/" .. tostring(hasOH)
  if sig ~= c.enchantSig or now - c.enchantAt > M.ENCHANT_RESCAN then
    local tip = M.tooltip()
    c.enchant = {
      mh = hasMH and M.enchantOf(tip, 16, c.enchantNames) or nil,
      oh = hasOH and M.enchantOf(tip, 17, c.enchantNames) or nil,
    }
    c.enchantSig, c.enchantAt = sig, now
  end
  return c.enchant
end

function M.totem(slot, names, now)
  local have, name, start, dur = GetTotemInfo(slot)
  if not have or not name or name == "" then return nil, 0 end
  local remains = math.max(0, (start or 0) + (dur or 0) - now)
  for base, kind in pairs(names) do
    if name:find(base, 1, true) then return kind, remains end
  end
  return "other", remains
end

function M.guessHealth(level, classification)
  return interp(M.HP_BY_LEVEL, level) * (M.CLASS_MULT[classification] or 1)
end

function M.mode(override)
  if override and override ~= "auto" then return override end
  if (GetNumRaidMembers() or 0) > 0 then return "raid" end
  if (GetNumPartyMembers() or 0) > 0 then return "group" end
  return "solo"
end

function M.range(c)
  local meleeProbed = false
  for _, p in ipairs(M.RANGE_PROBES) do
    local key, band = p[1], p[2]
    local name = c.known[key] and c.names[key]
    if name then
      if band == "melee" then
        meleeProbed = true
      elseif not meleeProbed then
        meleeProbed = true
        if CheckInteractDistance("target", 3) then return "melee" end
      end
      if IsSpellInRange(name, "target") == 1 then return band end
    end
  end
  return "far"
end

function M.spellHaste(c, mw)
  local rating = 1 + (GetCombatRatingBonus(CR_HASTE_SPELL) or 0) / 100
  local k, name = c.known.lightningBolt, c.names.lightningBolt
  if not k or not name then return rating end
  local castMs = select(7, GetSpellInfo(name))
  local base = (M.LB_BASE[k.rank] or 2.5) * (1 - 0.2 * math.min(5, mw or 0))
  if not castMs or castMs <= 0 or base <= 0 then return rating end
  return math.max(1, math.min(3, base / (castMs / 1000)))
end

function M.playerInfo(haste)
  local base, pos, neg = UnitAttackPower("player")
  local hpMax = UnitHealthMax("player") or 0
  local level = UnitLevel("player") or 1
  return {
    level = level,
    mana = UnitPower("player", 0) or 0,
    manaMax = UnitPowerMax("player", 0) or 0,
    baseMana = math.floor(interp(M.BASE_MANA, level) + 0.5),
    hpPct = hpMax > 0 and (UnitHealth("player") or 0) / hpMax or 1,
    ap = (base or 0) + (pos or 0) + (neg or 0),
    spNature = GetSpellBonusDamage(4) or 0,
    spFire = GetSpellBonusDamage(3) or 0,
    meleeCrit = (GetCritChance() or 0) / 100,
    spellCrit = (GetSpellCritChance(4) or 0) / 100,
    meleeHit = ((GetCombatRatingBonus(CR_HIT_MELEE) or 0) + (GetHitModifier and GetHitModifier() or 0)) / 100,
    spellHit = ((GetCombatRatingBonus(CR_HIT_SPELL) or 0) + (GetSpellHitModifier and GetSpellHitModifier() or 0)) / 100,
    spellHaste = haste,
    meleeHaste = 1 + (GetCombatRatingBonus(CR_HASTE_MELEE) or 0) / 100,
    moving = (GetUnitSpeed("player") or 0) > 0,
    inCombat = UnitAffectingCombat("player") and true or false,
  }
end

function M.weapons(c, now)
  local mhSpeed, ohSpeed = UnitAttackSpeed("player")
  local minMH, maxMH, minOH, maxOH = UnitDamage("player")
  local ench = M.enchants(c, now)
  local w = { mh = { speed = mhSpeed or 2.0, min = minMH or 0, max = maxMH or 0, enchant = ench.mh } }
  if ohSpeed and ohSpeed > 0 then
    w.oh = { speed = ohSpeed, min = minOH or 0, max = maxOH or 0, enchant = ench.oh }
  end
  return w
end

function M.spellInfo(c, now)
  local out = {}
  for key, k in pairs(c.known) do
    local name = c.names[key]
    local _, _, _, cost, _, _, castMs = GetSpellInfo(name)
    local st, dur = GetSpellCooldown(name)
    local cd = 0
    if st and st > 0 and dur and dur > 1.5 then cd = math.max(0, st + dur - now) end
    out[key] = { id = k.id, rank = k.rank, cd = cd, cost = cost or 0, cast = (castMs or 0) / 1000 }
  end
  return out
end

function M.targetInfo(ctx, c, now, playerLevel)
  local t = { exists = false, enemy = false, level = 0, hp = 0, hpMax = 0, hpPct = 0, ttd = nil, range = "far",
              fs = 0, ss = { charges = 0, remains = 0 }, guessed = false }
  if not UnitExists("target") or UnitIsDeadOrGhost("target") then return t end
  t.exists = true
  t.enemy = UnitCanAttack("player", "target") and true or false
  local level = UnitLevel("target") or 0
  if level <= 0 then
    level = playerLevel + 3
    t.guessed = true
  end
  t.level = level
  local hp, hpMax = UnitHealth("target") or 0, UnitHealthMax("target") or 0
  t.hpPct = hpMax > 0 and hp / hpMax or 0
  if hpMax == 100 and not UnitIsPlayer("target") then
    hpMax = M.guessHealth(level, UnitClassification("target"))
    hp = hpMax * t.hpPct
    t.guessed = true
  end
  t.hp, t.hpMax = hp, hpMax
  local guid = UnitGUID("target")
  if t.enemy and guid and ctx.ttd then
    ctx.ttd:add(now, guid, t.hpPct)
    t.ttd = ctx.ttd:estimate(now, guid)
  end
  local deb = M.auras("target", "HARMFUL", c.debuffNames, true, now)
  if deb.fs then t.fs = deb.fs.remains end
  if deb.ss then t.ss = { charges = deb.ss.count, remains = deb.ss.remains } end
  t.range = M.range(c)
  return t
end

function M.swingInfo(ctx, now, weapons)
  local st = ctx.swing and ctx.swing:state(now)
  if not st then
    st = { attacking = false, mh = { next = 0, speed = weapons.mh.speed },
           oh = weapons.oh and { next = 0, speed = weapons.oh.speed } or nil }
  end
  if ctx.attacking ~= nil then st.attacking = ctx.attacking end
  st.resetByInstant = st.resetByInstant or {}
  return st
end

function M.inflight(src, now)
  local out = {}
  if not src then return out end
  for key, untilAt in pairs(src) do
    if untilAt > now then out[key] = untilAt - now else src[key] = nil end
  end
  return out
end

local function charges(a) return a and math.max(1, a.count) or 0 end
local function remains(a) return a and a.remains or 0 end

function M.build(ctx)
  local now = ctx.now or GetTime()
  local c = ctx.cache or M.scan()
  ctx.cache = c
  local mine = M.auras("player", "HELPFUL", c.buffNames, false, now)
  local mw = mine.mw and mine.mw.count or 0
  local haste = M.spellHaste(c, mw)
  local S = { now = now, gcdRemains = 0, castRemains = 0, gcd = math.max(1.0, 1.5 / haste), mode = M.mode(ctx.mode) }
  local _, _, latMs = GetNetStats()
  S.latency = (latMs or 0) / 1000 + 0.1
  local gcdName = c.names.lightningBolt
  if gcdName then
    local st, dur = GetSpellCooldown(gcdName)
    if st and st > 0 and dur and dur > 0 and dur <= 1.51 then S.gcdRemains = math.max(0, st + dur - now) end
  end
  local _, _, _, _, _, endMs = UnitCastingInfo("player")
  if endMs then S.castRemains = math.max(0, endMs / 1000 - now) end
  S.player = M.playerInfo(haste)
  S.weapons = M.weapons(c, now)
  S.talents = c.talents or {}
  S.spells = M.spellInfo(c, now)
  S.buffs = {
    mw = { stacks = mw, remains = remains(mine.mw) },
    ls = { charges = charges(mine.ls), remains = remains(mine.ls) },
    flurry = { charges = charges(mine.flurry), remains = remains(mine.flurry) },
    rage = remains(mine.rage), lust = remains(mine.lust), em = remains(mine.em),
  }
  S.target = M.targetInfo(ctx, c, now, S.player.level)
  local fireKind, fireRemains = M.totem(M.SLOT.fire, c.totemNames, now)
  local _, waterRemains = M.totem(M.SLOT.water, c.totemNames, now)
  S.totems = { fire = { kind = fireKind, remains = fireRemains }, water = { remains = waterRemains } }
  S.swing = M.swingInfo(ctx, now, S.weapons)
  local melee, nearby = 0, 0
  if ctx.enemies then melee, nearby = ctx.enemies:counts(now) end
  if S.target.exists and S.target.enemy then
    nearby = math.max(nearby, 1)
    if S.target.range == "melee" then melee = math.max(melee, 1) end
  end
  S.enemies = { melee = melee, nearby = nearby }
  S.inflight = M.inflight(ctx.inflight, now)
  return S
end

return M
```

- [ ] **Step 5: Прогнать тесты**

Run: `docker compose run --rm test busted spec/snapshot_spec.lua`
Expected: PASS, все 17 тестов зелёные.

- [ ] **Step 6: Коммит**

```bash
git add spec/support/game_mock.lua src/snapshot.lua spec/snapshot_spec.lua
git commit -m "EnhRot: снимок ситуации из API клиента 3.3.5a"
```

---

### Task 13: Лента времени (`timeline`)

**Files:**
- Create: `src/timeline.lua`
- Test: `spec/timeline_spec.lua`

**Interfaces:**
- Consumes: `spells.byKey[key].icon`, `model.castTime(S, "lightningBolt")`, контрактный `S`, `plan.steps`, мок `game_mock` (`CreateFrame`, `GetTime`).
- Produces:
  - `timeline.new(parent, opts) -> tl`; `tl:render(plan, S, now)`, `tl:setAlert(alert)`, `tl:tick(dt)`; поля `tl.frame`, `tl.icons`, `tl.glow`, `tl.alert`, `tl.reason`, `tl.cur`;
  - чистые `timeline.options`, `timeline.xOf`, `timeline.swingTimes`, `timeline.castWindow`, `timeline.layout`;
  - константы `timeline.DEFAULTS`, `timeline.ICON_Y = 70`, `timeline.TICK_Y = 22`.

Раскладка по макету B:
- Шкала от черты «сейчас» (`nowX = 60` px) до правого края (`width = 340`) — это `seconds = 6` с.
- Первое действие — крупная иконка 64 px ровно на черте, с подсветкой. Следующие — 38 px в своих точках времени. Если иконки налезают, следующая сдвигается вправо (зазор 2 px).
- Отметки ударов: правая рука — золотые высотой 16 px, левая — серые высотой 10 px.
- Зелёное окно — где можно начать каст Lightning Bolt при 1–4 стаках Maelstrom, не задерживая ни одного удара. При 0 стаков окна нет: каст всё равно сбросит таймер. При 5 стаках тоже нет: Bolt мгновенный.
- Лента «едет» сама: `layout` получает `elapsed` — сколько прошло с момента снимка — и сдвигает всё влево.
- Иконки плавно перетекают к новому месту: `x += (цель − x) · min(1, dt·12)`.

- [ ] **Step 1: Написать падающие тесты**

Создать `spec/timeline_spec.lua`:

```lua
local G = require("game_mock")
local timeline = require("timeline")
local model = require("model")
local spells = require("spells")

local function S(patch)
  local s = {
    now = 100, gcdRemains = 0, latency = 0.15,
    buffs = { mw = { stacks = 3, remains = 20 } },
    spells = { lightningBolt = { id = 49238, rank = 14, cd = 0, cost = 400, cast = 2.5 } },
    swing = { attacking = true, mh = { next = 1.0, speed = 2.6 }, oh = { next = 0.4, speed = 2.6 } },
  }
  for k, v in pairs(patch or {}) do s[k] = v end
  return s
end

local function plan(...)
  local steps = {}
  for i, st in ipairs({ ... }) do steps[i] = { key = st[1], at = st[2], reason = st[3] } end
  return { value = 1, steps = steps }
end

describe("timeline layout", function()
  local realCast
  before_each(function()
    realCast = model.castTime
    model.castTime = function() return 1.0 end
  end)
  after_each(function() model.castTime = realCast end)

  it("maps seconds onto the scale", function()
    local o = timeline.options({})
    assert.are.equal(60, timeline.xOf(0, o))
    assert.are.equal(340, timeline.xOf(6, o))
    assert.are.equal(200, timeline.xOf(3, o))
  end)

  it("puts the first action on the now line and the rest at their times", function()
    local L = timeline.layout(plan({ "stormstrike", 0, "Stormstrike" }, { "waitSwing", 1.0 }, { "lavaLash", 1.5 },
      { "lightningBolt", 2.4 }, { "earthShock", 3.0 }, { "fireNova", 4.5 }), S(), { icons = 3 }, 0)
    assert.are.equal(3, #L.icons)
    assert.are.same({ "stormstrike", "lavaLash", "lightningBolt" }, { L.icons[1].key, L.icons[2].key, L.icons[3].key })
    assert.is_true(L.icons[1].big)
    assert.are.equal(64, L.icons[1].size)
    assert.are.equal(60, L.icons[1].x)
    assert.are.near(130, L.icons[2].x, 1e-9)
    assert.are.near(172, L.icons[3].x, 1e-9)
    assert.are.equal(spells.byKey.stormstrike.icon, L.icons[1].icon)
    assert.are.equal("Stormstrike", L.reason)
  end)

  it("pushes overlapping icons to the right", function()
    local L = timeline.layout(plan({ "stormstrike", 0 }, { "lavaLash", 0.3 }), S(), {}, 0)
    assert.are.near(113, L.icons[2].x, 1e-9)
  end)

  it("lists future swings of both hands in time order", function()
    local t = timeline.swingTimes(S(), 6)
    local got = {}
    for i, s in ipairs(t) do got[i] = s.hand .. "@" .. s.t end
    assert.are.same({ "oh@0.4", "mh@1", "oh@3", "mh@3.6", "oh@5.6" }, got)
    assert.are.same({}, timeline.swingTimes(S({ swing = { attacking = false, mh = { next = 1, speed = 2.6 } } }), 6))
  end)

  it("works with a single two-handed weapon", function()
    local t = timeline.swingTimes(S({ swing = { attacking = true, mh = { next = 0.5, speed = 3.5 } } }), 6)
    assert.are.equal(2, #t)
    assert.are.equal("mh", t[2].hand)
  end)

  it("finds the first gap between swings that fits the cast", function()
    local a, b = timeline.castWindow(S(), timeline.swingTimes(S(), 6))
    assert.are.near(1.0, a, 1e-9)
    assert.are.near(1.85, b, 1e-9)
  end)

  it("shows no cast window at 0 or 5 Maelstrom stacks", function()
    local s0 = S({ buffs = { mw = { stacks = 0, remains = 0 } } })
    assert.is_nil(timeline.castWindow(s0, timeline.swingTimes(s0, 6)))
    local s5 = S({ buffs = { mw = { stacks = 5, remains = 10 } } })
    assert.is_nil(timeline.castWindow(s5, timeline.swingTimes(s5, 6)))
  end)

  it("slides ticks, window and GCD band left as time passes", function()
    local L = timeline.layout(plan({ "stormstrike", 0 }), S({ gcdRemains = 1.2 }), {}, 0.5)
    assert.are.equal("mh", L.ticks[1].hand)
    assert.are.near(0.5, L.ticks[1].t, 1e-9)
    assert.are.near(0.5, L.window.t1, 1e-9)
    assert.are.equal(60, L.gcd.x1)
    assert.are.near(timeline.xOf(0.7, timeline.options({})), L.gcd.x2, 1e-9)
    assert.is_nil(timeline.layout(plan(), S({ gcdRemains = 1.2 }), {}, 1.5).gcd)
  end)

  it("counts Maelstrom dots", function()
    assert.are.equal(3, timeline.layout(plan(), S(), {}, 0).dots)
    assert.are.equal(5, timeline.layout(plan(), S({ buffs = { mw = { stacks = 7, remains = 1 } } }), {}, 0).dots)
  end)
end)

describe("timeline render", function()
  local realCast
  before_each(function()
    G.install({ now = 100 })
    realCast = model.castTime
    model.castTime = function() return 1.0 end
  end)
  after_each(function() model.castTime = realCast end)

  it("draws icons, glow and hides unused slots", function()
    local tl = timeline.new(CreateFrame("Frame"), { icons = 4 })
    tl:render(plan({ "stormstrike", 0, "Stormstrike" }, { "lavaLash", 1.5 }), S(), 100)
    tl.frame.scripts.OnUpdate(tl.frame, 0.016)
    assert.is_true(tl.icons[1].shown)
    assert.are.equal(spells.byKey.stormstrike.icon, tl.icons[1].texture)
    assert.is_true(tl.glow.shown)
    assert.is_false(tl.icons[3].shown)
    assert.are.equal("Stormstrike", tl.reason.text)
  end)

  it("glides an icon to its new place instead of jumping", function()
    local tl = timeline.new(CreateFrame("Frame"), {})
    tl:render(plan({ "stormstrike", 0 }, { "lavaLash", 1.5 }), S(), 100)
    tl:tick(0.016)
    assert.are.near(130, tl.cur.lavaLash, 1e-9)
    tl:render(plan({ "stormstrike", 0 }, { "lavaLash", 3.0 }), S(), 100)
    tl:tick(0.05)
    assert.are.near(172, tl.cur.lavaLash, 1e-9)
  end)

  it("shows and hides the alert icon", function()
    local tl = timeline.new(CreateFrame("Frame"), {})
    tl:setAlert({ icon = "Interface\\Icons\\X" })
    assert.is_true(tl.alert.shown)
    assert.are.equal("Interface\\Icons\\X", tl.alert.texture)
    tl:setAlert(nil)
    assert.is_false(tl.alert.shown)
  end)

  it("hides the reason text when the option is off", function()
    local tl = timeline.new(CreateFrame("Frame"), { showReason = false })
    tl:render(plan({ "stormstrike", 0, "Stormstrike" }), S(), 100)
    tl:tick(0.016)
    assert.is_false(tl.reason.shown)
  end)
end)
```

- [ ] **Step 2: Убедиться, что тесты падают**

Run: `docker compose run --rm test busted spec/timeline_spec.lua`
Expected: FAIL — `module 'timeline' not found`.

- [ ] **Step 3: Реализация**

Создать `src/timeline.lua`:

```lua
local spells = require("spells")
local model = require("model")

local M = {}

M.DEFAULTS = { width = 340, height = 120, nowX = 60, seconds = 6, big = 64, small = 38, icons = 4, gap = 2, lerp = 12, showReason = true }
M.ICON_Y = 70
M.TICK_Y = 22
M.WHITE = "Interface\\Buttons\\WHITE8X8"
M.GLOW = "Interface\\Buttons\\UI-ActionButton-Border"
M.COLORS = {
  mh = { 0.91, 0.76, 0.35, 1 }, oh = { 0.79, 0.83, 0.86, 1 },
  window = { 0.35, 0.9, 0.47, 0.35 }, now = { 1, 0.83, 0.35, 1 }, gcd = { 1, 1, 1, 0.07 },
  lane = { 0.23, 0.29, 0.24, 1 }, dotOn = { 0.37, 0.7, 1, 1 }, dotOff = { 0.11, 0.16, 0.23, 1 },
}

function M.options(opts)
  local o = {}
  for k, v in pairs(M.DEFAULTS) do o[k] = v end
  for k, v in pairs(opts or {}) do if v ~= nil then o[k] = v end end
  return o
end

function M.xOf(t, o)
  return o.nowX + t / o.seconds * (o.width - o.nowX)
end

function M.swingTimes(S, seconds)
  local out = {}
  local sw = S.swing
  if not sw or not sw.attacking then return out end
  for _, hand in ipairs({ "mh", "oh" }) do
    local h = sw[hand]
    if h and h.speed and h.speed > 0 then
      local t = math.max(0, h.next or 0)
      while t <= seconds do
        out[#out + 1] = { t = t, hand = hand }
        t = t + h.speed
      end
    end
  end
  table.sort(out, function(a, b) return a.t < b.t end)
  return out
end

function M.castWindow(S, swings)
  local mw = (S.buffs and S.buffs.mw and S.buffs.mw.stacks) or 0
  if not (S.spells and S.spells.lightningBolt) or mw < 1 or mw >= 5 or #swings == 0 then return nil end
  local need = model.castTime(S, "lightningBolt") + (S.latency or 0)
  local prev = 0
  for _, s in ipairs(swings) do
    if s.t - prev >= need then return prev, s.t - need end
    prev = s.t
  end
  return nil
end

function M.layout(plan, S, opts, elapsed)
  local o = M.options(opts)
  elapsed = elapsed or 0
  local mw = (S.buffs and S.buffs.mw and S.buffs.mw.stacks) or 0
  local L = { nowX = o.nowX, icons = {}, ticks = {}, window = nil, gcd = nil, reason = nil,
              dots = math.max(0, math.min(5, mw)) }
  local prev
  for _, st in ipairs((plan and plan.steps) or {}) do
    if #L.icons >= o.icons then break end
    local meta = spells.byKey[st.key]
    if meta then
      local t = math.max(0, (st.at or 0) - elapsed)
      local big = #L.icons == 0
      local size = big and o.big or o.small
      local x = M.xOf(t, o)
      if prev then x = math.max(x, prev.x + (prev.size + size) / 2 + o.gap) end
      x = math.min(x, o.width)
      local it = { key = st.key, icon = meta.icon, x = x, size = size, big = big, t = t }
      L.icons[#L.icons + 1] = it
      if big then L.reason = st.reason end
      prev = it
    end
  end
  local swings = M.swingTimes(S, o.seconds + elapsed)
  for _, s in ipairs(swings) do
    local t = s.t - elapsed
    if t >= 0 and t <= o.seconds then L.ticks[#L.ticks + 1] = { x = M.xOf(t, o), hand = s.hand, t = t } end
  end
  local a, b = M.castWindow(S, swings)
  if a then
    a, b = math.max(0, a - elapsed), b - elapsed
    if b > a then L.window = { x1 = M.xOf(a, o), x2 = M.xOf(math.min(b, o.seconds), o), t1 = a, t2 = b } end
  end
  local g = (S.gcdRemains or 0) - elapsed
  if g > 0 then L.gcd = { x1 = o.nowX, x2 = M.xOf(math.min(g, o.seconds), o) } end
  return L
end

local TL = {}
TL.__index = TL

local function tex(f, layer, color)
  local t = f:CreateTexture(nil, layer)
  t:SetTexture(M.WHITE)
  if color then t:SetVertexColor(unpack(color)) end
  t:Hide()
  return t
end

local function place(t, f, x, y, w, h)
  t:ClearAllPoints()
  t:SetPoint("CENTER", f, "BOTTOMLEFT", x, y)
  t:SetWidth(w)
  t:SetHeight(h)
  t:Show()
end

function M.new(parent, opts)
  local o = M.options(opts)
  local f = CreateFrame("Frame", nil, parent)
  f:SetWidth(o.width)
  f:SetHeight(o.height)
  f:SetPoint("CENTER", parent, "CENTER", 0, 0)
  if o.scale then f:SetScale(o.scale) end
  local tl = setmetatable({ o = o, frame = f, icons = {}, ticks = {}, dots = {}, cur = {} }, TL)
  tl.lane = tex(f, "BACKGROUND", M.COLORS.lane)
  place(tl.lane, f, (o.nowX + o.width) / 2, M.TICK_Y, o.width - o.nowX, 1)
  tl.gcd = tex(f, "BORDER", M.COLORS.gcd)
  tl.window = tex(f, "ARTWORK", M.COLORS.window)
  tl.now = tex(f, "OVERLAY", M.COLORS.now)
  place(tl.now, f, o.nowX, o.height / 2, 2, o.height)
  for i = 1, o.icons do
    local ic = f:CreateTexture(nil, "ARTWORK")
    ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ic:Hide()
    tl.icons[i] = ic
  end
  tl.glow = f:CreateTexture(nil, "OVERLAY")
  tl.glow:SetTexture(M.GLOW)
  tl.glow:SetBlendMode("ADD")
  tl.glow:SetVertexColor(1, 0.82, 0.3, 1)
  tl.glow:Hide()
  for i = 1, 5 do
    local d = tex(f, "OVERLAY", M.COLORS.dotOff)
    place(d, f, o.width - 8 - (5 - i) * 16, o.height - 8, 12, 12)
    tl.dots[i] = d
  end
  tl.reason = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  tl.reason:Hide()
  tl.alert = f:CreateTexture(nil, "ARTWORK")
  tl.alert:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  place(tl.alert, f, 16, M.ICON_Y, 30, 30)
  tl.alert:Hide()
  f:SetScript("OnUpdate", function(_, dt) tl:tick(dt) end)
  return tl
end

function TL:render(plan, S, now)
  self.plan, self.S, self.at = plan, S, now or GetTime()
end

function TL:setAlert(alert)
  if alert and alert.icon then
    self.alert:SetTexture(alert.icon)
    self.alert:Show()
  else
    self.alert:Hide()
  end
end

function TL:tick(dt)
  if not self.plan or not self.S then return end
  local o, f = self.o, self.frame
  local L = M.layout(self.plan, self.S, o, GetTime() - self.at)
  local k = math.min(1, (dt or 0) * o.lerp)
  local seen = {}
  for i, ic in ipairs(self.icons) do
    local it = L.icons[i]
    if it then
      local x = self.cur[it.key]
      if x then x = x + (it.x - x) * k else x = it.x end
      self.cur[it.key] = x
      seen[it.key] = true
      ic:SetTexture(it.icon)
      place(ic, f, x, M.ICON_Y, it.size, it.size)
      if it.big then place(self.glow, f, x, M.ICON_Y, it.size * 1.7, it.size * 1.7) end
    else
      ic:Hide()
    end
  end
  if not L.icons[1] then self.glow:Hide() end
  for key in pairs(self.cur) do
    if not seen[key] then self.cur[key] = nil end
  end
  for i, tk in ipairs(L.ticks) do
    local t = self.ticks[i]
    if not t then
      t = tex(f, "ARTWORK")
      self.ticks[i] = t
    end
    t:SetVertexColor(unpack(M.COLORS[tk.hand]))
    place(t, f, tk.x, M.TICK_Y, 2, tk.hand == "mh" and 16 or 10)
  end
  for i = #L.ticks + 1, #self.ticks do self.ticks[i]:Hide() end
  if L.window then
    place(self.window, f, (L.window.x1 + L.window.x2) / 2, M.TICK_Y, math.max(2, L.window.x2 - L.window.x1), 12)
  else
    self.window:Hide()
  end
  if L.gcd then
    place(self.gcd, f, (L.gcd.x1 + L.gcd.x2) / 2, M.ICON_Y, L.gcd.x2 - L.gcd.x1, 44)
  else
    self.gcd:Hide()
  end
  for i, d in ipairs(self.dots) do
    d:SetVertexColor(unpack(i <= L.dots and M.COLORS.dotOn or M.COLORS.dotOff))
  end
  local first = L.icons[1]
  if o.showReason and L.reason and first then
    self.reason:SetText(L.reason)
    self.reason:ClearAllPoints()
    self.reason:SetPoint("TOP", f, "BOTTOMLEFT", self.cur[first.key], M.ICON_Y - first.size / 2 - 4)
    self.reason:Show()
  else
    self.reason:Hide()
  end
end

return M
```

- [ ] **Step 4: Прогнать тесты**

Run: `docker compose run --rm test busted spec/timeline_spec.lua`
Expected: PASS, 13 тестов.

- [ ] **Step 5: Коммит**

```bash
git add src/timeline.lua spec/timeline_spec.lua
git commit -m "EnhRot: лента времени с ударами и окном каста"
```

---

### Task 14: Запись снимков и связка с событиями игры (`recorder`, `runtime`)

**Files:**
- Create: `src/recorder.lua`
- Create: `src/runtime.lua`
- Create: `spec/support/scenario.lua`
- Test: `spec/recorder_spec.lua`
- Test: `spec/runtime_spec.lua`

**Interfaces:**
- Consumes:
  - `snapshot.scan/build/auras`, `swing.new()` (методы по контракту), `enemies.new()`, `ttd.new()`;
  - `planner.new(opts)`, `p:update(S, ev) -> plan`;
  - `timeline.new(parent, opts)`, `search.best` (в `scenario`), `talents.standard` (необязательная).
- Produces:
  - `recorder.new(saved, max) -> r`, `r:push(S, plan) -> bool`, `recorder.KEY`, `recorder.MIN_GAP`;
  - `runtime.start(config, env) -> rt` (кладёт в `env.rt`), `runtime.onEvent`, `runtime.update`, `runtime.mark`, `runtime.validPlan`, `runtime.alert`, `runtime.lustReady`, `runtime.signature`, `runtime.MODES`, `runtime.EVENTS`, `runtime.RESCAN`, `runtime.PULSE = 0.25`;
  - `scenario.state(level, patch) -> S`, `scenario.cd(S, map)`, `scenario.best(S)`, `scenario.first(S)`, `scenario.knownAt(level)`, `scenario.merge(dst, patch)`.

Правила `runtime` (спецификация §7):
- События не пересчитывают план сразу. Они только ставят отметку «нужен пересчёт» с приоритетом: `cast > target > swing > aura > totem > power`. Сам пересчёт идёт в ближайшем `OnUpdate` — не чаще одного раза за кадр. Без событий пересчёт идёт раз в `PULSE = 0.25` с.
- Боевой лог сначала фильтруется по GUID игрока: остальные записи отбрасываются сразу, кроме `UNIT_DIED` текущей цели.
- Нет вражеской цели → планировщик не вызывается, на ленте только предупреждение.
- Ошибки без `pcall`: план проверяется `validPlan` перед отрисовкой. Негодный план — одно сообщение в чат за сессию; лента держит последний хороший план.

- [ ] **Step 1: Тесты записи снимков**

Создать `spec/recorder_spec.lua`:

```lua
local recorder = require("recorder")

describe("recorder", function()
  it("stores a deep copy of the snapshot and plan", function()
    local saved = {}
    local r = recorder.new(saved, 30)
    local S = { now = 100, buffs = { mw = { stacks = 2 } } }
    assert.is_true(r:push(S, { steps = { { key = "stormstrike", at = 0 } } }))
    S.buffs.mw.stacks = 5
    assert.are.equal(2, saved.enhrotSnapshots[1].S.buffs.mw.stacks)
    assert.are.equal("stormstrike", saved.enhrotSnapshots[1].plan.steps[1].key)
  end)

  it("keeps at least MIN_GAP seconds between records", function()
    local r = recorder.new({}, 30)
    assert.is_true(r:push({ now = 100 }, { steps = {} }))
    assert.is_false(r:push({ now = 101 }, { steps = {} }))
    assert.is_true(r:push({ now = 102.5 }, { steps = {} }))
  end)

  it("keeps only the newest max records", function()
    local saved = {}
    local r = recorder.new(saved, 3)
    for i = 1, 5 do r:push({ now = i * 10 }, { steps = {} }) end
    assert.are.equal(3, #saved.enhrotSnapshots)
    assert.are.equal(30, saved.enhrotSnapshots[1].S.now)
  end)

  it("continues an existing list after reload", function()
    local saved = { enhrotSnapshots = { { S = { now = 1 }, plan = { steps = {} } } } }
    local r = recorder.new(saved, 30)
    r:push({ now = 100 }, { steps = {} })
    assert.are.equal(2, #saved.enhrotSnapshots)
  end)
end)
```

- [ ] **Step 2: Убедиться, что тесты падают**

Run: `docker compose run --rm test busted spec/recorder_spec.lua`
Expected: FAIL — `module 'recorder' not found`.

- [ ] **Step 3: Реализация записи снимков**

Создать `src/recorder.lua`:

```lua
local M = {}
M.KEY = "enhrotSnapshots"
M.MIN_GAP = 2

local function copy(v, seen)
  if type(v) ~= "table" then
    if type(v) == "function" then return nil end
    return v
  end
  seen = seen or {}
  if seen[v] then return seen[v] end
  local out = {}
  seen[v] = out
  for k, x in pairs(v) do out[copy(k, seen)] = copy(x, seen) end
  return out
end
M.copy = copy

local R = {}
R.__index = R

function M.new(saved, max)
  saved[M.KEY] = saved[M.KEY] or {}
  return setmetatable({ list = saved[M.KEY], max = max or 30, last = -math.huge }, R)
end

function R:push(S, plan)
  if (S.now or 0) - self.last < M.MIN_GAP then return false end
  self.last = S.now or 0
  self.list[#self.list + 1] = { S = copy(S), plan = copy(plan) }
  while #self.list > self.max do table.remove(self.list, 1) end
  return true
end

return M
```

Run: `docker compose run --rm test busted spec/recorder_spec.lua`
Expected: PASS, 4 теста.

- [ ] **Step 4: Сборщик сценариев для тестов**

Создать `spec/support/scenario.lua`. Он нужен тестам `runtime` и задачи 16:

```lua
local spells = require("spells")
local data = require("spells_data")
local talents = require("talents")
local search = require("search")

local Sc = {}

-- уровни, на которых становятся доступны заклинания без рангов в spells_data
Sc.LEVEL = { stormstrike = 40, lavaLash = 45, shamanisticRage = 50, feralSpirit = 60, callOfElements = 30, fireElemental = 68 }
Sc.COST_PCT = { lightningBolt = 10, chainLightning = 26, earthShock = 18, flameShock = 17, frostShock = 18, lavaLash = 4,
                stormstrike = 8, fireNova = 22, magmaTotem = 27, searingTotem = 7, fireElemental = 23, feralSpirit = 12,
                callOfElements = 30, lightningShield = 0, shamanisticRage = 0 }
Sc.BASE_MANA = { { 1, 55 }, { 10, 185 }, { 20, 410 }, { 30, 635 }, { 40, 860 }, { 50, 1085 }, { 60, 1520 }, { 70, 2678 }, { 80, 4396 } }
Sc.HP = { { 1, 42 }, { 10, 200 }, { 20, 600 }, { 30, 1200 }, { 40, 2000 }, { 50, 3500 }, { 60, 4500 }, { 70, 7000 }, { 80, 12000 } }
Sc.OPTS = { horizon = 6, beam = 6, depth = 4, budgetMs = 2, clock = function() return 0 end }

local function interp(t, x)
  if x <= t[1][1] then return t[1][2] end
  for i = 2, #t do
    if x <= t[i][1] then
      local a, b = t[i - 1], t[i]
      return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1])
    end
  end
  return t[#t][2]
end

function Sc.merge(dst, patch)
  for k, v in pairs(patch or {}) do
    if type(v) == "table" and type(dst[k]) == "table" then Sc.merge(dst[k], v) else dst[k] = v end
  end
  return dst
end

local function rankIndex(meta, id)
  for i, x in ipairs(meta.ranks) do if x == id then return i end end
  return 1
end

function Sc.knownAt(level)
  local out = {}
  for _, meta in ipairs(spells.CATALOG) do
    local ranks = data[meta.key]
    if Sc.LEVEL[meta.key] then
      if level >= Sc.LEVEL[meta.key] then out[meta.key] = { id = meta.ranks[1], rank = 1 } end
    elseif ranks then
      for i = #ranks, 1, -1 do
        if ranks[i].level <= level then
          out[meta.key] = { id = ranks[i].id, rank = rankIndex(meta, ranks[i].id) }
          break
        end
      end
    end
  end
  return out
end

local function castOf(key, rank)
  if key == "lightningBolt" then return ({ 1.5, 2.0 })[rank] or 2.5 end
  if key == "chainLightning" then return 2.0 end
  return 0
end

-- level 80: raid boss, WF/FT, big cooldowns on cd; below 80: solo trash mob of the same level
function Sc.state(level, patch)
  local baseMana = interp(Sc.BASE_MANA, level)
  local dual = level >= 40
  local mobHp = interp(Sc.HP, level)
  local S = {
    now = 100, gcdRemains = 0, castRemains = 0, latency = 0.15,
    gcd = level >= 80 and 1.5 / 1.15 or 1.5,
    mode = level >= 80 and "raid" or "solo",
    player = {
      level = level, mana = baseMana * 3.5 * 0.8, manaMax = baseMana * 3.5, baseMana = baseMana, hpPct = 1,
      ap = level * 50, spNature = level * 15, spFire = level * 15,
      meleeCrit = 0.05 + level * 0.003, spellCrit = 0.05 + level * 0.002,
      meleeHit = level >= 80 and 0.08 or 0, spellHit = level >= 80 and 0.10 or 0,
      spellHaste = level >= 80 and 1.15 or 1.0, meleeHaste = level >= 80 and 1.2 or 1.0,
      moving = false, inCombat = true,
    },
    weapons = {},
    talents = (talents.standard and talents.standard(level)) or {},
    spells = {},
    buffs = { mw = { stacks = 0, remains = 0 }, ls = { charges = 0, remains = 0 }, flurry = { charges = 0, remains = 0 }, rage = 0, lust = 0, em = 0 },
    target = level >= 80
      and { exists = true, enemy = true, level = 83, hp = 1e7, hpMax = 1e7, hpPct = 1, ttd = 180, range = "melee", fs = 0, ss = { charges = 0, remains = 0 }, guessed = false }
      or { exists = true, enemy = true, level = level, hp = mobHp, hpMax = mobHp, hpPct = 1, ttd = 20, range = "melee", fs = 0, ss = { charges = 0, remains = 0 }, guessed = false },
    totems = { fire = { kind = nil, remains = 0 }, water = { remains = 120 } },
    swing = { attacking = true, mh = { next = 1.0, speed = dual and 2.6 or 3.5 }, resetByInstant = {} },
    enemies = { melee = 1, nearby = 1 },
    inflight = {},
  }
  if dual then
    S.weapons.mh = { speed = 2.6, min = level * 6, max = level * 9, enchant = "wf" }
    S.weapons.oh = { speed = 2.6, min = level * 3, max = level * 4.5, enchant = "ft" }
    S.swing.oh = { next = 0.5, speed = 2.6 }
  else
    S.weapons.mh = { speed = 3.5, min = level * 8, max = level * 12, enchant = level >= 30 and "wf" or (level >= 10 and "ft" or "rb") }
  end
  for key, k in pairs(Sc.knownAt(level)) do
    S.spells[key] = { id = k.id, rank = k.rank, cd = 0, cost = math.floor((Sc.COST_PCT[key] or 0) / 100 * baseMana), cast = castOf(key, k.rank) }
  end
  if S.spells.lightningShield then S.buffs.ls = { charges = 3, remains = 600 } end
  if level >= 80 then
    Sc.cd(S, { feralSpirit = 120, fireElemental = 300, shamanisticRage = 30 })
  end
  return Sc.merge(S, patch)
end

-- map: key -> cd; key "shock" sets the shared cooldown of all shocks
function Sc.cd(S, map)
  for key, v in pairs(map) do
    local keys = key == "shock" and { "earthShock", "flameShock", "frostShock" } or { key }
    for _, k in ipairs(keys) do
      if S.spells[k] then S.spells[k].cd = v end
    end
  end
  return S
end

function Sc.best(S)
  return search.best(S, Sc.OPTS)
end

function Sc.first(S)
  local plan = Sc.best(S)
  local st = plan.steps[1]
  return st and st.key, st and st.at, plan
end

return Sc
```

- [ ] **Step 5: Тесты `runtime`**

Создать `spec/runtime_spec.lua`:

```lua
local G = require("game_mock")
local runtime = require("runtime")
local planner = require("planner")
local spells = require("spells")
local Sc = require("scenario")

local function top(key) local r = spells.byKey[key].ranks; return r[#r] end

local PLAN = { value = 10, steps = { { key = "stormstrike", at = 0, reason = "Stormstrike" }, { key = "lavaLash", at = 1.5 } } }

local function allKnown()
  local k = {}
  for _, meta in ipairs(spells.CATALOG) do k[meta.ranks[#meta.ranks]] = true end
  return k
end

local function install(extra)
  local cfg = { now = 100, known = allKnown(), castMs = { ["Lightning Bolt"] = 2500 },
                target = { level = 83, hp = 1e6, hpMax = 1e6, guid = "Creature-9" }, inRange = { Stormstrike = 1 },
                enchants = { mh = true, oh = true }, tooltip = { [16] = { "Windfury 8" }, [17] = { "Flametongue 10" } },
                auras = { player = { HELPFUL = { { name = "Lightning Shield", count = 3, expires = 700 } } } } }
  for k, v in pairs(extra or {}) do cfg[k] = v end
  return G.install(cfg)
end

local function spy()
  local s = { calls = {}, saved = {} }
  for _, m in ipairs({ "onSwing", "onExtraAttacks", "onSpeed", "onCastStart", "onCastEnd", "onInstant" }) do
    s[m] = function(self, ...) self.calls[#self.calls + 1] = { m, ... } end
  end
  s.state = function() return { attacking = true, mh = { next = 1, speed = 2.6 }, oh = { next = 0.5, speed = 2.6 }, resetByInstant = {} } end
  s.castWindow = function() return nil end
  return s
end

local function enemiesSpy()
  local e = { calls = {} }
  function e:onEvent(...) self.calls[#self.calls + 1] = { ... } end
  function e:counts() return 1, 1 end
  return e
end

describe("runtime", function()
  local realNew, calls, nextPlan
  before_each(function()
    realNew = planner.new
    calls, nextPlan = {}, PLAN
    planner.new = function()
      return { update = function(_, S, ev) calls[#calls + 1] = { S = S, ev = ev }; return nextPlan end }
    end
  end)
  after_each(function() planner.new = realNew end)

  local function start(config, extra)
    install(extra)
    local env = { config = config or {}, region = CreateFrame("Frame"), saved = {} }
    local rt = runtime.start(env.config, env)
    rt.ctx.swing = spy()
    rt.ctx.enemies = enemiesSpy()
    return rt, env
  end

  it("validates plans", function()
    assert.is_true(runtime.validPlan(PLAN))
    assert.is_true(runtime.validPlan({ steps = { { key = "waitSwing", at = 0.4 } } }))
    assert.is_false(runtime.validPlan(nil))
    assert.is_false(runtime.validPlan({ steps = { { key = "fireball", at = 0 } } }))
    assert.is_false(runtime.validPlan({ steps = { { key = "stormstrike", at = 0 / 0 } } }))
  end)

  it("raises alerts in order of importance", function()
    local S = Sc.state(80)
    S.buffs.ls.charges = 0
    assert.are.equal("lightningShield", runtime.alert(S).key)
    S = Sc.state(80); S.weapons.oh.enchant = nil
    assert.are.equal("noEnchant", runtime.alert(S).key)
    S = Sc.state(80); S.player.mana = S.player.manaMax * 0.1; S.spells.shamanisticRage.cd = 0
    local a = runtime.alert(S)
    assert.are.equal("shamanisticRage", a.key)
    assert.are.equal(spells.byKey.shamanisticRage.icon, a.icon)
    S = Sc.state(80); S.target.range = "far"
    assert.are.equal("outOfRange", runtime.alert(S).key)
    assert.is_nil(runtime.alert(Sc.state(80)))
  end)

  it("registers 3.3.5 events only and reuses the engine frame", function()
    local rt = start()
    assert.is_true(rt.frame.events.UNIT_MANA)
    assert.is_nil(rt.frame.events.UNIT_POWER)
    assert.is_true(rt.frame.events.COMBAT_LOG_EVENT_UNFILTERED)
    assert.is_true(rt.frame.events.SPELLS_CHANGED)
    local env2 = { config = {}, region = CreateFrame("Frame"), saved = {} }
    local old = rt.tl
    local rt2 = runtime.start({}, env2)
    assert.are.equal(rt.frame, rt2.frame)
    assert.is_false(old.frame.shown)
    assert.are.equal(rt2, env2.rt)
  end)

  it("feeds own swings and extra attacks to the swing clock", function()
    local rt = start()
    runtime.onEvent(rt, "COMBAT_LOG_EVENT_UNFILTERED", 0, "SWING_DAMAGE", "Player-1", "Me", 0x511, "Creature-9", "Mob", 0xa48, 1200)
    runtime.onEvent(rt, "COMBAT_LOG_EVENT_UNFILTERED", 0, "SPELL_EXTRA_ATTACKS", "Player-1", "Me", 0x511, "Player-1", "Me", 0x511, 25504, "Windfury Attack", 1, 2)
    assert.are.same({ "onSwing", 100, false }, rt.ctx.swing.calls[1])
    assert.are.same({ "onExtraAttacks", 100, 2 }, rt.ctx.swing.calls[2])
    assert.are.equal("swing", rt.pending.kind)
  end)

  it("drops combat log lines that do not involve the player", function()
    local rt = start()
    runtime.onEvent(rt, "COMBAT_LOG_EVENT_UNFILTERED", 0, "SWING_DAMAGE", "Creature-2", "A", 0, "Creature-3", "B", 0, 100)
    assert.are.equal(0, #rt.ctx.enemies.calls)
    assert.are.equal(0, #rt.ctx.swing.calls)
    assert.is_nil(rt.pending)
  end)

  it("replans when the current target dies", function()
    local rt = start()
    runtime.onEvent(rt, "COMBAT_LOG_EVENT_UNFILTERED", 0, "UNIT_DIED", nil, nil, 0, "Creature-9", "Mob", 0xa48)
    assert.are.equal("target", rt.pending.kind)
  end)

  it("tracks a hard cast with the Maelstrom stacks at its start", function()
    local rt = start(nil, { casting = { name = "Lightning Bolt", startMs = 100000, endMs = 101500 },
      auras = { player = { HELPFUL = { { name = "Maelstrom Weapon", count = 3, expires = 110 } } } } })
    runtime.onEvent(rt, "UNIT_SPELLCAST_START", "player", "Lightning Bolt", "Rank 14")
    assert.are.same({ "onCastStart", 100, "lightningBolt", 3, 1.5 }, rt.ctx.swing.calls[1])
    runtime.onEvent(rt, "UNIT_SPELLCAST_SUCCEEDED", "player", "Lightning Bolt", "Rank 14")
    assert.are.same({ "onCastEnd", 100, "lightningBolt", 3, true }, rt.ctx.swing.calls[2])
    assert.are.equal(101, rt.ctx.inflight.lightningBolt)
  end)

  it("reports an interrupted cast and instant casts separately", function()
    local rt = start(nil, { casting = { name = "Lightning Bolt", startMs = 100000, endMs = 102500 } })
    runtime.onEvent(rt, "UNIT_SPELLCAST_START", "player", "Lightning Bolt", "Rank 14")
    runtime.onEvent(rt, "UNIT_SPELLCAST_INTERRUPTED", "player", "Lightning Bolt", "Rank 14")
    assert.are.same({ "onCastEnd", 100, "lightningBolt", 0, false }, rt.ctx.swing.calls[2])
    runtime.onEvent(rt, "UNIT_SPELLCAST_SUCCEEDED", "player", "Earth Shock", "Rank 10")
    assert.are.same({ "onInstant", 100, "earthShock" }, rt.ctx.swing.calls[3])
    runtime.onEvent(rt, "UNIT_SPELLCAST_FAILED", "player", "Earth Shock", "Rank 10")
    assert.is_nil(rt.ctx.inflight.earthShock)
    runtime.onEvent(rt, "UNIT_SPELLCAST_START", "party1", "Lightning Bolt", "Rank 14")
    assert.are.equal(3, #rt.ctx.swing.calls)
  end)

  it("clears the in-flight mark when the aura lands", function()
    local rt = start()
    runtime.onEvent(rt, "UNIT_SPELLCAST_SUCCEEDED", "player", "Flame Shock", "Rank 9")
    assert.is_not_nil(rt.ctx.inflight.flameShock)
    runtime.onEvent(rt, "COMBAT_LOG_EVENT_UNFILTERED", 0, "SPELL_AURA_APPLIED", "Player-1", "Me", 0x511, "Creature-9", "Mob", 0xa48, 49233, "Flame Shock", 4, "DEBUFF")
    assert.is_nil(rt.ctx.inflight.flameShock)
  end)

  it("passes attack speed changes and auto-attack state", function()
    local rt = start(nil, { speed = { 2.4, 2.4 } })
    runtime.onEvent(rt, "UNIT_ATTACK_SPEED", "player")
    assert.are.same({ "onSpeed", 100, 2.4, 2.4 }, rt.ctx.swing.calls[1])
    runtime.onEvent(rt, "PLAYER_ENTER_COMBAT")
    assert.is_true(rt.ctx.attacking)
    runtime.onEvent(rt, "PLAYER_LEAVE_COMBAT")
    assert.is_false(rt.ctx.attacking)
  end)

  it("coalesces events and keeps the most important one", function()
    local rt = start()
    runtime.onEvent(rt, "UNIT_MANA", "player")
    runtime.onEvent(rt, "UNIT_SPELLCAST_SUCCEEDED", "player", "Earth Shock", "Rank 10")
    runtime.onEvent(rt, "UNIT_AURA", "player")
    runtime.update(rt, 0.01)
    assert.are.equal(1, #calls)
    assert.are.equal("cast", calls[1].ev.kind)
    assert.are.equal("earthShock", calls[1].ev.key)
  end)

  it("pulses every 0.25 s without events", function()
    local rt = start()
    runtime.update(rt, 0.1)
    assert.are.equal(0, #calls)
    runtime.update(rt, 0.2)
    assert.are.equal(1, #calls)
    assert.are.equal("pulse", calls[1].ev.kind)
  end)

  it("shows the host aura on the first update", function()
    local rt = start()
    runtime.update(rt, 0.01)
    assert.are.equal("ENHROT_SHOW", G.sent[1][1])
  end)

  it("does not plan without a hostile target", function()
    local rt = start(nil, { target = { exists = false } })
    runtime.update(rt, 0.3)
    assert.are.equal(0, #calls)
    assert.are.same({}, rt.plan.steps)
  end)

  it("reports a broken plan once and keeps the last good one", function()
    local rt = start()
    runtime.update(rt, 0.3)
    nextPlan = { steps = { { key = "fireball", at = 0 } } }
    runtime.update(rt, 0.3)
    runtime.update(rt, 0.3)
    assert.are.equal(1, #G.printed)
    assert.are.equal(PLAN, rt.plan)
    assert.are.equal(2, rt.counters.errors)
  end)

  it("prints debug lines only when the first action changes", function()
    local rt = start({ printDebug = true })
    runtime.update(rt, 0.3)
    runtime.update(rt, 0.3)
    assert.are.equal(1, #G.printed)
    assert.is_not_nil(G.printed[1]:find("stormstrike@0.0", 1, true))
  end)

  it("records a snapshot on replans when recording is on", function()
    local rt, env = start({ record = true })
    runtime.update(rt, 0.3)
    assert.are.equal(1, #env.saved.enhrotSnapshots)
  end)

  it("rescans spells after learning one", function()
    local rt = start(nil, { known = { [top("lightningBolt")] = true } })
    assert.is_nil(rt.ctx.cache.known.stormstrike)
    G.cfg.known[17364] = true
    runtime.onEvent(rt, "LEARNED_SPELL_IN_TAB")
    assert.is_not_nil(rt.ctx.cache.known.stormstrike)
    assert.are.equal("target", rt.pending.kind)
  end)

  it("resets enemies and the planner when combat ends", function()
    local rt = start()
    local p = rt.planner
    runtime.onEvent(rt, "PLAYER_REGEN_ENABLED")
    assert.are_not.equal(p, rt.planner)
  end)
end)
```

- [ ] **Step 6: Убедиться, что тесты падают**

Run: `docker compose run --rm test busted spec/runtime_spec.lua`
Expected: FAIL — `module 'runtime' not found`.

- [ ] **Step 7: Реализация `runtime`**

Создать `src/runtime.lua`:

```lua
local spells = require("spells")
local swing = require("swing")
local enemies = require("enemies")
local ttd = require("ttd")
local snapshot = require("snapshot")
local planner = require("planner")
local timeline = require("timeline")
local recorder = require("recorder")

local M = {}

M.PULSE = 0.25
M.RECORD_MAX = 30
M.MODES = { "auto", "solo", "group", "raid", "pvp" }
M.EVENTS = {
  "COMBAT_LOG_EVENT_UNFILTERED",
  "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
  "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_DELAYED",
  "UNIT_AURA", "PLAYER_TARGET_CHANGED", "UNIT_MANA", "PLAYER_TOTEM_UPDATE", "UNIT_ATTACK_SPEED",
  "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
}
M.RESCAN = { SPELLS_CHANGED = true, LEARNED_SPELL_IN_TAB = true, PLAYER_LEVEL_UP = true, CHARACTER_POINTS_CHANGED = true, PLAYER_TALENT_UPDATE = true }
M.PRIORITY = { cast = 6, target = 5, swing = 4, aura = 3, totem = 2, power = 1, pulse = 0 }
M.WAIT_KEYS = { waitSwing = true, wait = true }
M.LUST_IDS = { 2825, 32182 }
M.ALERT_ICONS = {
  noEnchant = "Interface\\Icons\\Spell_Nature_Cyclone",
  outOfRange = "Interface\\Icons\\Ability_Rogue_Sprint",
}

function M.validPlan(plan)
  if type(plan) ~= "table" or type(plan.steps) ~= "table" then return false end
  for _, st in ipairs(plan.steps) do
    if type(st) ~= "table" or type(st.at) ~= "number" then return false end
    if st.at ~= st.at or st.at < -1 or st.at > 60 then return false end
    if not (spells.byKey[st.key] or M.WAIT_KEYS[st.key]) then return false end
  end
  return true
end

local function withIcon(a)
  local meta = spells.byKey[a.key]
  a.icon = (meta and meta.icon) or M.ALERT_ICONS[a.key]
  return a
end

function M.alert(S)
  local sp, b, w = S.spells, S.buffs, S.weapons
  if sp.lightningShield and b.ls.charges <= 0 then
    return withIcon({ key = "lightningShield", reason = "Lightning Shield missing" })
  end
  if (w.mh and not w.mh.enchant) or (w.oh and not w.oh.enchant) then
    return withIcon({ key = "noEnchant", reason = "Weapon imbue missing" })
  end
  local rage = sp.shamanisticRage
  if rage and S.player.manaMax > 0 and S.player.mana / S.player.manaMax < 0.2 and rage.cd <= (S.gcdRemains or 0) + 0.1 then
    return withIcon({ key = "shamanisticRage", reason = "Low mana: Shamanistic Rage" })
  end
  if S.target.exists and S.target.enemy and S.target.range == "far" then
    return withIcon({ key = "outOfRange", reason = "Target out of range" })
  end
  return nil
end

function M.lustReady(S, now)
  if S.mode ~= "group" and S.mode ~= "raid" then return nil end
  for _, id in ipairs(M.LUST_IDS) do
    local name = GetSpellInfo(id)
    if name and GetSpellInfo(name) then
      local st, dur = GetSpellCooldown(name)
      if not st or st == 0 or st + dur - now <= 0 then
        local _, _, icon = GetSpellInfo(name)
        return { key = "lust", icon = icon, reason = name .. " ready" }
      end
    end
  end
  return nil
end

function M.signature(plan, c)
  local parts = {}
  for _, st in ipairs(plan.steps) do parts[#parts + 1] = ("%s@%.1f"):format(st.key, st.at) end
  return ("EnhRot: %s | replans=%d timeouts=%d errors=%d"):format(table.concat(parts, " "), c.replans, c.timeouts, c.errors)
end

function M.report(rt, msg)
  rt.counters.errors = rt.counters.errors + 1
  if rt.reported then return end
  rt.reported = true
  print("|cffff5555EnhRot|r " .. msg)
end

function M.mark(rt, kind, key)
  if not rt.pending or M.PRIORITY[kind] > M.PRIORITY[rt.pending.kind] then
    rt.pending = { kind = kind, key = key }
  end
end

local function mwNow(ctx, now)
  local a = snapshot.auras("player", "HELPFUL", ctx.cache.buffNames, false, now)
  return a.mw and a.mw.count or 0
end

function M.onCast(rt, event, key, now)
  local ctx = rt.ctx
  if event == "UNIT_SPELLCAST_START" then
    local _, _, _, _, startMs, endMs = UnitCastingInfo("player")
    local castTime = (startMs and endMs) and (endMs - startMs) / 1000 or 0
    rt.casting = { key = key, mw = mwNow(ctx, now) }
    ctx.swing:onCastStart(now, key, rt.casting.mw, castTime)
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    if rt.casting and rt.casting.key == key then
      ctx.swing:onCastEnd(now, key, rt.casting.mw, true)
      rt.casting = nil
    else
      ctx.swing:onInstant(now, key)
    end
    ctx.inflight[key] = now + 1
  elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
    if rt.casting and rt.casting.key == key then
      ctx.swing:onCastEnd(now, key, rt.casting.mw, false)
      rt.casting = nil
    end
    ctx.inflight[key] = nil
  elseif event ~= "UNIT_SPELLCAST_DELAYED" then
    return
  end
  M.mark(rt, "cast", key)
end

function M.onCombatLog(rt, now, _, sub, src, _, _, dst, _, _, _, a2, _, a4)
  local ctx, pg = rt.ctx, rt.playerGUID
  if sub == "UNIT_DIED" then
    if dst and dst == UnitGUID("target") then M.mark(rt, "target") end
    return
  end
  if src ~= pg and dst ~= pg then return end
  ctx.enemies:onEvent(now, sub, src, dst, pg)
  if src ~= pg then return end
  if sub == "SWING_DAMAGE" or sub == "SWING_MISSED" then
    ctx.swing:onSwing(now, false)
    M.mark(rt, "swing")
  elseif sub == "SPELL_EXTRA_ATTACKS" then
    ctx.swing:onExtraAttacks(now, a4 or 1)
  elseif sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REFRESH" or sub == "SPELL_AURA_APPLIED_DOSE" then
    local key = ctx.cache.keyByName[a2]
    if key then ctx.inflight[key] = nil end
    M.mark(rt, "aura")
  end
end

function M.onEvent(rt, event, ...)
  local now = GetTime()
  local ctx = rt.ctx
  if event == "COMBAT_LOG_EVENT_UNFILTERED" then
    M.onCombatLog(rt, now, ...)
  elseif event:sub(1, 15) == "UNIT_SPELLCAST_" then
    local unit, name = ...
    if unit ~= "player" then return end
    local key = ctx.cache.keyByName[name]
    if key then M.onCast(rt, event, key, now) end
  elseif event == "UNIT_AURA" then
    local unit = ...
    if unit == "player" or unit == "target" then M.mark(rt, "aura") end
  elseif event == "PLAYER_TARGET_CHANGED" then
    M.mark(rt, "target")
  elseif event == "UNIT_MANA" then
    if (...) == "player" then M.mark(rt, "power") end
  elseif event == "PLAYER_TOTEM_UPDATE" then
    M.mark(rt, "totem")
  elseif event == "UNIT_ATTACK_SPEED" then
    if (...) == "player" then
      local mh, oh = UnitAttackSpeed("player")
      ctx.swing:onSpeed(now, mh, oh)
      M.mark(rt, "swing")
    end
  elseif event == "PLAYER_ENTER_COMBAT" then
    ctx.attacking = true
    M.mark(rt, "swing")
  elseif event == "PLAYER_LEAVE_COMBAT" then
    ctx.attacking = false
    M.mark(rt, "swing")
  elseif event == "PLAYER_REGEN_ENABLED" then
    ctx.enemies = enemies.new()
    rt.planner = planner.new({})
  elseif event == "PLAYER_ENTERING_WORLD" then
    rt.playerGUID = UnitGUID("player")
    rt.shown = false
  elseif M.RESCAN[event] then
    ctx.cache = snapshot.scan()
    M.mark(rt, "target")
  end
end

function M.update(rt, dt)
  rt.elapsed = rt.elapsed + (dt or 0)
  if not rt.shown then
    rt.shown = true
    WeakAuras.ScanEvents("ENHROT_SHOW")
  end
  if not rt.pending and rt.elapsed < M.PULSE then return false end
  local ev = rt.pending or { kind = "pulse" }
  rt.pending, rt.elapsed = nil, 0
  local now = GetTime()
  rt.ctx.now = now
  local S = snapshot.build(rt.ctx)
  local alert = M.alert(S)
  if not alert and rt.config.showLust ~= false then alert = M.lustReady(S, now) end
  rt.tl:setAlert(alert)
  if not (S.target.exists and S.target.enemy) then
    rt.plan, rt.S = { value = 0, steps = {} }, S
    rt.tl:render(rt.plan, S, now)
    return true
  end
  local plan = rt.planner:update(S, ev)
  if not M.validPlan(plan) then
    M.report(rt, "planner returned an invalid plan")
    return false
  end
  if plan.timedOut then rt.counters.timeouts = rt.counters.timeouts + 1 end
  local first = plan.steps[1] and plan.steps[1].key
  if first ~= rt.lastFirst then
    rt.lastFirst = first
    rt.counters.replans = rt.counters.replans + 1
    if rt.rec then rt.rec:push(S, plan) end
    if rt.config.printDebug then print(M.signature(plan, rt.counters)) end
  end
  rt.plan, rt.S = plan, S
  rt.tl:render(plan, S, now)
  return true
end

function M.timelineOptions(config)
  return { icons = config.icons, seconds = config.seconds, scale = config.scale, showReason = config.showReason ~= false }
end

function M.start(config, env)
  config = config or {}
  env = env or {}
  env.saved = env.saved or {}
  env.saved.swing = env.saved.swing or {}
  local ctx = { cache = snapshot.scan(), swing = swing.new(), enemies = enemies.new(), ttd = ttd.new(),
                inflight = {}, mode = M.MODES[config.mode or 1] or "auto", attacking = nil }
  ctx.swing.saved = env.saved.swing
  local frame = EnhRotEngineFrame or CreateFrame("Frame", "EnhRotEngineFrame")
  frame:UnregisterAllEvents()
  for _, e in ipairs(M.EVENTS) do frame:RegisterEvent(e) end
  for e in pairs(M.RESCAN) do frame:RegisterEvent(e) end
  if frame.enhrotTimeline then
    frame.enhrotTimeline.frame:SetScript("OnUpdate", nil)
    frame.enhrotTimeline.frame:Hide()
  end
  local tl = timeline.new(env.region or UIParent, M.timelineOptions(config))
  frame.enhrotTimeline = tl
  local rt = {
    config = config, env = env, ctx = ctx, frame = frame, tl = tl, elapsed = 0, pending = nil, shown = false,
    planner = planner.new({}), rec = config.record and recorder.new(env.saved, M.RECORD_MAX) or nil,
    playerGUID = UnitGUID("player"), counters = { replans = 0, timeouts = 0, errors = 0 }, reported = false,
  }
  frame:SetScript("OnEvent", function(_, event, ...) M.onEvent(rt, event, ...) end)
  frame:SetScript("OnUpdate", function(_, dt) M.update(rt, dt) end)
  frame:Show()
  env.rt = rt
  return rt
end

return M
```

- [ ] **Step 8: Прогнать тесты**

Run: `docker compose run --rm test busted spec/recorder_spec.lua spec/runtime_spec.lua`
Expected: PASS — 4 + 20 тестов.

Если тест `raises alerts in order of importance` падает на `S.spells.shamanisticRage == nil`, значит в `spells_data`/`CATALOG` у Shamanistic Rage другой ключ. Сверить ключ с контрактом, а не менять тест.

- [ ] **Step 9: Коммит**

```bash
git add src/recorder.lua src/runtime.lua spec/support/scenario.lua spec/recorder_spec.lua spec/runtime_spec.lua
git commit -m "EnhRot: связка с событиями игры и запись снимков"
```

---

### Task 15: Аура и сборка строки импорта (`tools/aura.lua`, `tools/build.lua`)

**Files:**
- Create: `tools/aura.lua`
- Create: `tools/build.lua`
- Create: `tools/encode.lua` (копия из `frost-rotation`, без изменений), если её не создала часть 1
- Create: `vendor/LibSerialize.lua`, `vendor/LibDeflate.lua` (копии из `frost-rotation`), если их не создала часть 1
- Create: `spec/recorded_spec.lua`
- Test: `spec/build_spec.lua`

**Interfaces:**
- Consumes: все модули `src/`, `runtime.start(config, env)`, `runtime.validPlan`, `search.best`, `encode.encode/decode`.
- Produces:
  - `aura.GROUP_ID = "EnhRot"`, `aura.HOST_ID = "EnhRot Timeline"`, `aura.OPTIONS`, `aura.defaultConfig()`, `aura.transmit(initCode, version)`;
  - `build.MODULES`, `build.bundle(dir)`, `build.initCode(dir)`, `build.dump(t)`, `build.findSnapshots(t)`, `build.importSnapshots(path, out) -> n`, `build.main(cmd, a, b)`.
  - Команды:
    - `lua tools/build.lua` → `dist/EnhRot.txt`;
    - `lua tools/build.lua decode <file>`;
    - `lua tools/build.lua import-snapshots <WeakAuras.lua> [out]` → `spec/fixtures/recorded.lua`.

- [ ] **Step 1: Скопировать проверенные кодеки, если их ещё нет**

```bash
test -f tools/encode.lua || cp ../frost-rotation/tools/encode.lua tools/encode.lua
test -f vendor/LibSerialize.lua || { mkdir -p vendor && cp ../frost-rotation/vendor/LibSerialize.lua ../frost-rotation/vendor/LibDeflate.lua vendor/; }
```

- [ ] **Step 2: Написать падающие тесты**

Создать `spec/build_spec.lua`:

```lua
local build = require("build")
local aura = require("aura")
local enc = require("encode")
local G = require("game_mock")
local spells = require("spells")
local runtime = require("runtime")

local function srcModules()
  local out = {}
  local p = io.popen("ls src")
  for f in p:lines() do
    local name = f:match("^(.+)%.lua$")
    if name then out[#out + 1] = name end
  end
  p:close()
  return out
end

local function allKnown()
  local k = {}
  for _, meta in ipairs(spells.CATALOG) do k[meta.ranks[#meta.ranks]] = true end
  return k
end

describe("build", function()
  it("lists every source module and bundles code that compiles", function()
    local listed = {}
    for _, name in ipairs(build.MODULES) do listed[name] = true end
    for _, name in ipairs(srcModules()) do assert.is_true(listed[name] == true, "not in build.MODULES: " .. name) end
    local code = build.initCode("src")
    assert.is_not_nil(loadstring(code))
    for _, name in ipairs(build.MODULES) do
      assert.is_not_nil(code:find('__mods["' .. name .. '"]', 1, true), name)
    end
  end)

  it("uses nothing the WeakAuras sandbox blocks", function()
    local code = build.bundle("src")
    for _, word in ipairs({ "pcall", "xpcall", "loadstring", "setfenv", "getfenv", "_G", "SlashCmdList", "RunScript" }) do
      assert.is_nil(code:find("%f[%w_]" .. word .. "%f[^%w_]"), "blocked word: " .. word)
    end
  end)

  it("round-trips the import string", function()
    local code = build.initCode("src")
    local t = assert(enc.decode(enc.encode(aura.transmit(code))))
    assert.are.equal("EnhRot", t.d.id)
    assert.are.equal(1, #t.c)
    local host = t.c[1]
    assert.are.equal("EnhRot Timeline", host.id)
    assert.are.equal("EnhRot", host.parent)
    assert.are.equal(30300, host.tocversion)
    assert.are.equal(code, host.actions.init.custom)
    local keys = {}
    for _, o in ipairs(host.authorOptions) do keys[#keys + 1] = o.key end
    assert.are.same({ "scale", "seconds", "icons", "mode", "showReason", "showLust", "record", "printDebug" }, keys)
    assert.are.equal("5.22.0", t.s)
  end)

  it("runs as a WeakAuras init action and draws a plan", function()
    G.install({ now = 100, known = allKnown(), castMs = { ["Lightning Bolt"] = 2500 },
                target = { level = 83, hp = 1e6, hpMax = 1e6, guid = "Creature-9" }, inRange = { Stormstrike = 1 },
                enchants = { mh = true, oh = true }, tooltip = { [16] = { "Windfury 8" }, [17] = { "Flametongue 10" } },
                auras = { player = { HELPFUL = { { name = "Lightning Shield", count = 3, expires = 700 } } } } })
    local env = { config = aura.defaultConfig(), region = CreateFrame("Frame"), saved = {} }
    local chunk = assert(loadstring(build.initCode("src")))
    setfenv(chunk, setmetatable({ aura_env = env }, { __index = _G }))
    chunk()
    EnhRotEngineFrame.scripts.OnUpdate(EnhRotEngineFrame, 0.3)
    assert.is_true(runtime.validPlan(env.rt.plan))
    assert.is_true(#env.rt.plan.steps >= 1)
    assert.are.equal("ENHROT_SHOW", G.sent[1][1])
    env.rt.tl:tick(0.016)
    assert.is_true(env.rt.tl.icons[1].shown)
  end)

  it("imports recorded snapshots from SavedVariables", function()
    local sv, out = os.tmpname(), os.tmpname()
    local f = assert(io.open(sv, "wb"))
    f:write('WeakAurasSaved = { displays = { ["EnhRot Timeline"] = { information = { saved = { enhrotSnapshots = { { S = { now = 1 }, plan = { steps = {} } } } } } } } }\n')
    f:close()
    assert.are.equal(1, build.importSnapshots(sv, out))
    assert.are.equal(1, dofile(out)[1].S.now)
    os.remove(sv)
    os.remove(out)
  end)
end)
```

Создать `spec/recorded_spec.lua` — регресс по снимкам, записанным в игре:

```lua
local search = require("search")
local runtime = require("runtime")
local Sc = require("scenario")

local path = "spec/fixtures/recorded.lua"
local f = io.open(path, "rb")

describe("recorded snapshots", function()
  if not f then
    pending("no " .. path .. " yet — record in game and run tools/build.lua import-snapshots")
    return
  end
  f:close()
  for i, rec in ipairs(dofile(path)) do
    it("snapshot #" .. i .. " gives a valid plan of known spells", function()
      local plan = search.best(rec.S, Sc.OPTS)
      assert.is_true(runtime.validPlan(plan))
      for _, st in ipairs(plan.steps) do
        assert.is_true(rec.S.spells[st.key] ~= nil or st.key == "waitSwing" or st.key == "wait", st.key)
      end
      if rec.expect then assert.are.equal(rec.expect, plan.steps[1] and plan.steps[1].key) end
    end)
  end
end)
```

Правило: поле `expect` в фикстуре пользователь или исполнитель дописывает руками, когда в игре замечено неправильное действие. Рядом комментарием — почему правильное именно такое.

- [ ] **Step 3: Убедиться, что тесты падают**

Run: `docker compose run --rm test busted spec/build_spec.lua`
Expected: FAIL — `module 'build' not found`.

- [ ] **Step 4: Реализация ауры**

Создать `tools/aura.lua`:

```lua
local M = {}
M.GROUP_ID = "EnhRot"
M.HOST_ID = "EnhRot Timeline"
M.TOC = 30300
M.WIDTH, M.HEIGHT = 340, 120
M.EVENT = "ENHROT_SHOW"

M.OPTIONS = {
  { type = "range", key = "scale", name = "Scale", min = 0.5, max = 2, step = 0.05, default = 1, width = 1, useDesc = false },
  { type = "range", key = "seconds", name = "Timeline length (s)", min = 3, max = 10, step = 0.5, default = 6, width = 1, useDesc = false },
  { type = "range", key = "icons", name = "Icons on timeline", min = 1, max = 4, step = 1, default = 4, width = 1, useDesc = false },
  { type = "select", key = "mode", name = "Mode", desc = "auto picks solo/group/raid by your group",
    values = { "auto", "solo", "group", "raid", "pvp (reserved)" }, default = 1, width = 1, useDesc = true },
  { type = "toggle", key = "showReason", name = "Show reason under icon", default = true, width = 1, useDesc = false },
  { type = "toggle", key = "showLust", name = "Show Bloodlust ready in group", default = true, width = 1, useDesc = false },
  { type = "toggle", key = "record", name = "Record snapshots for bug reports", default = false, width = 1, useDesc = false },
  { type = "toggle", key = "printDebug", name = "Print debug to chat", default = false, width = 1, useDesc = false },
}

function M.defaultConfig()
  local c = {}
  for _, o in ipairs(M.OPTIONS) do c[o.key] = o.default end
  return c
end

local function animation()
  local none = function() return { type = "none", duration_type = "seconds", easeType = "none", easeStrength = 3 } end
  return { start = none(), main = none(), finish = none() }
end

function M.hostTrigger()
  return [[function(allstates, event)
  if event ~= "ENHROT_SHOW" and event ~= "OPTIONS" then return false end
  allstates[""] = { show = true, changed = true, progressType = "static", value = 0, total = 0, autoHide = false }
  return true
end]]
end

function M.host(initCode)
  return {
    id = M.HOST_ID, uid = "EnhRotHost01", parent = M.GROUP_ID, regionType = "texture",
    internalVersion = 90, tocversion = M.TOC,
    width = M.WIDTH, height = M.HEIGHT, xOffset = 0, yOffset = 0,
    anchorPoint = "CENTER", selfPoint = "CENTER", anchorFrameType = "SCREEN", frameStrata = 1,
    texture = "Interface\\Buttons\\WHITE8X8", color = { 0, 0, 0, 0 }, blendMode = "BLEND",
    rotation = 0, discrete_rotation = 0, rotate = true, mirror = false, desaturate = false, alpha = 1,
    triggers = {
      { trigger = { type = "custom", custom_type = "stateupdate", check = "event", events = M.EVENT,
                    custom = M.hostTrigger(), customVariables = "{}", debuffType = "HELPFUL",
                    unit = "player", names = {}, spellIds = {} },
        untrigger = {} },
      activeTriggerMode = -10, disjunctive = "any",
    },
    load = { use_class = true, class = { single = "SHAMAN", multi = {} }, spec = { multi = {} }, talent = { multi = {} }, size = { multi = {} } },
    actions = { init = { do_custom = true, custom = initCode }, start = {}, finish = {} },
    conditions = {}, animation = animation(), subRegions = {},
    authorOptions = M.OPTIONS, config = M.defaultConfig(), information = {},
  }
end

function M.group(ids)
  return {
    id = M.GROUP_ID, uid = "EnhRotGroup01", regionType = "group", internalVersion = 90, tocversion = M.TOC,
    controlledChildren = ids, anchorPoint = "CENTER", selfPoint = "CENTER", anchorFrameType = "SCREEN",
    xOffset = 0, yOffset = -200, frameStrata = 1, scale = 1, alpha = 1,
    border = false, borderEdge = "Square Full White", borderOffset = 4, borderInset = 1, borderSize = 2,
    borderColor = { 0, 0, 0, 1 }, backdropColor = { 1, 1, 1, 0.5 },
    triggers = { { trigger = { type = "aura2", debuffType = "HELPFUL", unit = "player", names = {}, spellIds = {} }, untrigger = {} } },
    load = { class = { multi = {} }, spec = { multi = {} }, talent = { multi = {} }, size = { multi = {} } },
    actions = { init = {}, start = {}, finish = {} }, animation = animation(), conditions = {},
    subRegions = {}, config = {}, authorOptions = {}, information = {},
  }
end

function M.transmit(initCode, version)
  return { m = "d", d = M.group({ M.HOST_ID }), c = { M.host(initCode) }, v = 1421, s = version or "5.22.0" }
end

return M
```

- [ ] **Step 5: Реализация сборщика**

Создать `tools/build.lua`:

```lua
package.path = "src/?.lua;tools/?.lua;vendor/?.lua;" .. package.path

local B = {}

B.MODULES = { "spells_data", "spells", "talents", "swing", "enemies", "ttd", "damage", "model", "value", "search", "planner", "snapshot", "timeline", "recorder", "runtime" }
B.OUT = "dist/EnhRot.txt"
B.FIXTURE = "spec/fixtures/recorded.lua"

function B.readFile(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

function B.bundle(srcDir)
  local parts = {
    "local __mods = {}\n",
    "local function __require(name)\n  local m = __mods[name]\n  if m == nil then error('EnhRot: module not loaded: ' .. name) end\n  return m\nend\n",
  }
  for _, name in ipairs(B.MODULES) do
    parts[#parts + 1] = ('__mods["%s"] = (function(require)\n%s\nend)(__require)\n'):format(name, B.readFile(srcDir .. "/" .. name .. ".lua"))
  end
  return table.concat(parts)
end

function B.initCode(srcDir)
  return B.bundle(srcDir) .. "__require('runtime').start(aura_env.config or {}, aura_env)\n"
end

function B.dump(t, indent)
  indent = indent or ""
  if type(t) ~= "table" then return type(t) == "string" and ("%q"):format(t) or tostring(t) end
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = { "{\n" }
  for _, k in ipairs(keys) do
    out[#out + 1] = ("%s  [%s] = %s,\n"):format(indent, B.dump(k), B.dump(t[k], indent .. "  "))
  end
  out[#out + 1] = indent .. "}"
  return table.concat(out)
end

function B.findSnapshots(t, seen)
  seen = seen or {}
  if type(t) ~= "table" or seen[t] then return nil end
  seen[t] = true
  if type(t.enhrotSnapshots) == "table" then return t.enhrotSnapshots end
  for _, v in pairs(t) do
    local found = B.findSnapshots(v, seen)
    if found then return found end
  end
  return nil
end

function B.importSnapshots(path, out)
  local chunk = assert(loadfile(path))
  local env = {}
  setfenv(chunk, env)
  chunk()
  local list = assert(B.findSnapshots(env), "no enhrotSnapshots in " .. path)
  os.execute("mkdir -p spec/fixtures")
  local f = assert(io.open(out or B.FIXTURE, "wb"))
  f:write("return " .. B.dump(list) .. "\n")
  f:close()
  return #list
end

function B.main(cmd, a, b)
  local enc = require("encode")
  if cmd == "decode" then
    print(B.dump(assert(enc.decode(B.readFile(a)))))
    return
  end
  if cmd == "import-snapshots" then
    print(("%d snapshots -> %s"):format(B.importSnapshots(a, b), b or B.FIXTURE))
    return
  end
  local aura = require("aura")
  local str = enc.encode(aura.transmit(B.initCode("src")))
  os.execute("mkdir -p dist")
  local f = assert(io.open(B.OUT, "wb"))
  f:write(str)
  f:close()
  print(("%s: %d bytes"):format(B.OUT, #str))
end

if arg and arg[0] and arg[0]:match("build%.lua$") then B.main(arg[1], arg[2], arg[3]) end

return B
```

Если к этому моменту в `src/` есть модули, которых нет в `B.MODULES` (первый тест `build_spec` это покажет), их нужно вставить в список перед первым модулем, который их использует.

- [ ] **Step 6: Прогнать тесты и собрать строку**

Run: `docker compose run --rm test busted spec/build_spec.lua spec/recorded_spec.lua`
Expected: PASS — 5 тестов; `recorded_spec` в статусе pending (фикстуры ещё нет).

Run: `docker compose run --rm test lua tools/build.lua`
Expected: `dist/EnhRot.txt: <N> bytes`, строка начинается с `!WA:2!`.

Run: `docker compose run --rm test lua tools/build.lua decode dist/EnhRot.txt | head -20`
Expected: дамп таблицы: `["m"] = "d"` и группа `EnhRot`.

- [ ] **Step 7: Коммит**

```bash
git add tools/aura.lua tools/build.lua tools/encode.lua vendor spec/build_spec.lua spec/recorded_spec.lua
git commit -m "EnhRot: аура-хост и сборка строки импорта"
```

---

### Task 16: Сверка с wowsims, прокачка, документация, финальная сборка

**Files:**
- Test: `spec/wowsims_spec.lua`
- Test: `spec/leveling_spec.lua`
- Create: `README.md`
- Create: `AGENTS.md`, симлинк `.claude/CLAUDE.md -> ../AGENTS.md`

**Interfaces:**
- Consumes: `spec/support/scenario.lua` (`Sc.state`, `Sc.cd`, `Sc.first`, `Sc.best`), `search.best`.
- Produces: проверочные спеки, `README.md`, `AGENTS.md`, `dist/EnhRot.txt`.

**Правило для расхождений.** Если случай из wowsims падает, сначала ищем ошибку в `damage`/`model`/`value`. Менять ожидание можно только одним способом: добавить действие в `alt` с комментарием, почему оба варианта верны по механике (ссылка на APL или формулу). Удалять случай нельзя.

Порядок APL wowsims, на который опираются ожидания (Default WF):
1. Feral Spirit → Bloodlust → остальные кулдауны.
2. LB при MW = 5.
3. LB при MW ≥ 3, если время каста + 0,3 с меньше времени до следующего удара.
4. Stormstrike.
5. Flame Shock, если спал.
6. Earth Shock.
7. Call of the Elements, если водяному тотему осталось меньше 20 с.
8. Magma Totem, если огненный тотем спал и не стоит Fire Elemental.
9. Fire Nova.
10. Lightning Shield, если слетел.
11. Lava Lash.

Отличия пресетов:
- **Default FT** — без вплетения LB и с Stormstrike без дебаффа после Flame Shock.
- **Phase 3** — Flame Shock первым, если бой продлится ещё ≥ 8 с.

- [ ] **Step 1: Спек сверки с wowsims**

Создать `spec/wowsims_spec.lua`:

```lua
local Sc = require("scenario")

-- every case: level 80 raid boss, MH Windfury / OH Flametongue unless patched.
-- setup(S) mutates the base state; expect = first action; alt = allowed alternatives with a written reason.
local CASES = {
  { name = "pull: Feral Spirit before everything",
    setup = function(S) Sc.cd(S, { feralSpirit = 0 }) end,
    expect = "feralSpirit",
    alt = { fireElemental = "APL: both are 'autocast' cooldowns at pull, order between them does not matter" } },
  { name = "5 Maelstrom: instant Lightning Bolt",
    setup = function(S) S.buffs.mw = { stacks = 5, remains = 20 }; S.target.fs = 10; Sc.cd(S, { stormstrike = 4, shock = 3, lavaLash = 3 }) end,
    expect = "lightningBolt" },
  { name = "5 Maelstrom beats a ready Stormstrike",
    setup = function(S) S.buffs.mw = { stacks = 5, remains = 20 }; S.target.fs = 10; Sc.cd(S, { shock = 3 }) end,
    expect = "lightningBolt" },
  { name = "Stormstrike first when ready and Flame Shock is up",
    setup = function(S) S.target.fs = 10 end,
    expect = "stormstrike" },
  { name = "Flame Shock when it has dropped",
    setup = function(S) Sc.cd(S, { stormstrike = 4 }) end,
    expect = "flameShock" },
  { name = "Earth Shock while Flame Shock ticks",
    setup = function(S) S.target.fs = 9; Sc.cd(S, { stormstrike = 4 }) end,
    expect = "earthShock" },
  { name = "Magma Totem when no fire totem is down",
    setup = function(S) S.target.fs = 9; Sc.cd(S, { stormstrike = 4, shock = 3 }) end,
    expect = "magmaTotem",
    alt = { callOfElements = "Call of the Elements drops Magma Totem too; same fire slot result" } },
  { name = "Fire Nova with Magma Totem down",
    setup = function(S) S.target.fs = 9; S.totems.fire = { kind = "magma", remains = 15 }; Sc.cd(S, { stormstrike = 4, shock = 3 }) end,
    expect = "fireNova" },
  { name = "Lightning Shield when it has dropped",
    setup = function(S)
      S.target.fs = 9; S.totems.fire = { kind = "magma", remains = 15 }; S.buffs.ls = { charges = 0, remains = 0 }
      Sc.cd(S, { stormstrike = 4, shock = 3, fireNova = 4, lavaLash = 3 })
    end,
    expect = "lightningShield" },
  { name = "Lava Lash as the last filler",
    setup = function(S) S.target.fs = 9; S.totems.fire = { kind = "magma", remains = 15 }; Sc.cd(S, { stormstrike = 4, shock = 3, fireNova = 4 }) end,
    expect = "lavaLash" },
  { name = "WF weave: 3 stacks and a long gap before the next swing",
    setup = function(S)
      S.buffs.mw = { stacks = 3, remains = 20 }; S.target.fs = 9; S.totems.fire = { kind = "magma", remains = 15 }
      S.swing.mh.next, S.swing.oh.next = 2.0, 2.2
      Sc.cd(S, { stormstrike = 3, shock = 3, fireNova = 4, lavaLash = 3 })
    end,
    expect = "lightningBolt" },
  { name = "Shamanistic Rage at low mana",
    setup = function(S)
      S.player.mana = S.player.manaMax * 0.1; S.target.fs = 9; S.totems.fire = { kind = "magma", remains = 15 }
      Sc.cd(S, { shamanisticRage = 0, stormstrike = 4, shock = 3, fireNova = 4, lavaLash = 3 })
    end,
    expect = "shamanisticRage" },
  { name = "AoE: Chain Lightning at 5 stacks",
    setup = function(S)
      S.enemies = { melee = 4, nearby = 4 }; S.buffs.mw = { stacks = 5, remains = 20 }; S.target.fs = 9
      S.totems.fire = { kind = "magma", remains = 15 }; Sc.cd(S, { stormstrike = 4, shock = 3, fireNova = 4 })
    end,
    expect = "chainLightning" },
  { name = "AoE: Magma Totem when no fire totem",
    setup = function(S) S.enemies = { melee = 4, nearby = 4 }; S.target.fs = 9; Sc.cd(S, { stormstrike = 4, shock = 3 }) end,
    expect = "magmaTotem",
    alt = { callOfElements = "Call of the Elements drops Magma Totem too" } },
  { name = "AoE: Fire Nova with Magma down",
    setup = function(S)
      S.enemies = { melee = 4, nearby = 4 }; S.target.fs = 9; S.totems.fire = { kind = "magma", remains = 15 }
      Sc.cd(S, { stormstrike = 4, shock = 3 })
    end,
    expect = "fireNova" },
  { name = "FT build: Stormstrike when ready",
    setup = function(S) S.weapons.mh.enchant = "ft"; S.target.fs = 10 end,
    expect = "stormstrike" },
  { name = "Phase 3: Flame Shock missing with 5 stacks",
    setup = function(S) S.buffs.mw = { stacks = 5, remains = 20 }; Sc.cd(S, { stormstrike = 4 }) end,
    expect = "lightningBolt",
    alt = { flameShock = "Phase 3 preset puts Flame Shock (fight >= 8 s) above 5-stack LB; Default WF does the opposite" } },
  { name = "Call of the Elements when the water totem is expiring",
    setup = function(S)
      S.totems.water.remains = 5; S.target.fs = 9; S.totems.fire = { kind = "magma", remains = 3 }
      Sc.cd(S, { stormstrike = 4, shock = 3, fireNova = 4, lavaLash = 3 })
    end,
    expect = "callOfElements",
    alt = { magmaTotem = "Magma expires in 3 s as well; replacing it first loses only the water refresh" } },
}

local function instant(key, at)
  return at <= 0.1
end

describe("wowsims APL agreement at level 80", function()
  for _, c in ipairs(CASES) do
    it(c.name, function()
      local S = Sc.state(80)
      c.setup(S)
      local key, at = Sc.first(S)
      local ok = key == c.expect or (c.alt and c.alt[key] ~= nil)
      assert.is_true(ok, ("expected %s, got %s"):format(c.expect, tostring(key)))
      assert.is_true(instant(key, at), ("%s should be pressed now, planned at %s"):format(tostring(key), tostring(at)))
    end)
  end

  it("does not start a Bolt right before a swing at 3 stacks", function()
    local S = Sc.state(80)
    S.buffs.mw = { stacks = 3, remains = 20 }; S.target.fs = 9; S.totems.fire = { kind = "magma", remains = 15 }
    S.swing.mh.next, S.swing.oh.next = 0.4, 1.7
    Sc.cd(S, { stormstrike = 3, shock = 3, fireNova = 4, lavaLash = 3 })
    local key, at = Sc.first(S)
    assert.is_false(key == "lightningBolt" and at < 0.35, "Bolt would delay the swing in 0.4 s")
  end)

  it("never hard-casts a 0-stack Bolt in melee", function()
    local S = Sc.state(80)
    S.target.fs = 9; S.totems.fire = { kind = "magma", remains = 15 }
    S.swing.mh.next, S.swing.oh.next = 0.5, 1.8
    Sc.cd(S, { stormstrike = 3, shock = 3, fireNova = 4, lavaLash = 3 })
    local key = Sc.first(S)
    assert.are_not.equal("lightningBolt", key)
  end)

  it("does not put Magma Totem over an active Fire Elemental", function()
    local S = Sc.state(80)
    S.target.fs = 9; S.totems.fire = { kind = "fireElemental", remains = 90 }
    Sc.cd(S, { stormstrike = 4, shock = 3 })
    for _, st in ipairs(Sc.best(S).steps) do assert.are_not.equal("magmaTotem", st.key) end
  end)
end)
```

- [ ] **Step 2: Спек прокачки**

Создать `spec/leveling_spec.lua`:

```lua
local Sc = require("scenario")

local WAIT = { waitSwing = true, wait = true }

local function situations(level)
  local fresh = Sc.state(level)
  local busy = Sc.state(level)
  busy.target.fs = 9
  busy.totems.fire = { kind = "searing", remains = 30 }
  for key in pairs(busy.spells) do busy.spells[key].cd = 3 end
  local stacked = Sc.state(level, { buffs = { mw = { stacks = 5, remains = 20 } } })
  local dying = Sc.state(level)
  dying.target.hp, dying.target.hpPct, dying.target.ttd = dying.target.hpMax * 0.05, 0.05, 2
  return { fresh = fresh, busy = busy, stacked = stacked, dying = dying }
end

describe("leveling", function()
  for level = 1, 80, 3 do
    it("level " .. level .. " never suggests an unknown spell", function()
      for name, S in pairs(situations(level)) do
        for _, st in ipairs(Sc.best(S).steps) do
          assert.is_true(S.spells[st.key] ~= nil or WAIT[st.key] == true, ("level %d %s: %s is not known"):format(level, name, st.key))
        end
      end
    end)
  end

  it("level 10: Flame Shock on a fresh mob", function()
    assert.are.equal("flameShock", (Sc.first(Sc.state(10))))
  end)

  it("level 10 knows no Stormstrike, Lava Lash or Maelstrom", function()
    local S = Sc.state(10)
    assert.is_nil(S.spells.stormstrike)
    assert.is_nil(S.spells.lavaLash)
    assert.is_nil(S.weapons.oh)
  end)

  it("level 25: Earth Shock while Flame Shock ticks", function()
    local S = Sc.state(25)
    S.target.fs = 10
    assert.are.equal("earthShock", (Sc.first(S)))
  end)

  it("level 35: a fire totem when shocks are on cooldown", function()
    local S = Sc.state(35)
    S.target.fs = 10
    Sc.cd(S, { shock = 4 })
    local key = Sc.first(S)
    assert.is_true(key == "searingTotem" or key == "magmaTotem", tostring(key))
  end)

  it("level 42: Stormstrike once learned", function()
    local S = Sc.state(42)
    S.target.fs = 10
    assert.are.equal("stormstrike", (Sc.first(S)))
  end)

  it("level 50: Lava Lash as filler", function()
    local S = Sc.state(50)
    S.target.fs = 10
    S.totems.fire = { kind = "searing", remains = 30 }
    Sc.cd(S, { stormstrike = 4, shock = 3, fireNova = 4 })
    assert.are.equal("lavaLash", (Sc.first(S)))
  end)

  it("level 58: 5 Maelstrom stacks go into Lightning Bolt", function()
    local S = Sc.state(58)
    S.target.fs = 10
    S.buffs.mw = { stacks = 5, remains = 20 }
    Sc.cd(S, { stormstrike = 4, shock = 3 })
    assert.are.equal("lightningBolt", (Sc.first(S)))
  end)

  it("solo: no Flame Shock on a mob about to die", function()
    local S = Sc.state(30)
    S.target.hp, S.target.hpPct, S.target.ttd = S.target.hpMax * 0.1, 0.1, 3
    assert.are_not.equal("flameShock", (Sc.first(S)))
  end)
end)
```

- [ ] **Step 3: Прогнать проверочные спеки**

Run: `docker compose run --rm test busted spec/wowsims_spec.lua spec/leveling_spec.lua`
Expected: PASS. Если что-то падает — чинить `damage`/`model`/`value`/`search` по правилу выше. В каждом исправлении — регресс-тест в спеке того модуля, где была ошибка.

- [ ] **Step 4: Полный прогон и сборка**

Run: `docker compose run --rm test busted`
Expected: все спеки зелёные, `recorded_spec` в статусе pending.

Run: `docker compose run --rm test lua tools/build.lua`
Expected: `dist/EnhRot.txt: <N> bytes`.

- [ ] **Step 5: README**

Создать `README.md`:

````markdown
# EnhRot — подсказчик для энх-шамана (WotLK 3.3.5a)

WeakAura для клиента 3.3.5a с WeakAuras 5.22 (бэкпорт). Показывает на ленте времени, что нажать сейчас и что потом, когда будут удары оружием и когда можно кастовать Lightning Bolt, не сбивая удар.

## Установка
1. `docker compose run --rm test lua tools/build.lua`
2. Открыть `dist/EnhRot.txt`, скопировать всю строку.
3. В игре: `/wa` → Import → вставить → Import.
4. Двигать ленту: `/wa` → группа `EnhRot` → перетащить мышкой.

## Что на ленте
- **Жёлтая черта** — «сейчас». Крупная иконка на ней — жми это.
- **Иконки правее** — что будет дальше, каждая в своей точке времени (шкала 6 с).
- **Внизу черточки** — будущие удары: золотые — правая рука, серые — левая.
- **Зелёная полоса** — окно, где можно начать Lightning Bolt при 1–4 стаках Maelstrom, и удар не задержится.
- **Светлая полоса** — общая перезарядка.
- **5 точек справа сверху** — стаки Maelstrom Weapon.
- **Иконка слева** — предупреждение: нет Lightning Shield, нет чар на оружии, мало маны (Shamanistic Rage), цель далеко, в группе — Bloodlust готов.
- **Текст под крупной иконкой** — почему это действие.

## Настройки
`/wa` → `EnhRot Timeline` → вкладка Custom Options:
- **Scale** — масштаб.
- **Timeline length** — длина шкалы.
- **Icons on timeline** — сколько иконок на ленте.
- **Mode** — `auto`, `solo`, `group`, `raid`. `pvp` пока пустой.
- **Show reason** — текст под крупной иконкой.
- **Show Bloodlust ready** — значок «Bloodlust готов» в группе.
- **Record snapshots** — запись ситуаций для отчёта об ошибке.
- **Print debug to chat** — печатать план в чат при каждой смене.

## Проверки в игре на первом запуске
1. **Здоровье мобов.** Взять моба в цель и ввести `/run print(UnitHealthMax("target"))`.
   - Число вроде `12600` — всё хорошо.
   - `100` — клиент отдаёт проценты. Подсказчик тогда оценивает здоровье по уровню моба: работать будет, но хуже решает, «добивать ли дорогим заклинанием».
2. **Сбивают ли мгновенные заклинания удар.** Включить Print debug, встать у манекена, трижды нажать Earth Shock посреди полоски удара, потом так же Stormstrike и Lava Lash. Часы ударов запомнят, как это устроено на сервере. Результат хранится в сохранённых данных ауры.
3. **Вплетание Bolt.** При 3–4 стаках Maelstrom Bolt должен появляться на ленте ровно в зелёном окне, а черточка удара после каста — не сдвигаться.

## Если подсказка неправильная
1. Включить **Record snapshots**, повторить ситуацию, выйти из игры (данные пишутся при выходе).
2. Прислать файл `WTF/Account/<АККАУНТ>/SavedVariables/WeakAuras.lua`.
3. Разработчик: `docker compose run --rm test lua tools/build.lua import-snapshots path/to/WeakAuras.lua`. В `spec/fixtures/recorded.lua` у нужного снимка дописать `expect = "<правильное действие>"` с комментарием, почему оно правильное. Затем `docker compose run --rm test busted spec/recorded_spec.lua`.

## Ограничения
- Число врагов рядом клиент 3.3.5a не отдаёт. Оно оценивается по боевому логу: кто бил тебя и кого бил ты за последние секунды.
- Проки тринкетов в расчёт пока не входят.
- Команды `/enhrot` нет: WeakAuras не даёт аурам регистрировать слеш-команды. Отладка — через опцию Print debug.
````

- [ ] **Step 6: AGENTS.md**

Создать `AGENTS.md`:

```markdown
# EnhRot

WeakAura-подсказчик для энх-шамана под WotLK 3.3.5a (WeakAuras 5.22 backport): мини-симулятор на 6 с вперёд + лента времени + часы ударов.

- Тесты: `docker compose run --rm test busted`
- Один файл: `docker compose run --rm test busted spec/search_spec.lua`
- Сборка строки импорта: `docker compose run --rm test lua tools/build.lua` → `dist/EnhRot.txt`
- Декодировать строку: `docker compose run --rm test lua tools/build.lua decode <file>`
- Снимки из игры в тесты: `docker compose run --rm test lua tools/build.lua import-snapshots <WeakAuras.lua>`
- Данные рангов: `src/spells_data.lua` генерируется из `data/Spell.dbc` (не в git), руками не править.
- Спецификация: `docs/superpowers/specs/2026-09-30-enh-rotation-design.md`; план: `docs/superpowers/plans/2026-09-30-enh-rotation.md`.

Конвенции:
- Lua 5.1. В `src/` нельзя `pcall`, `loadstring`, `setfenv`, `getfenv`, `_G`, `SlashCmdList` — это песочница WeakAuras.
- API игры читают только `snapshot`, `runtime`, `timeline`; остальные модули — чистые функции над `S`.
- Тексты в игре — на английском. Новый модуль в `src/` — добавить в `tools/build.lua` `B.MODULES`.
```

```bash
mkdir -p .claude && ln -sf ../AGENTS.md .claude/CLAUDE.md
```

- [ ] **Step 7: Коммит**

```bash
git add spec/wowsims_spec.lua spec/leveling_spec.lua README.md AGENTS.md .claude/CLAUDE.md
git commit -m "EnhRot: сверка с wowsims, проверки прокачки, README"
```

- [ ] **Step 8: Документация проекта**

У проекта нет `.claude/docs/`. Поэтому в отчёте пользователю — одной строкой предложить `/docs-init`: он создаст структуру и `ARCHITECTURE.md`. Вызывать DocsKeeper до этого не нужно.

---

## Предложения для Review Focus (из этой части)

1. **У моба нет абсолютного здоровья** (`UnitHealthMax == 100`). Здоровье оценивается по уровню и классификации, `guessed = true`. Покрыто тестом `snapshot`: «guesses mob health».
2. **Цель умерла или сменилась посреди плана.** Немедленный пересчёт с `kind = "target"`. Покрыто тестами `runtime`: «replans when the current target dies», «rescans spells…».
3. **Каст Bolt прерван движением.** Часы ударов получают `onCastEnd(ok = false)` и не сбрасывают таймер. Покрыто тестом `runtime`: «reports an interrupted cast».
4. **Перезагрузка ауры** (`/reload`, смена опций). Движок работает на одном фрейме, старая лента скрыта, `OnUpdate` у неё снят. Покрыто тестом `runtime`: «registers 3.3.5 events only and reuses the engine frame».
5. **Двуручник до 40 уровня, левой руки нет.** `weapons.oh = nil`, `swing.oh = nil`, серых отметок нет. Покрыто тестами `snapshot` («has no off-hand…») и `timeline` («works with a single two-handed weapon»).
