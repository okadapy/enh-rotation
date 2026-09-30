# EnhRot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** WeakAura-подсказчик для Enhancement Shaman (WotLK 3.3.5a) с мини-симулятором на ~6 с вперёд, лентой времени и часами ударов.

**Architecture:** Чистые Lua-модули в `src/` (без API игры, кроме `snapshot`/`runtime`/`timeline`), склеиваются `tools/build.lua` в init-код одной ауры-хоста и кодируются в строку `!WA:2!`. Данные рангов заклинаний генерируются из `data/Spell.dbc` клиента в `src/spells_data.lua`.

**Tech Stack:** Lua 5.1, busted 2.2 в Docker (`nickblah/lua:5.1-luarocks-alpine` + python3 для генератора), LibSerialize/LibDeflate (vendor из `frost-rotation`).

**Spec:** `docs/superpowers/specs/2026-09-30-enh-rotation-design.md`

## Global Constraints

- Lua 5.1; в `src/` запрещены `pcall`, `loadstring`, `setfenv`, `getfenv`, `_G` (проверяется тестом сборки).
- Клиент 3.3.5a, `## Interface: 30300`, WeakAuras 5.22 backport: `internalVersion = 90`, `tocversion = 30300`, строка импорта `!WA:2!`, `s = "5.22.0"`.
- Иконки — только пути `Interface\\Icons\\...`.
- Все тексты в игре — английские.
- Бюджет одного поиска — `BUDGET_MS = 2`.
- Горизонт поиска — `HORIZON = 6.0` с, ширина луча `BEAM = 6`, глубина `DEPTH = 4`.
- Гистерезис плана — `HYSTERESIS = 0.03`.
- Пульс ленты — `PULSE = 0.25` с.
- Допуск определения руки удара — `HAND_TOLERANCE = 0.25` с.
- Калибровка сброса удара мгновенными — `CALIBRATE_VOTES = 3`.
- Все команды — через Docker: `docker compose run --rm test <cmd>`.
- Коммиты — по-русски, без упоминания Claude/AI.

## Review Focus

1. **Нет левой руки** (двуручник до 40 уровня): `weapons.oh = nil`, `swing.oh = nil`, Lava Lash недоступен, серых отметок нет — ни один модуль не падает на `nil`. Тесты: Task 4, 7, 8, 12, 13.
2. **Цель умирает посреди горизонта или сменилась посреди плана:** после смерти нет урона от автоатак/DoT/тотемов, урон сверх здоровья в соло не ценится, планировщик сразу пересчитывает. Тесты: Task 8, 9, 14.
3. **Нечего нажимать** (нет цели, нет маны, всё за горизонтом, уровень 1): пустой план с `value = 0`, лента пустая, ошибок Lua нет. Тесты: Task 10, 11, 14.
4. **Неизвестные данные цели:** уровень −1 (босс → +3, броня босса), только проценты здоровья (`hpMax == 100` → оценка, `guessed = true`). Тесты: Task 7, 12.
5. **Прерванный каст и отрицательная ценность плана:** `onCastEnd(ok=false)` не сбрасывает удары; гистерезис считается от `|old|`. Тесты: Task 4, 11, 14.

---

## Контракт модулей (общий для всех задач)

Каждая задача обязана использовать эти имена и формы. Модуль — файл `src/<name>.lua`, возвращает таблицу `M`. В тестах модули грузятся через `require("<name>")`; `lpath` в `.busted`: `src/?.lua;spec/support/?.lua;tools/?.lua;vendor/?.lua`.

### Состояние `S` (снимок, его же копирует и сдвигает `model`)

Все времена — секунды **от `S.now`** (остатки), кроме `S.now`.

```lua
S = {
  now = 100.0,            -- GetTime()
  gcdRemains = 0,         -- до конца общей перезарядки
  castRemains = 0,        -- до конца текущего каста
  gcd = 1.5,              -- длительность GCD с хастом, >= 1.0
  latency = 0.15,         -- пинг + 0.1
  mode = "solo",          -- "solo" | "group" | "raid" | "pvp"
  player = {
    level = 80, mana = 8000, manaMax = 10000, baseMana = 4396,
    hpPct = 1.0, ap = 4000, spNature = 1200, spFire = 1200,
    meleeCrit = 0.30, spellCrit = 0.20,   -- доли 0..1
    meleeHit = 0.08, spellHit = 0.10,     -- бонус к попаданию, доли
    spellHaste = 1.10, meleeHaste = 1.25, -- множители (>=1)
    moving = false, inCombat = true,
  },
  weapons = {
    mh = { speed = 2.6, min = 600, max = 900, enchant = "wf" }, -- enchant: "wf"|"ft"|"rb"|nil
    oh = { speed = 2.6, min = 600, max = 900, enchant = "ft" }, -- nil если нет левой руки
  },
  talents = { },          -- ключ -> ранг, ключи определяет talents.KEYS
  spells = {              -- только выученные; ключи = spells.CATALOG[i].key
    stormstrike = { id = 17364, rank = 1, cd = 0, cost = 351, cast = 0 },
  },
  buffs = {
    mw = { stacks = 0, remains = 0 },     -- Maelstrom Weapon
    ls = { charges = 0, remains = 0 },    -- Lightning Shield
    flurry = { charges = 0, remains = 0 },
    rage = 0, lust = 0, em = 0,           -- остатки: Shamanistic Rage, Bloodlust/Heroism, Elemental Mastery
  },
  target = {
    exists = true, enemy = true, level = 83, hp = 1e6, hpMax = 1e6, hpPct = 1.0,
    ttd = 60,              -- оценка времени жизни, nil если неизвестно
    range = "melee",       -- "melee" | "20" | "30" | "far"
    fs = 0,                -- остаток Flame Shock
    ss = { charges = 0, remains = 0 }, -- Stormstrike debuff
    guessed = false,
  },
  totems = { fire = { kind = nil, remains = 0 }, water = { remains = 0 } }, -- kind: "searing"|"magma"|"fireElemental"|nil
  swing = {
    attacking = true,
    mh = { next = 1.2, speed = 2.6 },     -- next: до следующего удара
    oh = { next = 0.4, speed = 2.6 },     -- nil если нет левой руки
    resetByInstant = { },                 -- ключ заклинания -> true, если калибровка показала сброс
  },
  enemies = { melee = 1, nearby = 1 },
  inflight = { },                         -- ключ -> остаток до подтверждения (<=1 с)
}
```

### Действия

Ключи действий: `stormstrike`, `lavaLash`, `earthShock`, `flameShock`, `frostShock`, `lightningBolt`, `chainLightning`, `searingTotem`, `magmaTotem`, `fireNova`, `fireElemental`, `callOfElements`, `lightningShield`, `shamanisticRage`, `feralSpirit`. Служебные: `waitSwing`, `wait` (с аргументом `dt`).

### Сигнатуры

```lua
-- spells.lua
spells.CATALOG      -- массив { key, name, ranks = {ids...}, gcd = 1.5|1.0|0, cd = сек, sharedCd = "shock"|nil,
                    --   school = "nature"|"fire"|"frost"|"physical", castBase = сек (2.5 для LB/2.0 для CL, 0 иначе),
                    --   weapon = true|nil (Stormstrike/Lava Lash), totem = "fire"|nil, icon = "Interface\\Icons\\..." }
spells.byKey[key]   -- элемент CATALOG
spells.rank(key, id) -> элемент spells_data[key] для ID ранга или nil

-- spells_data.lua (генерируется tools/spelldata.py, не править руками)
spells_data[key] = { { id=, level=, min=, max=, coef=, tick=, tickCoef=, ticks= }, ... } -- по возрастанию level

-- talents.lua
talents.KEYS        -- массив { key, tab, index, name }
talents.read(getTalentInfo) -> { [key] = rank }  -- getTalentInfo(tab, index) как GetTalentInfo 3.3.5

-- damage.lua (ожидаемые значения, одна цель)
damage.action(S, key) -> dmg            -- мгновенный урон действия (+ урон тиков внутри ttd для DoT)
damage.dot(S, key) -> perTick, ticks, period
damage.auto(S, hand) -> dmg             -- ожидаемый урон одного автоудара hand="mh"|"oh" (с WF/FT)
damage.mwPerSwing(S, hand) -> stacks    -- ожидаемый прирост стаков Maelstrom за удар
damage.targets(S, key) -> n             -- сколько целей заденет (AoE)

-- model.lua (чистая функция, S не мутирует)
model.readyIn(S, key) -> сек | nil      -- через сколько можно нажать (nil = нельзя в горизонте: не выучено/нет маны/нет цели/далеко)
model.castTime(S, key) -> сек           -- с учётом стаков MW и хаста
model.apply(S, key) -> S2, dmg, dt      -- нажать сейчас (readyIn должен быть <= 0.05)
model.wait(S, dt) -> S2, dmg            -- прошло dt: автоатаки, тики, остатки
model.actions(S) -> { {key=, readyIn=}, ... }  -- кандидаты на следующий шаг, включая waitSwing

-- value.lua
value.WEIGHTS[mode] -> { mana =, overkill =, kill = }
value.step(S, S2, dmg, manaSpent) -> v  -- ценность одного шага с учётом режима
value.terminal(S) -> v                  -- остаточная ценность в конце цепочки

-- search.lua
search.best(S, opts) -> plan            -- opts: { horizon, beam, depth, budgetMs, clock = function() -> ms }
-- plan = { value = число, steps = { { key =, at = сек от S.now, reason = "text" }, ... }, timedOut = bool }

-- planner.lua
planner.new(opts) -> p
p:update(S, ev) -> plan                 -- ev: { kind = "pulse"|"cast"|"aura"|"swing"|"target"|"power"|"totem", key = ... }

-- swing.lua
swing.new() -> c
c:onSwing(now, isExtra)                 -- SWING_DAMAGE/SWING_MISSED от игрока
c:onExtraAttacks(now, count)            -- SPELL_EXTRA_ATTACKS
c:onSpeed(now, mhSpeed, ohSpeed)        -- UNIT_ATTACK_SPEED
c:onCastStart(now, key, mwStacks, castTime)
c:onCastEnd(now, key, mwStacks, ok)     -- ok=false при прерывании
c:onInstant(now, key)                   -- для калибровки
c:state(now) -> { attacking, mh = {next, speed}, oh = {next, speed}|nil, resetByInstant = {} }
c:castWindow(now, castTime, latency) -> startIn, endIn | nil  -- окно, где каст не задержит удар
c.saved                                 -- таблица калибровки (кладётся в aura_env.saved)

-- enemies.lua / ttd.lua
enemies.new() -> e; e:onEvent(now, subEvent, srcGUID, dstGUID, playerGUID); e:counts(now) -> melee, nearby
ttd.new() -> t; t:add(now, guid, hpPct); t:estimate(now, guid) -> сек|nil

-- snapshot.lua (единственный, кто читает API игры, кроме runtime/timeline)
snapshot.build(ctx) -> S               -- ctx: { swing = c, enemies = e, ttd = t, inflight = {}, mode = "auto"|..., now = GetTime() }

-- timeline.lua
timeline.new(parent, opts) -> tl; tl:render(plan, S, now); tl:setAlert(alert)
-- runtime.lua
runtime.start(config, env)             -- env = aura_env
-- recorder.lua
recorder.new(saved, max) -> r; r:push(S, plan)
```

---

## Контракт v2 — сведение частей (ОБЯЗАТЕЛЕН, главнее текста частей)

Части `parts/0N-*.md` писались параллельно. Где часть расходится с этим разделом, **прав этот раздел**; исполнитель правит свой код под него, а не наоборот. Все «Contract additions» из частей действуют, если здесь не сказано иное.

### Решения по конфликтам

1. **`src/util.lua` создаёт Task 1** (в части 1 его нет — добавить). Содержимое:
   ```lua
   local M = {}
   function M.copy(t)
     if type(t) ~= "table" then return t end
     local r = {}
     for k, v in pairs(t) do r[k] = M.copy(v) end
     return r
   end
   function M.merge(dst, patch)
     for k, v in pairs(patch or {}) do
       if type(v) == "table" and type(dst[k]) == "table" then M.merge(dst[k], v) else dst[k] = M.copy(v) end
     end
     return dst
   end
   function M.clamp(x, lo, hi) if x < lo then return lo elseif x > hi then return hi end return x end
   return M
   ```
   `model.copy` (часть 3) = `util.copy`, отдельную реализацию не писать.
2. **`talents.read(numTabs, numTalents, info)`** — вариант части 1 (три функции). `snapshot` вызывает `talents.read(GetNumTalentTabs, GetNumTalents, GetTalentInfo)`. Ключи — из части 1; ключ `dualWieldSpecialization` (не `dualWieldSpec`). Нужные части 3 ключи (`concussion, callOfFlame, elementalFury, reverberation, improvedFireNova, improvedShields, elementalWeapons, staticShock, maelstromWeapon`) обязаны быть в `talents.KEYS`.
3. **`spells_data[key][i].id` — ID заклинания, которое изучает и нажимает игрок** (для `IsSpellKnown`, `GetSpellInfo`, `UnitSpellcast`), числа урона — из парного ID урона (таблица `RANKS` части 1). Поле `dmgId` добавить в строку для отладки. У `flameShock` поле `period = 3` пишет генератор.
4. **`damage.action(S, key)` — только мгновенная часть урона** (часть 3, п. 6). Тики, тотемы, питомцы — в `model.advance`.
5. **`damage.dot(S, key) -> perPulse, pulses, period`** поддерживает `flameShock` (тики), `magmaTotem` и `searingTotem` (пульс/выстрел тотема; `pulses = floor(duration/period)`; `period` = `M.MAGMA_PERIOD` / `M.SEARING_PERIOD`); иначе `0, 0, 1`. Часть 3 дописывает ветки тотемов.
6. **`fixtures.state()` по умолчанию `mode = "group"`** (часть 1 пишет `"raid"` — заменить), плюс поля части 3: `weapons.mh.twoHand = nil`, `target.dead = nil`, `target.armor = nil`, `pets = { wolves = 0 }`; `swing.attacking = true`; все 15 действий выучены с `cd = 0`; `target.hp = hpMax = 1e6`, `ttd = 60`; `totems.fire.kind = false` означает «тотема нет» (и `nil` тоже — код обязан понимать оба).
7. **`model.*`** соблюдает пп. 4–7 части 4: детерминированный порядок `model.actions` по `spells.CATALOG`, `waitSwing` последним с `readyIn = min(mh.next, oh.next) + 0.01`, фильтр `readyIn < HORIZON`, `readyIn >= max(gcdRemains, castRemains)`, `apply` сдвигает `now` на `dt` и уменьшает `target.hp` (не ниже 0), `dmg` включает всё за `dt`.
8. **`swing.new(saved)`** (часть 2). `runtime` передаёт `aura_env.saved.swing`, заводя таблицу при отсутствии. `S.swing.resetByInstant` = `c.saved.reset` (только значения `true`).
9. **Время.** В `S` — остатки от `S.now`; внутри `swing`/`enemies`/`ttd` — абсолютные моменты. Конвертирует только `snapshot`.

### Решения по части 5

10. **`runtime` создаёт `swing.new(aura_env.saved.swing)`** (п. 8); `swing` всё равно читает `self.saved` при каждом обращении — `runtime` может подменить таблицу позже.
11. **Моки.** Общий мок — `spec/support/wow_mock.lua` (волна 1). Task 12–14 могут завести **свои** файлы `spec/support/game_mock.lua` и `spec/support/scenario.lua` (их владелец — исполнитель Task 12–16), но не правят `wow_mock.lua`/`fixtures.lua`/`stubs.lua`.
12. **`talents.standard(level)`** (нужна `scenario`) добавляет Task 16 в волне 3 — в волне 2 `talents.lua` не трогать.
13. **`build.MODULES`** порядок: `util, spells_data, spells, talents, swing, enemies, ttd, damage, model, value, search, planner, snapshot, timeline, recorder, runtime`.
14. **`totems.fire.kind = "other"`** — чужой/неизвестный огненный тотем; Fire Nova при нём доступна (`model.readyIn` обязан это учитывать).
15. `spells.CATALOG[i].ranks` — строго по возрастанию уровня; поля `name`, `icon` обязательны.
16. Слэш-команды нет (WeakAuras блокирует `SlashCmdList`) — опция `printDebug`. `UNIT_POWER` в 3.3.5a нет — `UNIT_MANA`.

### Заглушки для параллельной разработки

Task 1 создаёт `spec/support/stubs.lua` — общие поддельные модули. Модуль, который тестируется до готовности соседей, подменяет их через `package.loaded[...] = stubs.X()` в `before_each` и восстанавливает в `after_each` (или через `opts.model/opts.value` там, где это предусмотрено).

```lua
local S = {}
-- damage: фиксированные числа, не зависят от характеристик
function S.damage(over)
  local N = { stormstrike = 2000, lavaLash = 1500, earthShock = 1800, flameShock = 900, frostShock = 1600,
              lightningBolt = 2500, chainLightning = 2200, searingTotem = 0, magmaTotem = 0, fireNova = 900,
              fireElemental = 0, callOfElements = 0, lightningShield = 0, shamanisticRage = 0, feralSpirit = 0 }
  for k, v in pairs(over or {}) do N[k] = v end
  return {
    action = function(_, key) return N[key] or 0 end,
    dot = function(_, key)
      if key == "flameShock" then return 300, 4, 3 elseif key == "magmaTotem" then return 400, 10, 2
      elseif key == "searingTotem" then return 250, 24, 2.5 end
      return 0, 0, 1
    end,
    periodic = function(_, src) return ({ flameShock = 100, magmaTotem = 200, searingTotem = 100, fireElemental = 500, feralSpirit = 400 })[src] or 0 end,
    auto = function(_, hand) return hand == "oh" and 400 or 800 end,
    mwPerSwing = function() return 0.3 end,
    targets = function(S_, key)
      local n = math.max(1, (S_.enemies and S_.enemies.nearby) or 1)
      if key == "fireNova" or key == "magmaTotem" then return n elseif key == "chainLightning" then return math.min(n, 3) end
      return 1
    end,
  }
end
return S
```
Игрушечную модель для поиска (`spec/support/stub_model.lua`) создаёт Task 10 (часть 4), как там описано.

### Интеграционные тесты

Тесты, которым нужны **настоящие** соседние модули (реальный `model` в `search_spec`/`planner_spec`, `stability_spec`, `perf_spec`, `wowsims_spec`, `leveling_spec`), помечаются тегом busted `#integration` (`describe("... #integration", ...)`). В волне 2 исполнитель гоняет `busted --exclude-tags=integration spec/<свой>_spec.lua`; интеграционные включаются в волне 3.

## Порядок выполнения (волны)

| Волна | Задачи | Кто | Условие старта |
|---|---|---|---|
| 1 | Task 1 → Task 2 → Task 3 (каркас, `util`, `stubs`, мок, фикстуры, генератор, `spells_data`, `spells`, `talents`) | один исполнитель | — |
| 2 | Task 4–6 · Task 7–8 · Task 9–11 · Task 12–14 · Task 15 | пять исполнителей одновременно, каждый только свои `src/*.lua` и `spec/*_spec.lua` | волна 1 закоммичена; общие файлы (`spec/support/*`, `util`, `spells*`, `talents`) заморожены |
| 3 | Интеграционные тесты + Task 16 (сверка с wowsims, прокачка, подкрутка весов), полный прогон | один исполнитель | волна 2 закоммичена |
| 4 | Итоговое ревью ветки, README, GitHub (публичный `okadapy/enh-rotation`), релиз `v0.1.0` с `dist/EnhRot.txt` | координатор | полный прогон зелёный |

Изменить общий файл в волне 2 нельзя; если без этого никак — исполнитель описывает нужную правку в отчёте, координатор вносит её сам и сообщает остальным.

## Задачи

Тексты задач — в частях (порядок номеров сквозной):

- `parts/01-scaffold-data.md` — Task 1–3
- `parts/02-swing-enemies-ttd.md` — Task 4–6
- `parts/03-damage-model.md` — Task 7–8
- `parts/04-value-search-planner.md` — Task 9–11
- `parts/05-game-glue-verify.md` — Task 12–16
