# Разбор боя с советами — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** после каждого боя аддон даёт разбор: насколько игрок следовал подсказке, сколько урона это стоило, 3–5 советов; строка в чат, окно `/dmr last`, история по боссам между сессиями.

**Architecture:** движок (`src/`) отдаёт только оценки первых кнопок из уже идущего поиска (`firstValue`) и одну зацепку `env.onPress`. Всё остальное — модули аддона: сборщик за бой (`fightlog`), чистые советы (`advice`), история (`history`), окно (`fightwin`) и связка с событиями игры (`review`), подключённая в `core`.

**Tech Stack:** Lua 5.1, клиент WotLK 3.3.5a, busted 2.2 в Docker.

**Spec:** `docs/superpowers/specs/2026-10-01-fight-review-design.md`

## Global Constraints

- Все команды — в контейнере: `docker compose run --rm test busted <spec>`; весь набор — `docker compose run --rm test busted`; скорость — `docker compose run --rm test busted --tags=perf`.
- Lua 5.1. В `src/` нельзя `pcall`, `loadstring`, `setfenv`, `getfenv`, `_G`, `SlashCmdList`, `package`, `io`, `debug` — даже в комментариях (проверяет `spec/build_spec.lua`). В `addon/` нет `io`, `package`, `debug`; `require` разрешает сборка.
- Ускорения и правки поиска — только с тем же результатом бит в бит (`value`, `nodes`, шаги): порядок операций с плавающей точкой не менять. Весь набор тестов должен остаться зелёным без правки ожиданий.
- Лимиты `spec/perf_spec.lua`: в среднем ≤ 6 мс, ≤ 600 тыс. инструкций, ≤ 300 КБ мусора на поиск — не должны заметно вырасти.
- Тексты в игре — на английском, только ASCII (дефис `-`, не тире).
- Новые модули аддона — в `tools/build.lua` `B.ADDON_MODULES` (перед `core`), не в `B.MODULES`.
- Строка ауры не длиннее `B.MAX_IMPORT` (тест в `spec/build_spec.lua`).
- API игры в `src/` читают только `snapshot`, `runtime`, `timeline`. Модули аддона `fightlog`, `advice`, `history` — без API игры (всё через `deps`); API игры — только в `review` и `fightwin`.
- Коммиты — по-русски, без номера задачи, стиль `git log` («Разбор боя: …»). Никаких `Co-Authored-By`, «Generated with», упоминаний ИИ.
- Пороги: `MIN_SECONDS = 20`, `MIN_PRESSES = 10`, `STALE = 0.5`, `LATE = 1.5`, `MAX_COPIES = 30`, `SAMPLE = 0.5`; история `SESSION_MAX = 10`, `BOSS_FIGHTS = 20`, `BOSS_MAX = 50`, тренд по 5 прошлым, «так же» — < 0.03 совпадения и < 10% потери в секунду.

## Review Focus

- `/reload` посреди боя: `PLAYER_REGEN_DISABLED` не пришёл, `PLAYER_REGEN_ENABLED` пришёл — разбора нет, ошибок нет (Task 3: `finish` без `begin`).
- Движок спит / окно ленты скрыто / движка нет (`rt` или `rt.S` = nil) весь бой — выборки молча пропускаются (Task 3: `tick` с `state() == nil`).
- Новый бой начался, пока досчитываются нажатия прошлого — прошлый разбор выходит с «не оценено», без ошибок и без смешения боёв (Task 7).
- Нет цели весь бой (или только друзья) — имя `Unknown`, трэш, в историю боссов не идёт (Task 3).
- SavedVariables старой версии без `fights` / разбор при выключенной опции `fightSummary` — история пишется, в чат ничего (Task 5, Task 7).

---

### Task 1: оценки первых кнопок в поиске и последний поиск у планировщика

**Files:**
- Modify: `src/search.lua:531-560` (сборка `byFirst` и `result`)
- Modify: `src/planner.lua` (`P:finish`)
- Test: `spec/search_spec.lua`, `spec/planner_spec.lua`

**Interfaces:**
- Produces: результат `search.best` / `job.result` получает `firstValue` — таблица `{ [firstKey] = number }`, ключи те же, что у `byFirst` (`"key"` или `"key+swing"`). Планировщик после каждого законченного поиска держит `p.last = { now = number, value = number, firstValue = table|nil, s = state }`.

- [ ] **Step 0: замер до правок** — `docker compose run --rm test busted --tags=perf` на чистом дереве; записать среднее время, инструкции и мусор на поиск (для сравнения в Step 8).

- [ ] **Step 1: тест на `firstValue`** — в конец `describe("search.best", …)` в `spec/search_spec.lua` (там уже есть `stub`, `opts`):

```lua
  -- firstValue: the score of the best chain of every first button (the fight review weighs a
  -- press by it); the plan's own first button scores the plan's value, no other more
  it("keeps the score of every first button's best chain", function()
    local plan = search.best(stub.state(), opts())
    assert.is_true(#plan.steps > 0)
    assert.are.equal(plan.value, plan.firstValue[search.firstKey(plan.steps[1])])
    local n = 0
    for f, v in pairs(plan.firstValue) do
      n = n + 1
      assert.is_true(plan.byFirst[f] ~= nil, f)
      assert.is_true(v <= plan.value, f)
    end
    assert.is_true(n >= 2)
  end)
```

- [ ] **Step 2:** `docker compose run --rm test busted spec/search_spec.lua` — FAIL (`firstValue` nil).

- [ ] **Step 3: реализация в `src/search.lua`** — рядом с `local byFirst = {}`:

```lua
  -- byFirst: the best chain found for every first button ("key" or "key+swing"), so the planner
  -- can weigh a held first button by its best continuation, not by the old plan's stale tail;
  -- firstValue: its score (after fillIdle when it was filled) - the fight review prices a press by it
  local byFirst, firstValue = {}, {}
  local function result(value, steps)
    return { value = value, steps = steps, capped = capped, timedOut = capped, nodes = nodes, byFirst = byFirst,
             firstValue = firstValue }
  end
  for f, c in pairs(bestByFirst) do byFirst[f], firstValue[f] = stepsOf(c), c.score end
```

и в цикле заполнения после `byFirst[c.first] = st`:

```lua
    firstValue[c.first] = v
```

Больше ничего не трогать: ни порядок операций, ни сравнения.

- [ ] **Step 4:** `docker compose run --rm test busted spec/search_spec.lua` — PASS.

- [ ] **Step 5: тест на `p.last`** — в `spec/planner_spec.lua`: `stubSearch` отдаёт `firstValue`, если он есть в `script`. В `s.best` заменить `return` на:

```lua
    return { value = script.best, firstValue = script.firstValue,
             steps = script.steps or { { key = script.bestKey or "fresh", at = 0, reason = "" } } }
```

и добавить тест:

```lua
  -- the last finished search, for the fight review: its time, values and the searched state
  it("keeps the last finished search", function()
    local fv = { a = 100, b = 90 }
    local p = planner.new({ search = stubSearch({ best = 100, bestKey = "a", firstValue = fv }) })
    assert.is_nil(p.last)
    p:update(at(100))
    assert.are.equal(100, p.last.now)
    assert.are.equal(100, p.last.value)
    assert.are.equal(fv, p.last.firstValue)
    assert.are.equal(100, p.last.s.now)
  end)
```

- [ ] **Step 6:** `docker compose run --rm test busted spec/planner_spec.lua` — FAIL (`p.last` nil).

- [ ] **Step 7: реализация в `src/planner.lua`**, в начале `P:finish`, после `self.job = nil`:

```lua
  -- the last finished search as found (not the held plan): the fight review prices presses by it
  self.last = { now = s.now, value = fresh.value, firstValue = fresh.firstValue, s = s }
```

- [ ] **Step 8:** весь набор без скорости `docker compose run --rm test busted --exclude-tags=perf` — PASS без правки ожиданий (бит в бит). Затем `docker compose run --rm test busted --tags=perf` — PASS; числа инструкций и мусора сравнить с Step 0 и записать обе пары в отчёт задачи.

- [ ] **Step 9: коммит**

```bash
git add src/search.lua src/planner.lua spec/search_spec.lua spec/planner_spec.lua
git commit -m "Разбор боя: оценки первых кнопок в поиске, последний поиск у планировщика"
```

---

### Task 2: зацепка `env.onPress` в движке

**Files:**
- Modify: `src/runtime.lua` (`logPress`, ~строка 199)
- Test: `spec/runtime_spec.lua` (рядом с тестами журнала нажатий, ~строка 951)

**Interfaces:**
- Consumes: `rt.planner.last` (Task 1), `rt.plan`, `rt.due`.
- Produces: хозяин, передавший `env.onPress`, получает на каждое нажатие `e = { t = number, key = string, sug = string|nil, due = number|nil, last = table|nil }`. Работает и без записи (`record`).

- [ ] **Step 1: тест** — в `describe("runtime", …)` (`start(config, extra)` уже есть; планировщик там — заглушка без `last`):

```lua
  -- the host's press hook (the addon's fight review): every press, recording on or off
  it("tells the host about every press against the shown plan", function()
    local rt, env = start()
    local got = {}
    env.onPress = function(e) got[#got + 1] = e end
    runtime.update(rt, 0.3) -- shows stormstrike @0 at 100
    rt.planner.last = { now = 100, value = 5, firstValue = { stormstrike = 5 } }
    G.cfg.now = 100.4
    runtime.onEvent(rt, "UNIT_SPELLCAST_SENT", "player", "Stormstrike", "", "Mob")
    assert.are.equal(1, #got)
    assert.are.equal(100.4, got[1].t)
    assert.are.equal("stormstrike", got[1].key)
    assert.are.equal("stormstrike", got[1].sug)
    assert.are.near(100, got[1].due, 1e-9)
    assert.are.equal(rt.planner.last, got[1].last)
    assert.is_nil(env.saved.enhrotPresses)
  end)

  it("runs without a press hook (the aura)", function()
    local rt = start()
    runtime.update(rt, 0.3)
    runtime.onEvent(rt, "UNIT_SPELLCAST_SENT", "player", "Stormstrike", "", "Mob")
  end)
```

- [ ] **Step 2:** `docker compose run --rm test busted spec/runtime_spec.lua` — FAIL (хук не вызван).

- [ ] **Step 3: реализация** — заменить `logPress`:

```lua
-- a press: to the host's hook (the addon's fight review) and, recording on, to the press log -
-- what was pressed against what was shown
local function logPress(rt, key, now)
  local d = rt.due
  local hook = rt.env and rt.env.onPress
  if hook then
    local st = rt.plan and rt.plan.steps[1]
    hook({ t = now, key = key, sug = st and st.key, due = d and d.at, last = rt.planner and rt.planner.last })
  end
  if not rt.rec then return end
  rt.rec:press(key, now, rt.plan, d and d.at)
end
```

- [ ] **Step 4:** `docker compose run --rm test busted spec/runtime_spec.lua spec/build_spec.lua` — PASS (строка ауры в лимите).

- [ ] **Step 5: коммит**

```bash
git add src/runtime.lua spec/runtime_spec.lua
git commit -m "Разбор боя: зацепка хозяина на каждое нажатие"
```

---

### Task 3: сборщик за бой — `addon/fightlog.lua`

**Files:**
- Create: `addon/fightlog.lua`
- Test: `spec/addon_fightlog_spec.lua`

**Interfaces:**
- Consumes: `e` из `env.onPress` (Task 2); `S` движка (поля: `buffs.mw.stacks`, `castRemains`, `gcdRemains`, `target.{exists,enemy,range,fs}`, `spells.<key>`, `player.shield`, `totems.fire.remains`, `weapons.{mh,oh}.enchant`, `swing.attacking`); `recorder.copy`; `search.HORIZON`.
- Produces:
  - `fightlog.new(deps) -> F`; `deps = { now(), state() -> S|nil, due() -> {key, at}|nil, boss() -> string|nil, targetName() -> string|nil, difficulty() -> string|nil }`
  - `F:begin()`, `F:active() -> bool`, `F:press(e)`, `F:tick(dt)`, `F:aura(sub, amount)`, `F:castStart(castTime)`, `F:finish() -> fight|nil`
  - `fightlog.settle(fight, evaluate) -> bool` (одно отложенное нажатие за вызов; `true` — больше нет), `fightlog.abandon(fight)`, `fightlog.bestOf(fv) -> best, bestKey`
  - `fightlog.OPTION`, `fightlog.MW_ID = 53817` и пороги из Global Constraints.
  - Разбор `fight`: `{ name, key|nil, trash|nil, boss|nil, started, seconds, presses, suggested, matched, rate|nil, stale, late, delay|nil, pairs = { ["sug>key"] = { sug, key, count, lost } }, lost, unrated, pending = { { s, key, best, pair } }, dps, mw = { wasted, idle, stacks }, gcdIdle, swings, fs = { seen, up }, prep = { shield, totems, enchants, autoAttack } }`

- [ ] **Step 1: тесты** — `spec/addon_fightlog_spec.lua`:

```lua
local fightlog = require("fightlog")

-- a collector over fake deps: a clock, the engine's state and due button, the boss and target
local function rig(over)
  local w = { t = 0, S = nil, due = nil, boss = nil, target = "Kobold", diff = "25 Player" }
  local deps = {
    now = function() return w.t end,
    state = function() return w.S end,
    due = function() return w.due end,
    boss = function() return w.boss end,
    targetName = function() return w.target end,
    difficulty = function() return w.diff end,
  }
  for k, v in pairs(over or {}) do deps[k] = v end
  w.F = fightlog.new(deps)
  return w
end

-- an engine state in melee of an enemy, every check passing (shield, totem, enchants, swinging)
local function melee(over)
  local S = { now = 0, gcdRemains = 0, castRemains = 0,
              buffs = { mw = { stacks = 0 } }, player = { shield = "lightning" },
              spells = { flameShock = {}, lightningShield = {}, searingTotem = {} },
              target = { exists = true, enemy = true, range = "melee", fs = 10 },
              totems = { fire = { remains = 30 } },
              weapons = { mh = { enchant = "wf" }, oh = { enchant = "ft" } },
              swing = { attacking = true } }
  for k, v in pairs(over or {}) do S[k] = v end
  return S
end

local function last(t, fv, s) return { now = t, value = 0, firstValue = fv, s = s or { now = t } } end

-- n presses of the suggested button, one a second from t
local function hits(w, n, t)
  for i = 1, n do
    w.t = t + i
    w.F:press({ t = w.t, key = "stormstrike", sug = "stormstrike", due = w.t, last = last(w.t, { stormstrike = 60 }) })
  end
end

describe("addon fight collector", function()
  it("exports the option and the thresholds", function()
    assert.are.same({ type = "toggle", key = "fightSummary", name = "Fight summary in chat after a fight", default = true },
      fightlog.OPTION)
    assert.are.equal(20, fightlog.MIN_SECONDS)
    assert.are.equal(10, fightlog.MIN_PRESSES)
    assert.are.equal(0.5, fightlog.STALE)
    assert.are.equal(1.5, fightlog.LATE)
    assert.are.equal(30, fightlog.MAX_COPIES)
  end)

  it("gives nothing for a fight that never began (a /reload in combat)", function()
    local w = rig()
    w.F:press({ t = 1, key = "stormstrike", sug = "stormstrike" })
    w.F:tick(1)
    assert.is_nil(w.F:finish())
  end)

  it("gives nothing below 20 s or 10 presses", function()
    local w = rig()
    w.F:begin(); hits(w, 12, 0); w.t = 19
    assert.is_nil(w.F:finish())
    w.t = 0
    w.F:begin(); hits(w, 9, 0); w.t = 30
    assert.is_nil(w.F:finish())
  end)

  it("counts matches, the mean delay and its late presses apart", function()
    local w = rig()
    w.F:begin()
    hits(w, 10, 0)
    w.t = 11.2 -- 0.2 s after due
    w.F:press({ t = 11.2, key = "stormstrike", sug = "stormstrike", due = 11, last = last(11.2, { stormstrike = 60 }) })
    w.t = 14 -- 2 s after due: late
    w.F:press({ t = 14, key = "lavaLash", sug = "stormstrike", due = 12, last = last(14, { stormstrike = 60, lavaLash = 10 }) })
    w.t = 25
    local f = w.F:finish()
    assert.are.equal(12, f.presses)
    assert.are.equal(12, f.suggested)
    assert.are.equal(11, f.matched)
    assert.are.near(11 / 12, f.rate, 1e-9)
    assert.are.equal(1, f.late)
    assert.are.near(0.2 / 11, f.delay, 1e-9)
    assert.are.equal(0, f.lost) -- the late press is not priced
    assert.are.equal(25, f.seconds)
  end)

  it("prices a wrong press by the best first button's score, the +swing chain counted too", function()
    local w = rig()
    w.F:begin()
    hits(w, 10, 0)
    w.t = 12
    w.F:press({ t = 12, key = "lavaLash", sug = "stormstrike", due = 12,
                last = last(11.8, { stormstrike = 100, lavaLash = 70, ["lavaLash+swing"] = 80 }) })
    w.t = 30
    local f = w.F:finish()
    assert.are.equal(20, f.lost)
    assert.are.same({ sug = "stormstrike", key = "lavaLash", count = 1, lost = 20 }, f.pairs["stormstrike>lavaLash"])
  end)

  it("does not price a press against a stale plan, nor one with no suggestion", function()
    local w = rig()
    w.F:begin()
    hits(w, 10, 0)
    w.t = 12
    w.F:press({ t = 12, key = "lavaLash", sug = "stormstrike", due = 12, last = last(11.4, { stormstrike = 100, lavaLash = 70 }) })
    w.F:press({ t = 12.5, key = "lavaLash" })
    w.t = 30
    local f = w.F:finish()
    assert.are.equal(1, f.stale)
    assert.are.equal(0, f.lost)
    assert.are.equal(12, f.presses)
    assert.are.equal(11, f.suggested)
  end)

  it("keeps a copy of the searched state for a button the search had no chain for, at most 30", function()
    local w = rig()
    w.F:begin()
    hits(w, 10, 0)
    local s = { now = 12, deep = { x = 1 } }
    for i = 1, 32 do
      w.F:press({ t = 12, key = "frostShock", sug = "stormstrike", due = 12,
                  last = last(12, { stormstrike = 100, ["stormstrike+swing"] = 90 }, s) })
    end
    w.t = 30
    local f = w.F:finish()
    assert.are.equal(30, #f.pending)
    assert.are.equal(2, f.unrated)
    assert.are_not.equal(s, f.pending[1].s)
    assert.are.same(s, f.pending[1].s)
    assert.are.equal("stormstrike", f.pending[1].best)
    assert.are.equal("frostShock", f.pending[1].key)
  end)

  it("settles the copied presses one a call, and abandons the rest", function()
    local w = rig()
    w.F:begin()
    hits(w, 10, 0)
    for i = 1, 3 do
      w.F:press({ t = 12, key = "frostShock", sug = "stormstrike", due = 12, last = last(12, { stormstrike = 100 }) })
    end
    w.t = 30
    local f = w.F:finish()
    local values = { stormstrike = 100, frostShock = 60 }
    local function evaluate(_, steps) return values[steps[1].key] end
    assert.is_false(fightlog.settle(f, evaluate))
    assert.are.equal(40, f.lost)
    assert.are.equal(40, f.pairs["stormstrike>frostShock"].lost)
    values.frostShock = nil -- no longer possible: not rated
    assert.is_false(fightlog.settle(f, evaluate))
    assert.are.equal(1, f.unrated)
    fightlog.abandon(f)
    assert.are.equal(2, f.unrated)
    assert.is_true(fightlog.settle(f, evaluate))
  end)

  it("samples idle 5 stacks, idle GCD, Flame Shock and the preparation every 0.5 s", function()
    local w = rig()
    w.F:begin()
    hits(w, 10, 0)
    w.S = melee({ buffs = { mw = { stacks = 5 } }, player = {}, totems = { fire = { remains = 0 } },
                  weapons = { mh = { enchant = "wf" }, oh = {} }, swing = { attacking = false },
                  target = { exists = true, enemy = true, range = "melee", fs = 0 } })
    w.due = { key = "lightningBolt", at = 10 }
    w.t = 11
    w.F:tick(0.3) -- not a sample yet
    w.F:tick(0.3) -- a sample of 0.6 s
    w.t = 30
    local f = w.F:finish()
    assert.are.near(0.6, f.mw.idle, 1e-9)
    assert.are.near(0.6, f.gcdIdle, 1e-9)
    assert.are.near(0.6, f.fs.seen, 1e-9)
    assert.are.equal(0, f.fs.up)
    assert.are.same({ shield = 0.6, totems = 0.6, enchants = 0.6, autoAttack = 0.6 }, f.prep)
  end)

  it("a plan waiting for a swing is no idle GCD; a cast is no idle 5 stacks", function()
    local w = rig()
    w.F:begin()
    hits(w, 10, 0)
    w.S = melee({ buffs = { mw = { stacks = 5 } }, castRemains = 1 })
    w.due = { key = "lightningBolt", at = 12 } -- due later: the plan waits
    w.t = 11
    w.F:tick(0.5)
    w.t = 30
    local f = w.F:finish()
    assert.are.equal(0, f.gcdIdle)
    assert.are.equal(0, f.mw.idle)
  end)

  it("skips samples while the engine has no state", function()
    local w = rig()
    w.F:begin()
    hits(w, 10, 0)
    w.F:tick(1)
    w.t = 30
    local f = w.F:finish()
    assert.are.equal(0, f.gcdIdle)
    assert.are.equal(0, f.fs.seen)
  end)

  it("counts a Maelstrom stack that came at 5 as wasted", function()
    local w = rig()
    w.F:begin()
    w.F:aura("SPELL_AURA_APPLIED")
    for n = 2, 5 do w.F:aura("SPELL_AURA_APPLIED_DOSE", n) end
    w.F:aura("SPELL_AURA_APPLIED_DOSE", 5)
    w.F:aura("SPELL_AURA_REFRESH")
    w.F:aura("SPELL_AURA_REMOVED")
    w.F:aura("SPELL_AURA_REFRESH")
    hits(w, 10, 0)
    w.t = 30
    assert.are.equal(2, w.F:finish().mw.wasted)
  end)

  it("starts from the stacks already up when the fight begins", function()
    local w = rig()
    w.S = melee({ buffs = { mw = { stacks = 5 } } })
    w.F:begin()
    w.F:aura("SPELL_AURA_REFRESH")
    hits(w, 10, 0)
    w.t = 30
    assert.are.equal(1, w.F:finish().mw.wasted)
  end)

  it("counts hard casts in melee as delayed swings", function()
    local w = rig()
    w.F:begin()
    w.S = melee()
    w.F:castStart(2.5)
    w.F:castStart(0) -- instant
    w.S = melee({ target = { exists = true, enemy = true, range = "30" } })
    w.F:castStart(2.5) -- at range: no swing to delay
    hits(w, 10, 0)
    w.t = 30
    assert.are.equal(1, w.F:finish().swings)
  end)

  it("names a boss fight with its difficulty, else the most seen target as trash", function()
    local w = rig()
    w.F:begin()
    hits(w, 10, 0)
    w.boss = "Lord Marrowgar"
    w.F:tick(0.5)
    w.t = 30
    local f = w.F:finish()
    assert.are.equal("Lord Marrowgar", f.name)
    assert.are.equal("Lord Marrowgar 25 Player", f.key)
    assert.is_nil(f.trash)

    w.boss = nil
    w.t = 0
    w.F:begin()
    hits(w, 10, 0)
    w.target = "Kobold"; w.F:tick(0.5); w.F:tick(0.5)
    w.target = "Gnoll"; w.F:tick(0.5)
    w.t = 30
    f = w.F:finish()
    assert.are.equal("Kobold", f.name)
    assert.is_true(f.trash)
    assert.is_nil(f.key)
  end)

  it("names a fight with no target at all Unknown", function()
    local w = rig()
    w.target = nil
    w.F:begin()
    hits(w, 10, 0)
    w.F:tick(0.5)
    w.t = 30
    local f = w.F:finish()
    assert.are.equal("Unknown", f.name)
    assert.is_true(f.trash)
  end)

  it("keeps the plan's damage per second: the mean best score over the horizon", function()
    local w = rig()
    w.F:begin()
    hits(w, 10, 0) -- best 60 each
    w.t = 30
    assert.are.near(60 / 6, w.F:finish().dps, 1e-9)
  end)
end)
```

- [ ] **Step 2:** `docker compose run --rm test busted spec/addon_fightlog_spec.lua` — FAIL (`module 'fightlog' not found`).

- [ ] **Step 3: реализация** — `addon/fightlog.lua`. Сначала сверить, как называются ключи заклинаний в `S.spells` (`lightningShield`, `searingTotem`, `magmaTotem`, `flameShock` — `src/spells.lua` `M.CATALOG`); если ключ другой — взять настоящий и поправить тестовую `melee()`.

```lua
-- The fight collector: counters over one fight (PLAYER_REGEN_DISABLED .. ENABLED) for the review
-- after it (addon/review.lua). The clock, the engine's state and the names come through deps:
-- nothing here reads the game API.
local recorder = require("recorder")
local search = require("search")

local M = {}
M.MIN_SECONDS = 20 -- shorter fights get no review
M.MIN_PRESSES = 10
M.STALE = 0.5 -- the last search older than this at a press: a stale plan, not a mistake
M.LATE = 1.5 -- a press later than this after its button became due: late, not wrong
M.MAX_COPIES = 30 -- searched states kept per fight for presses valued after it
M.SAMPLE = 0.5 -- seconds between samples of the engine's state
M.GRACE = 0.2 -- a due button not pressed for this long: the GCD is idle
M.MW_ID = 53817 -- Maelstrom Weapon, the buff
M.OPTION = { type = "toggle", key = "fightSummary", name = "Fight summary in chat after a fight", default = true }

local F = {}
F.__index = F

-- deps: now(), state() -> the engine's S or nil, due() -> { key, at } or nil, boss() -> name or
-- nil, targetName() -> name or nil, difficulty() -> e.g. "25 Player" or nil
function M.new(deps)
  return setmetatable({ deps = deps }, F)
end

function F:begin()
  local S = self.deps.state()
  local stacks = S and S.buffs and S.buffs.mw and S.buffs.mw.stacks or 0
  self.f = { started = self.deps.now(), presses = 0, suggested = 0, matched = 0, stale = 0, late = 0,
             delaySum = 0, delayN = 0, pairs = {}, lost = 0, unrated = 0, pending = {}, rateSum = 0, rateN = 0,
             mw = { wasted = 0, idle = 0, stacks = stacks }, gcdIdle = 0, swings = 0, fs = { seen = 0, up = 0 },
             prep = { shield = 0, totems = 0, enchants = 0, autoAttack = 0 }, names = {}, acc = 0 }
end

function F:active() return self.f ~= nil end

-- the best score of a firstValue table and its key (ties: the smaller key, deterministic)
function M.bestOf(fv)
  local best, bestKey
  for k, v in pairs(fv) do
    if best == nil or v > best or (v == best and k < bestKey) then best, bestKey = v, k end
  end
  return best, bestKey
end

local function pairOf(f, sug, key)
  local id = sug .. ">" .. key
  local p = f.pairs[id]
  if not p then
    p = { sug = sug, key = key, count = 0, lost = 0 }
    f.pairs[id] = p
  end
  return p
end

-- e = { t, key, sug, due, last } (runtime's env.onPress)
function F:press(e)
  local f = self.f
  if not f then return end
  f.presses = f.presses + 1
  if e.sug == nil then return end
  f.suggested = f.suggested + 1
  local last = e.last
  local fv = last and last.firstValue
  local best, bestKey
  if fv then best, bestKey = M.bestOf(fv) end
  if best then f.rateSum, f.rateN = f.rateSum + best / search.HORIZON, f.rateN + 1 end
  local late = false
  if e.due then
    local d = e.t - e.due
    if d > M.LATE then
      late = true
      f.late = f.late + 1
    else
      f.delaySum, f.delayN = f.delaySum + math.max(0, d), f.delayN + 1
    end
  end
  if e.key == e.sug then
    f.matched = f.matched + 1
    return
  end
  if late then return end
  if not best or e.t - last.now > M.STALE then
    f.stale = f.stale + 1
    return
  end
  local a, b = fv[e.key], fv[e.key .. "+swing"]
  local pv = (a and b) and math.max(a, b) or a or b
  local p = pairOf(f, e.sug, e.key)
  p.count = p.count + 1
  if pv then
    local loss = math.max(0, best - pv)
    p.lost, f.lost = p.lost + loss, f.lost + loss
  elseif #f.pending < M.MAX_COPIES and last.s then
    f.pending[#f.pending + 1] = { s = recorder.copy(last.s), key = e.key, best = (bestKey:gsub("%+swing$", "")), pair = p }
  else
    f.unrated = f.unrated + 1
  end
end

local function add(t, k, x) t[k] = t[k] + x end

-- a sample of the engine's state every SAMPLE seconds of dt
function F:tick(dt)
  local f = self.f
  if not f then return end
  f.acc = f.acc + (dt or 0)
  if f.acc < M.SAMPLE then return end
  local step, d = f.acc, self.deps
  f.acc = 0
  local boss = d.boss()
  if boss then
    f.boss = boss
  else
    local name = d.targetName()
    if name then f.names[name] = (f.names[name] or 0) + step end
  end
  local S = d.state()
  if not S then return end
  local busy = (S.castRemains or 0) > 0
  local mw = S.buffs and S.buffs.mw and S.buffs.mw.stacks or 0
  if mw >= 5 and not busy then add(f.mw, "idle", step) end
  local due = d.due()
  if due and d.now() >= due.at + M.GRACE and (S.gcdRemains or 0) <= 0 and not busy then
    f.gcdIdle = f.gcdIdle + step
  end
  local t, sp = S.target or {}, S.spells or {}
  if not (t.exists and t.enemy) then return end
  if sp.flameShock then
    add(f.fs, "seen", step)
    if (t.fs or 0) > 0 then add(f.fs, "up", step) end
  end
  if t.range ~= "melee" then return end
  local pr = f.prep
  if sp.lightningShield and not (S.player and S.player.shield) then add(pr, "shield", step) end
  local fire = S.totems and S.totems.fire
  if (sp.searingTotem or sp.magmaTotem) and ((fire and fire.remains) or 0) <= 0 then add(pr, "totems", step) end
  local w = S.weapons
  if w and ((w.mh and not w.mh.enchant) or (w.oh and not w.oh.enchant)) then add(pr, "enchants", step) end
  if S.swing and S.swing.attacking == false then add(pr, "autoAttack", step) end
end

-- the player's Maelstrom Weapon in the combat log: a stack that comes at 5 is wasted
function F:aura(sub, amount)
  local mw = self.f and self.f.mw
  if not mw then return end
  if sub == "SPELL_AURA_APPLIED" then
    mw.stacks = 1
  elseif sub == "SPELL_AURA_APPLIED_DOSE" then
    if mw.stacks >= 5 and (amount or 5) <= mw.stacks then mw.wasted = mw.wasted + 1 end
    mw.stacks = amount or (mw.stacks + 1)
  elseif sub == "SPELL_AURA_REFRESH" then
    if mw.stacks >= 5 then mw.wasted = mw.wasted + 1 end
  elseif sub == "SPELL_AURA_REMOVED" then
    mw.stacks = 0
  end
end

-- a hard cast started (castTime in seconds): in melee it delays the swings
function F:castStart(castTime)
  local f = self.f
  if not f or (castTime or 0) <= 0 then return end
  local S = self.deps.state()
  if S and S.target and S.target.range == "melee" then f.swings = f.swings + 1 end
end

-- the fight is over: its review data, or nil (too short, too few presses, never began)
function F:finish()
  local f, d = self.f, self.deps
  self.f = nil
  if not f then return nil end
  f.seconds = d.now() - f.started
  if f.seconds < M.MIN_SECONDS or f.presses < M.MIN_PRESSES then return nil end
  if f.boss then
    local dif = d.difficulty()
    f.name = f.boss
    f.key = (dif and dif ~= "") and (f.boss .. " " .. dif) or f.boss
  else
    local top, n
    for k, v in pairs(f.names) do
      if n == nil or v > n or (v == n and k < top) then top, n = k, v end
    end
    f.name, f.trash = top or "Unknown", true
  end
  f.dps = f.rateN > 0 and f.rateSum / f.rateN or 0
  f.delay = f.delayN > 0 and f.delaySum / f.delayN or nil
  f.rate = f.suggested > 0 and f.matched / f.suggested or nil
  f.names, f.acc = nil, nil
  return f
end

-- one copied press valued after the fight: the pressed button alone against the best first
-- button alone, on the searched state; evaluate(s, steps) -> value or nil. true: none left
function M.settle(f, evaluate)
  local item = table.remove(f.pending, 1)
  if not item then return true end
  local v1 = evaluate(item.s, { { key = item.key, at = 0 } })
  local v0 = evaluate(item.s, { { key = item.best, at = 0 } })
  if v0 and v1 then
    local loss = math.max(0, v0 - v1)
    item.pair.lost, f.lost = item.pair.lost + loss, f.lost + loss
  else
    f.unrated = f.unrated + 1
  end
  return #f.pending == 0
end

-- a new fight began before the copies were valued: the rest stays not rated
function M.abandon(f)
  f.unrated = f.unrated + #f.pending
  f.pending = {}
end

return M
```

- [ ] **Step 4:** `docker compose run --rm test busted spec/addon_fightlog_spec.lua` — PASS.

- [ ] **Step 5: коммит**

```bash
git add addon/fightlog.lua spec/addon_fightlog_spec.lua
git commit -m "Разбор боя: сборщик за бой"
```

---

### Task 4: советы — `addon/advice.lua`

**Files:**
- Create: `addon/advice.lua`
- Test: `spec/addon_advice_spec.lua`

**Interfaces:**
- Consumes: разбор `fight` из Task 3; `spells.byKey[key].name`.
- Produces:
  - `advice.tips(fight) -> { { code, weight, text, detail } }` — по убыванию веса (равные — по `code`), не больше `advice.MAX = 5`; ни одного замечания — один совет `code = "clean"`.
  - `advice.summary(fight, tips, trend) -> string` — строка в чат без префикса аддона.
  - `advice.k(n) -> string` (`1234 -> "1.2k"`, `56.4 -> "56"`), `advice.pct(rate) -> string` (`0.873 -> "87%"`, `nil -> "-"`).
  - Коды: `wrong`, `delay`, `mw_wasted`, `mw_idle`, `gcd_idle`, `swings`, `flame_shock`, `prep_shield`, `prep_totems`, `prep_enchants`, `prep_attack`, `clean`.

- [ ] **Step 1: тесты** — `spec/addon_advice_spec.lua`:

```lua
local advice = require("advice")

-- a clean fight's numbers; over replaces fields
local function fight(over)
  local f = { name = "Kobold", seconds = 60, presses = 50, suggested = 50, matched = 46, rate = 0.92, delay = 0.15,
              stale = 0, late = 0, lost = 0, unrated = 0, pairs = {}, dps = 1000,
              mw = { wasted = 0, idle = 0 }, gcdIdle = 0, swings = 0, fs = { seen = 0, up = 0 },
              prep = { shield = 0, totems = 0, enchants = 0, autoAttack = 0 } }
  for k, v in pairs(over or {}) do f[k] = v end
  return f
end

local function codes(tips)
  local out = {}
  for i, t in ipairs(tips) do out[i] = t.code end
  return table.concat(out, ",")
end

describe("addon fight advice", function()
  it("formats damage and shares", function()
    assert.are.equal("1.2k", advice.k(1234))
    assert.are.equal("56", advice.k(56.4))
    assert.are.equal("87%", advice.pct(0.873))
    assert.are.equal("-", advice.pct(nil))
  end)

  it("a clean fight says so", function()
    local tips = advice.tips(fight())
    assert.are.equal("clean", codes(tips))
    assert.are.equal("Clean fight - 92% matched, ~0.15s delay", tips[1].text)
  end)

  it("names the costly wrong pair from 15% of the loss", function()
    local pairs = { ["stormstrike>lightningBolt"] = { sug = "stormstrike", key = "lightningBolt", count = 4, lost = 4200 },
                    ["lavaLash>earthShock"] = { sug = "lavaLash", key = "earthShock", count = 1, lost = 100 } }
    local tips = advice.tips(fight({ lost = 4300, pairs = pairs }))
    assert.are.equal("wrong", tips[1].code)
    assert.are.equal(4200, tips[1].weight)
    assert.are.equal("Often pressed Lightning Bolt where Stormstrike was better (~4.2k damage)", tips[1].text)
    assert.are.equal("4 times; follow the big icon when the two differ", tips[1].detail)
    -- below 15% of the loss: no tip
    pairs["stormstrike>lightningBolt"].lost = 10
    assert.are.equal("clean", codes(advice.tips(fight({ lost = 1000, pairs = pairs }))))
  end)

  it("each rule fires at its threshold, not below", function()
    local cases = {
      { "delay", { delay = 0.31 }, { delay = 0.3 } },
      { "mw_wasted", { mw = { wasted = 2, idle = 0 } }, { mw = { wasted = 1, idle = 0 } } },
      { "mw_idle", { mw = { wasted = 0, idle = 3 } }, { mw = { wasted = 0, idle = 2.9 } } },
      { "gcd_idle", { gcdIdle = 3 }, { gcdIdle = 2.9 } }, -- 5% of 60 s
      { "swings", { swings = 3 }, { swings = 2 } },
      { "flame_shock", { fs = { seen = 30, up = 23 } }, { fs = { seen = 29, up = 0 } } },
      { "prep_shield", { prep = { shield = 5, totems = 0, enchants = 0, autoAttack = 0 } },
                       { prep = { shield = 4.9, totems = 0, enchants = 0, autoAttack = 0 } } },
      { "prep_totems", { prep = { shield = 0, totems = 5, enchants = 0, autoAttack = 0 } }, {} },
      { "prep_enchants", { prep = { shield = 0, totems = 0, enchants = 5, autoAttack = 0 } }, {} },
      { "prep_attack", { prep = { shield = 0, totems = 0, enchants = 0, autoAttack = 5 } }, {} },
    }
    for _, c in ipairs(cases) do
      assert.are.equal(c[1], codes(advice.tips(fight(c[2]))), c[1])
      assert.are.equal("clean", codes(advice.tips(fight(c[3]))), c[1] .. " below")
    end
  end)

  it("flame shock at 80% uptime is fine", function()
    assert.are.equal("clean", codes(advice.tips(fight({ fs = { seen = 100, up = 80 } }))))
  end)

  it("texts of the mechanics tips", function()
    local tips = advice.tips(fight({ delay = 0.42, mw = { wasted = 5, idle = 6.4 }, gcdIdle = 4.8, swings = 3,
                                     fs = { seen = 100, up = 62 },
                                     prep = { shield = 12, totems = 7, enchants = 9, autoAttack = 6 } }))
    assert.are.equal(5, #tips) -- 10 candidates, the 5 heaviest
    advice.MAX = 20
    local all = advice.tips(fight({ delay = 0.42, mw = { wasted = 5, idle = 6.4 }, gcdIdle = 4.8, swings = 3,
                                    fs = { seen = 100, up = 62 }, prep = { shield = 12, totems = 7, enchants = 9, autoAttack = 6 } }))
    advice.MAX = 5
    assert.are.equal(10, #all)
    local by = {}
    for _, t in ipairs(all) do by[t.code] = t.text end
    assert.are.equal("Presses come ~0.4s late - try queueing the next button earlier", by.delay)
    assert.are.equal("5 Maelstrom stacks wasted - cast at 5 right away", by.mw_wasted)
    assert.are.equal("Sat on 5 Maelstrom stacks for 6s", by.mw_idle)
    assert.are.equal("GCD idle 8% of the fight", by.gcd_idle)
    assert.are.equal("3 swings delayed by casts", by.swings)
    assert.are.equal("Flame Shock uptime 62%", by.flame_shock)
    assert.are.equal("No Lightning Shield for 12s", by.prep_shield)
    assert.are.equal("No fire totem for 7s", by.prep_totems)
    assert.are.equal("Weapon enchant missing for 9s", by.prep_enchants)
    assert.are.equal("Auto-attack off in melee for 6s", by.prep_attack)
  end)

  it("orders by weight: dps-based for the mechanics", function()
    -- gcd_idle 4 s x 1000 = 4000; mw_wasted 2 x 0.3 x 1000 = 600; swings 3 x 0.5 x 1000 = 1500
    local tips = advice.tips(fight({ gcdIdle = 4, mw = { wasted = 2, idle = 0 }, swings = 3 }))
    assert.are.equal("gcd_idle,swings,mw_wasted", codes(tips))
    assert.are.equal(4000, tips[1].weight)
  end)

  it("the chat line: name, share, loss, the first tip and the trend", function()
    local f = fight({ key = "Lich King 25 Player", name = "Lich King", rate = 0.87, lost = 3100,
                      mw = { wasted = 5, idle = 0 } })
    local tips = advice.tips(f)
    assert.are.equal("Lich King 25 Player - 87% matched, ~3.1k damage lost. Tip: 5 Maelstrom stacks wasted - cast at 5 right away. /dmr last",
      advice.summary(f, tips))
    assert.are.equal("Lich King 25 Player - 87% matched, ~3.1k damage lost, better than before. Tip: 5 Maelstrom stacks wasted - cast at 5 right away. /dmr last",
      advice.summary(f, tips, "better"))
    local clean = fight()
    assert.are.equal("Kobold - 92% matched, ~0 damage lost. Clean fight. /dmr last", advice.summary(clean, advice.tips(clean)))
  end)
end)
```

- [ ] **Step 2:** `docker compose run --rm test busted spec/addon_advice_spec.lua` — FAIL (`module 'advice' not found`).

- [ ] **Step 3: реализация** — `addon/advice.lua`:

```lua
-- Tips after a fight: pure functions over the collector's numbers (addon/fightlog.lua). Every
-- tip has a weight in damage (rough for the mechanics: through the plan's damage per second),
-- only for the order; the texts are soft ("can do better"), never "played badly".
local spells = require("spells")

local M = {}
M.MAX = 5
M.WRONG_SHARE = 0.15 -- a wrong pair is a tip from this share of the fight's loss
M.DELAY = 0.3
M.MW_WASTED = 2
M.MW_IDLE = 3
M.GCD_IDLE = 0.05 -- share of the fight
M.SWINGS = 3
M.FS_UPTIME = 0.8
M.FS_SEEN = 30
M.PREP = 5
M.TRENDS = { better = "better than before", worse = "worse than before", same = "same as before" }

function M.k(n)
  if n >= 1000 then return ("%.1fk"):format(n / 1000) end
  return tostring(math.floor(n + 0.5))
end

function M.pct(rate)
  if not rate then return "-" end
  return ("%d%%"):format(math.floor(rate * 100 + 0.5))
end

local function name(key)
  local s = spells.byKey[key]
  return s and s.name or key
end

local function topPair(f)
  local top
  for _, p in pairs(f.pairs or {}) do
    if not top or p.lost > top.lost or (p.lost == top.lost and p.sug .. p.key < top.sug .. top.key) then top = p end
  end
  return top
end

local PREP = {
  { code = "prep_shield", field = "shield", text = "No Lightning Shield for %ds" },
  { code = "prep_totems", field = "totems", text = "No fire totem for %ds" },
  { code = "prep_enchants", field = "enchants", text = "Weapon enchant missing for %ds" },
  { code = "prep_attack", field = "autoAttack", text = "Auto-attack off in melee for %ds" },
}

function M.tips(f)
  local out, dps = {}, f.dps or 0
  local function add(code, weight, text, detail)
    out[#out + 1] = { code = code, weight = weight, text = text, detail = detail }
  end
  local top = topPair(f)
  if top and f.lost > 0 and top.lost > 0 and top.lost >= M.WRONG_SHARE * f.lost then
    add("wrong", top.lost, ("Often pressed %s where %s was better (~%s damage)"):format(name(top.key), name(top.sug), M.k(top.lost)),
      ("%d times; follow the big icon when the two differ"):format(top.count))
  end
  if f.delay and f.delay > M.DELAY then
    add("delay", (f.suggested or 0) * (f.delay - M.DELAY) * dps,
      ("Presses come ~%.1fs late - try queueing the next button earlier"):format(f.delay),
      "Press as the icon reaches the line; the client queues the next spell")
  end
  local mw = f.mw or {}
  if (mw.wasted or 0) >= M.MW_WASTED then
    add("mw_wasted", mw.wasted * 0.3 * dps, ("%d Maelstrom stacks wasted - cast at 5 right away"):format(mw.wasted),
      "A stack that comes at 5 is lost; Lightning Bolt at 5 is instant")
  end
  if (mw.idle or 0) >= M.MW_IDLE then
    add("mw_idle", mw.idle * 0.2 * dps, ("Sat on 5 Maelstrom stacks for %ds"):format(math.floor(mw.idle + 0.5)),
      "At 5 stacks the next swing can waste a proc")
  end
  if f.seconds and f.seconds > 0 and (f.gcdIdle or 0) >= M.GCD_IDLE * f.seconds then
    add("gcd_idle", f.gcdIdle * dps, ("GCD idle %d%% of the fight"):format(math.floor(f.gcdIdle / f.seconds * 100 + 0.5)),
      "A button was ready and the global cooldown free, but nothing was pressed")
  end
  if (f.swings or 0) >= M.SWINGS then
    add("swings", f.swings * 0.5 * dps, ("%d swings delayed by casts"):format(f.swings),
      "Hard casts in melee push the swings back; cast at 5 Maelstrom stacks")
  end
  local fs = f.fs or {}
  if (fs.seen or 0) >= M.FS_SEEN and fs.up / fs.seen < M.FS_UPTIME then
    add("flame_shock", (fs.seen - fs.up) * 0.1 * dps, ("Flame Shock uptime %d%%"):format(math.floor(fs.up / fs.seen * 100 + 0.5)),
      "Lava Lash and the ticks need it on the target")
  end
  local prep = f.prep or {}
  for _, p in ipairs(PREP) do
    local s = prep[p.field] or 0
    if s >= M.PREP then add(p.code, s * 0.1 * dps, p.text:format(math.floor(s + 0.5)), "Before the pull or between packs") end
  end
  if #out == 0 then
    add("clean", 0, ("Clean fight - %s matched, ~%.2fs delay"):format(M.pct(f.rate), f.delay or 0), nil)
    return out
  end
  table.sort(out, function(a, b) return a.weight > b.weight or (a.weight == b.weight and a.code < b.code) end)
  while #out > M.MAX do table.remove(out) end
  return out
end

-- the line in chat after a fight (the caller adds the addon's tag); trend: history.trend or nil
function M.summary(f, tips, trend)
  local head = ("%s - %s matched, ~%s damage lost"):format(f.key or f.name, M.pct(f.rate), M.k(f.lost or 0))
  if trend and M.TRENDS[trend] then head = head .. ", " .. M.TRENDS[trend] end
  local tip = tips[1]
  local tail = (tip and tip.code ~= "clean") and ("Tip: " .. tip.text .. ".") or "Clean fight."
  return head .. ". " .. tail .. " /dmr last"
end

return M
```

- [ ] **Step 4:** `docker compose run --rm test busted spec/addon_advice_spec.lua` — PASS.
- [ ] **Step 5: коммит**

```bash
git add addon/advice.lua spec/addon_advice_spec.lua
git commit -m "Разбор боя: советы"
```

---

### Task 5: история — `addon/history.lua`

**Files:**
- Create: `addon/history.lua`
- Test: `spec/addon_history_spec.lua`

**Interfaces:**
- Consumes: разбор `fight` (Task 3), советы (Task 4).
- Produces:
  - `history.new(db, now) -> H`; `db` — `DoubtMyRotationDB` (ведёт `db.fights`), `now()` — секунды (`time` клиента).
  - `H:add(fight, tips) -> entry`; `entry = { fight, tips, short, trend }`; `H.session` — список, новые первыми, ≤ 10.
  - `H:boss(key) -> { short }` (новые первыми).
  - `history.short(fight, tips, date) -> { date, seconds, rate, delay, lostPerSec, tips = { code, … ≤ 3 } }`.
  - `history.trend(prev, short) -> "better"|"worse"|"same"|nil`.

- [ ] **Step 1: тесты** — `spec/addon_history_spec.lua`:

```lua
local history = require("history")

local function fight(over)
  local f = { name = "Marrowgar", key = "Marrowgar 25 Player", seconds = 100, rate = 0.9, delay = 0.2, lost = 1000 }
  for k, v in pairs(over or {}) do f[k] = v end
  return f
end
local TIPS = { { code = "wrong" }, { code = "delay" }, { code = "swings" }, { code = "gcd_idle" } }

local function rig()
  local w = { t = 1000, db = {} }
  w.H = history.new(w.db, function() return w.t end)
  return w
end

describe("addon fight history", function()
  it("exports the limits", function()
    assert.are.equal(10, history.SESSION_MAX)
    assert.are.equal(20, history.BOSS_FIGHTS)
    assert.are.equal(50, history.BOSS_MAX)
  end)

  it("keeps a short record: the first 3 tip codes, loss per second", function()
    assert.are.same({ date = 7, seconds = 100, rate = 0.9, delay = 0.2, lostPerSec = 10, tips = { "wrong", "delay", "swings" } },
      history.short(fight(), TIPS, 7))
  end)

  it("creates fights in old saved data and keeps the session newest first, at most 10", function()
    local w = rig()
    for i = 1, 12 do w.H:add(fight({ name = "M" .. i, key = nil, trash = true }), TIPS) end
    assert.are.equal(10, #w.H.session)
    assert.are.equal("M12", w.H.session[1].fight.name)
    assert.are.same({}, w.db.fights) -- trash: no boss history
  end)

  it("keeps 20 fights per boss, newest first", function()
    local w = rig()
    for i = 1, 22 do w.t = 1000 + i; w.H:add(fight({ seconds = i }), TIPS) end
    local list = w.H:boss("Marrowgar 25 Player")
    assert.are.equal(20, #list)
    assert.are.equal(22, list[1].seconds)
  end)

  it("drops the boss not fought for the longest past 50", function()
    local w = rig()
    for i = 1, 51 do w.t = 1000 + i; w.H:add(fight({ key = "Boss" .. i }), TIPS) end
    w.t = 2000
    w.H:add(fight({ key = "Boss1" }), TIPS) -- Boss1 fought again: Boss2 is the oldest
    w.t = 2001
    w.H:add(fight({ key = "Boss52" }), TIPS)
    assert.is_not_nil(w.db.fights.Boss1)
    assert.is_nil(w.db.fights.Boss2)
    local n = 0
    for _ in pairs(w.db.fights) do n = n + 1 end
    assert.are.equal(50, n)
  end)

  it("no trend with fewer than 2 fights before", function()
    local w = rig()
    assert.is_nil(w.H:add(fight(), TIPS).trend)
    assert.is_nil(w.H:add(fight(), TIPS).trend)
    assert.are.equal("same", w.H:add(fight(), TIPS).trend)
  end)

  it("trend against the mean of the last 5: better, worse, same", function()
    local prev = {}
    for i = 1, 7 do prev[i] = { rate = 0.8, lostPerSec = 10 } end
    prev[6], prev[7] = { rate = 0.1, lostPerSec = 100 }, { rate = 0.1, lostPerSec = 100 } -- older than 5: not counted
    assert.are.equal("better", history.trend(prev, { rate = 0.83, lostPerSec = 10 }))
    assert.are.equal("better", history.trend(prev, { rate = 0.8, lostPerSec = 9 }))
    assert.are.equal("worse", history.trend(prev, { rate = 0.77, lostPerSec = 10 }))
    assert.are.equal("worse", history.trend(prev, { rate = 0.8, lostPerSec = 11 }))
    assert.are.equal("same", history.trend(prev, { rate = 0.81, lostPerSec = 10.5 }))
    assert.are.equal("same", history.trend(prev, { rate = 0.9, lostPerSec = 20 })) -- mixed
  end)
end)
```

- [ ] **Step 2:** `docker compose run --rm test busted spec/addon_history_spec.lua` — FAIL.

- [ ] **Step 3: реализация** — `addon/history.lua`:

```lua
-- Fight reviews kept: the session's full ones in memory, a short record per boss fight in
-- SavedVariables (DoubtMyRotationDB.fights) and the trend against the last fights on that boss.
local M = {}
M.SESSION_MAX = 10
M.BOSS_FIGHTS = 20
M.BOSS_MAX = 50
M.TREND_OF = 5
M.SAME_RATE = 0.03 -- matched share, absolute
M.SAME_LOST = 0.10 -- loss per second, relative

local H = {}
H.__index = H

-- db: the addon's saved table; now(): seconds since the epoch (the client's time)
function M.new(db, now)
  if type(db.fights) ~= "table" then db.fights = {} end
  return setmetatable({ db = db, now = now, session = {} }, H)
end

function M.short(f, tips, date)
  local codes = {}
  for i = 1, math.min(3, #tips) do codes[i] = tips[i].code end
  return { date = date, seconds = math.floor((f.seconds or 0) + 0.5), rate = f.rate, delay = f.delay,
           lostPerSec = (f.seconds or 0) > 0 and (f.lost or 0) / f.seconds or 0, tips = codes }
end

-- prev: newest first; nil with fewer than 2 fights before
function M.trend(prev, cur)
  local n = math.min(#prev, M.TREND_OF)
  if n < 2 then return nil end
  local rate, rn, lost = 0, 0, 0
  for i = 1, n do
    if prev[i].rate then rate, rn = rate + prev[i].rate, rn + 1 end
    lost = lost + (prev[i].lostPerSec or 0)
  end
  lost = lost / n
  local dr = (rn > 0 and cur.rate) and (cur.rate - rate / rn) or 0
  local dl = lost > 0 and ((cur.lostPerSec or 0) - lost) / lost or 0
  local eps = 1e-9
  local up = dr >= M.SAME_RATE - eps or dl <= -M.SAME_LOST + eps
  local down = dr <= -M.SAME_RATE + eps or dl >= M.SAME_LOST - eps
  if up and not down then return "better" end
  if down and not up then return "worse" end
  return "same"
end

local function evict(fights)
  local n, oldest, oldKey = 0, nil, nil
  for k, b in pairs(fights) do
    n = n + 1
    local t = b.last or 0
    if oldest == nil or t < oldest or (t == oldest and k < oldKey) then oldest, oldKey = t, k end
  end
  if n > M.BOSS_MAX then fights[oldKey] = nil end
end

function H:add(f, tips)
  local short = M.short(f, tips, self.now())
  local entry = { fight = f, tips = tips, short = short }
  table.insert(self.session, 1, entry)
  while #self.session > M.SESSION_MAX do table.remove(self.session) end
  if f.key then
    local fights = self.db.fights
    local b = fights[f.key]
    entry.trend = M.trend(b and b.list or {}, short)
    if not b then
      b = { list = {} }
      fights[f.key] = b
    end
    b.last = short.date
    table.insert(b.list, 1, short)
    while #b.list > M.BOSS_FIGHTS do table.remove(b.list) end
    evict(fights)
  end
  return entry
end

function H:boss(key)
  local b = self.db.fights[key]
  return b and b.list or {}
end

return M
```

- [ ] **Step 4:** `docker compose run --rm test busted spec/addon_history_spec.lua` — PASS.

- [ ] **Step 5: коммит**

```bash
git add addon/history.lua spec/addon_history_spec.lua
git commit -m "Разбор боя: история по боссам и тренд"
```

---

### Task 6: окно — `addon/fightwin.lua`

**Files:**
- Create: `addon/fightwin.lua`
- Modify: `spec/support/game_mock.lua` (список сбрасываемых глобальных рамок, ~строка 299: добавить `"FightWindow"`, `"FightWindowHistory"`), при нужде — `spec/support/panel_mock.lua` (если `Button:SetText` / `FontString:GetText` в моках нет — добавить, как у соседних методов)
- Test: `spec/addon_fightwin_spec.lua`

**Interfaces:**
- Consumes: `history` (Task 5: `H.session`, `H:boss`), `advice.k`, `advice.pct`, `advice.TRENDS` (Task 4).
- Produces:
  - `fightwin.listLine(entry) -> string`, `fightwin.detail(entry) -> string`, `fightwin.historyText(key, list, date) -> string` (чистые).
  - `fightwin.new(deps) -> W`; `deps = { history = H, date = function(fmt, t) }`; `W:open(mode)` (`"last"` | `"history"`), `W:select(i)`, `W:showHistory()`, `W:refresh()`, `W:hide()`; `W.frame` (`DoubtMyRotationFightWindow`), `W.rows[i]` (кнопки списка), `W.text` (строка справа), `W.historyButton`.

- [ ] **Step 1: тесты** — `spec/addon_fightwin_spec.lua` (порядок установки моков — как в `spec/addon_panel_spec.lua`: посмотреть его `before_each` и повторить):

```lua
local G = require("game_mock")
local P = require("panel_mock")
local fightwin = require("fightwin")
local history = require("history")

local function entry(over)
  local f = { name = "Marrowgar", key = "Marrowgar 25 Player", seconds = 95, rate = 0.87, delay = 0.21, lost = 3100,
              stale = 1, late = 2, unrated = 3, mw = { wasted = 4, idle = 6.2 }, gcdIdle = 3.4, swings = 5,
              fs = { seen = 90, up = 81 }, prep = { shield = 12, totems = 0, enchants = 0, autoAttack = 2 } }
  for k, v in pairs(over or {}) do f[k] = v end
  return { fight = f, trend = "better",
           tips = { { code = "mw_wasted", text = "4 Maelstrom stacks wasted - cast at 5 right away", detail = "A stack that comes at 5 is lost" } } }
end

describe("addon fight window", function()
  before_each(function() G.install(); P.install() end)

  it("a list line: name, time, share", function()
    assert.are.equal("Marrowgar 1:35 87%", fightwin.listLine(entry()))
  end)

  it("the detail of a fight", function()
    assert.are.equal(table.concat({
      "Marrowgar 25 Player  1:35  87% matched  ~0.21s delay  ~3.1k lost  (better than before)",
      "",
      "- 4 Maelstrom stacks wasted - cast at 5 right away",
      "|cff999999  A stack that comes at 5 is lost|r",
      "",
      "Maelstrom: 4 stacks wasted, 6s on 5 stacks",
      "GCD idle 3s, swings delayed by casts 5",
      "Flame Shock uptime 90%",
      "Without: shield 12s, fire totem 0s, enchants 0s, auto-attack 2s",
      "Not rated: 3 (stale plan 1, late 2)",
    }, "\n"), fightwin.detail(entry()))
  end)

  it("no Flame Shock line when there was none to keep", function()
    assert.is_nil(fightwin.detail(entry({ fs = { seen = 0, up = 0 } })):find("Flame Shock"))
  end)

  it("the boss history: one line per fight", function()
    local list = { { date = 5, seconds = 95, rate = 0.87, lostPerSec = 32.6, tips = { "mw_wasted", "delay" } } }
    local date = function(fmt, t) return "d" .. t end
    assert.are.equal("Boss history: Marrowgar 25 Player\nd5  1:35  87%  ~33/s lost  mw_wasted, delay",
      fightwin.historyText("Marrowgar 25 Player", list, date))
  end)

  it("opens on the newest fight, selects another, shows the boss history", function()
    local H = history.new({}, function() return 7 end)
    H:add(entry({ name = "Old" }).fight, entry().tips)
    H:add(entry().fight, entry().tips)
    local W = fightwin.new({ history = H, date = function(_, t) return "d" .. t end })
    W:open("last")
    assert.is_true(W.frame:IsShown())
    assert.are.equal("Marrowgar 1:35 87%", W.rows[1].label:GetText())
    assert.is_truthy(W.text:GetText():find("^Marrowgar 25 Player"))
    W.rows[2]:Click()
    assert.are.equal(2, W.selected)
    W.historyButton:Click()
    assert.is_truthy(W.text:GetText():find("^Boss history: Marrowgar 25 Player"))
    W:hide()
    assert.is_false(W.frame:IsShown())
  end)

  it("opens with no fights yet and says so", function()
    local W = fightwin.new({ history = history.new({}, function() return 7 end), date = function() return "" end })
    W:open("last")
    assert.are.equal("No fight reviewed yet - fight something for 20s or more", W.text:GetText())
  end)
end)
```

- [ ] **Step 2:** `docker compose run --rm test busted spec/addon_fightwin_spec.lua` — FAIL.

- [ ] **Step 3: реализация** — `addon/fightwin.lua`:

```lua
-- The fight review window (/dmr last, /dmr history): the session's fights on the left, the
-- chosen one on the right, the boss history on a button. Its texts are pure functions.
local advice = require("advice")

local M = {}
M.ROWS = 10
M.WIDTH, M.HEIGHT = 640, 340
M.EMPTY = "No fight reviewed yet - fight something for 20s or more"

local function clock(s)
  s = math.floor((s or 0) + 0.5)
  return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

function M.listLine(entry)
  local f = entry.fight
  return ("%s %s %s"):format(f.name, clock(f.seconds), advice.pct(f.rate))
end

function M.detail(entry)
  local f, out = entry.fight, {}
  local function add(s) out[#out + 1] = s end
  local head = ("%s  %s  %s matched  ~%.2fs delay  ~%s lost"):format(f.key or f.name, clock(f.seconds), advice.pct(f.rate),
    f.delay or 0, advice.k(f.lost or 0))
  if entry.trend and advice.TRENDS[entry.trend] then head = head .. "  (" .. advice.TRENDS[entry.trend] .. ")" end
  add(head)
  add("")
  for _, t in ipairs(entry.tips or {}) do
    add("- " .. t.text)
    if t.detail then add("|cff999999  " .. t.detail .. "|r") end
  end
  add("")
  local mw, pr, fs = f.mw or {}, f.prep or {}, f.fs or {}
  local function s(x) return math.floor((x or 0) + 0.5) end
  add(("Maelstrom: %d stacks wasted, %ds on 5 stacks"):format(mw.wasted or 0, s(mw.idle)))
  add(("GCD idle %ds, swings delayed by casts %d"):format(s(f.gcdIdle), f.swings or 0))
  if (fs.seen or 0) > 0 then add(("Flame Shock uptime %s"):format(advice.pct(fs.up / fs.seen))) end
  add(("Without: shield %ds, fire totem %ds, enchants %ds, auto-attack %ds"):format(s(pr.shield), s(pr.totems), s(pr.enchants), s(pr.autoAttack)))
  add(("Not rated: %d (stale plan %d, late %d)"):format(f.unrated or 0, f.stale or 0, f.late or 0))
  return table.concat(out, "\n")
end

-- list: history's short records, newest first; date(fmt, t) formats a time (the client's date)
function M.historyText(key, list, date)
  local out = { "Boss history: " .. key }
  for _, r in ipairs(list) do
    out[#out + 1] = ("%s  %s  %s  ~%d/s lost  %s"):format(date("%m-%d %H:%M", r.date), clock(r.seconds), advice.pct(r.rate),
      math.floor((r.lostPerSec or 0) + 0.5), table.concat(r.tips or {}, ", "))
  end
  return table.concat(out, "\n")
end

local W = {}
W.__index = W

function M.new(deps)
  local self = setmetatable({ deps = deps, rows = {}, selected = 1 }, W)
  local f = CreateFrame("Frame", "DoubtMyRotationFightWindow", UIParent)
  f:SetWidth(M.WIDTH)
  f:SetHeight(M.HEIGHT)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetFrameStrata("DIALOG")
  f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                  tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
  f:SetBackdropColor(0, 0, 0, 0.9)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(fr) if not InCombatLockdown() then fr:StartMoving() end end)
  f:SetScript("OnDragStop", function(fr) fr:StopMovingOrSizing() end)
  f:Hide()
  self.frame = f
  for i = 1, M.ROWS do
    local b = CreateFrame("Button", nil, f)
    b:SetWidth(180)
    b:SetHeight(18)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -12 - (i - 1) * 20)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("LEFT", b, "LEFT", 0, 0)
    b:SetScript("OnClick", function() self:select(i) end)
    self.rows[i] = b
  end
  self.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  self.text:SetPoint("TOPLEFT", f, "TOPLEFT", 204, -12)
  self.text:SetWidth(M.WIDTH - 216)
  self.text:SetJustifyH("LEFT")
  local hb = CreateFrame("Button", "DoubtMyRotationFightWindowHistory", f, "UIPanelButtonTemplate")
  hb:SetWidth(110)
  hb:SetHeight(22)
  hb:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
  hb:SetText("Boss history")
  hb:SetScript("OnClick", function() self:showHistory() end)
  self.historyButton = hb
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
  return self
end

function W:refresh()
  local list = self.deps.history.session
  for i, b in ipairs(self.rows) do
    local e = list[i]
    if e then
      b.label:SetText(M.listLine(e))
      b:Show()
    else
      b:Hide()
    end
  end
  local e = list[self.selected]
  if self.mode == "history" and e and e.fight.key then
    self.text:SetText(M.historyText(e.fight.key, self.deps.history:boss(e.fight.key), self.deps.date))
  elseif e then
    self.text:SetText(M.detail(e))
  else
    self.text:SetText(M.EMPTY)
  end
end

function W:select(i)
  self.selected, self.mode = i, "last"
  self:refresh()
end

function W:showHistory()
  self.mode = "history"
  self:refresh()
end

function W:open(mode)
  self.selected, self.mode = 1, mode or "last"
  self:refresh()
  self.frame:Show()
end

function W:hide() self.frame:Hide() end

return M
```

Если мок рамки не знает `SetBackdrop`, `SetBackdropColor`, `SetFrameStrata`, `SetJustifyH`, `InCombatLockdown` — добавить заглушки в `spec/support/game_mock.lua` рядом с похожими (по одной строке, ничего не делают).

- [ ] **Step 4:** `docker compose run --rm test busted spec/addon_fightwin_spec.lua` — PASS. Убедиться, что `spec/addon_panel_spec.lua` и `spec/addon_core_spec.lua` не сломались от правок моков: `docker compose run --rm test busted spec/addon_panel_spec.lua spec/addon_core_spec.lua`.

- [ ] **Step 5: коммит**

```bash
git add addon/fightwin.lua spec/addon_fightwin_spec.lua spec/support/game_mock.lua spec/support/panel_mock.lua
git commit -m "Разбор боя: окно /dmr last"
```

---

### Task 7: связка с игрой, `/dmr last`, опция, сборка

**Files:**
- Create: `addon/review.lua`
- Modify: `addon/core.lua` (`withUpdate`, `M.login`, `M.handle`), `addon/settings.lua` (`M.ACTIONS`, `M.HELP`), `addon/panel.lua` (`M.SECTIONS`, Combat: `"fightSummary"`), `tools/build.lua` (`B.ADDON_MODULES`), `spec/support/game_mock.lua` (сброс `"Fights"`; заглушки `GetInstanceInfo`, `UnitExists`, `UnitName`, `time`, `date`, если их нет)
- Test: `spec/addon_review_spec.lua`, `spec/addon_core_spec.lua`, `spec/addon_settings_spec.lua`, `spec/build_spec.lua` (если там сверяется список модулей аддона)

**Interfaces:**
- Consumes: всё из Tasks 2–6.
- Produces: `review.new(deps) -> R`; `deps = { rt() -> engine rt|nil, db, say(line), config() -> table, now(), time(), date(fmt, t) }`; `R:start(frame)`, `R:onEvent(event, ...)`, `R:onUpdate(dt)`, `R:press(e)`, `R:open(mode)`; `review.boss()`, `review.difficulty()`, `review.EVENTS`. `/dmr last`, `/dmr history`.

- [ ] **Step 1: тесты связки** — `spec/addon_review_spec.lua`. Связку гоняем без настоящих событий клиента: `onEvent` / `onUpdate` вызываются напрямую, `rt()` отдаёт подставной движок.

```lua
local G = require("game_mock")
local P = require("panel_mock")
local review = require("review")
local fightlog = require("fightlog")

local function rig(config)
  G.install(); P.install()
  local w = { t = 100, said = {}, db = {}, config = config or {}, rt = { S = nil, due = nil } }
  w.R = review.new({
    rt = function() return w.rt end, db = w.db, say = function(l) w.said[#w.said + 1] = l end,
    config = function() return w.config end, now = function() return w.t end,
    time = function() return 5 end, date = function() return "d" end,
  })
  return w
end

-- a fight of n matched presses, one a second, ending at 100 + seconds
local function fight(w, n, seconds)
  w.R:onEvent("PLAYER_REGEN_DISABLED")
  for i = 1, n do
    w.t = 100 + i
    w.R:press({ t = w.t, key = "stormstrike", sug = "stormstrike", due = w.t,
                last = { now = w.t, value = 60, firstValue = { stormstrike = 60 } } })
  end
  w.t = 100 + seconds
  w.R:onEvent("PLAYER_REGEN_ENABLED")
end

describe("addon fight review", function()
  it("after a fight: one line in chat and the fight in the session", function()
    local w = rig()
    fight(w, 12, 30)
    w.R:onUpdate(0.016) -- nothing to settle: reported on the next frame
    assert.are.equal(1, #w.said)
    assert.is_truthy(w.said[1]:find("100%% matched"))
    assert.are.equal(1, #w.R.history.session)
  end)

  it("no line with the summary turned off; the fight is kept", function()
    local w = rig({ fightSummary = false })
    fight(w, 12, 30)
    w.R:onUpdate(0.016)
    assert.are.equal(0, #w.said)
    assert.are.equal(1, #w.R.history.session)
  end)

  it("a short fight gives nothing", function()
    local w = rig()
    fight(w, 12, 10)
    w.R:onUpdate(0.016)
    assert.are.equal(0, #w.said)
  end)

  it("a new fight before the copies are valued: the old one is reported, the rest not rated", function()
    local w = rig()
    w.R:onEvent("PLAYER_REGEN_DISABLED")
    for i = 1, 12 do
      w.t = 100 + i
      w.R:press({ t = w.t, key = "frostShock", sug = "stormstrike", due = w.t,
                  last = { now = w.t, value = 60, firstValue = { stormstrike = 60 }, s = { now = w.t } } })
    end
    w.t = 130
    w.R:onEvent("PLAYER_REGEN_ENABLED")
    w.R:onEvent("PLAYER_REGEN_DISABLED") -- before any frame
    assert.are.equal(1, #w.R.history.session)
    assert.are.equal(12, w.R.history.session[1].fight.unrated)
    assert.is_true(w.R.log:active())
  end)

  it("Maelstrom in the combat log: only the player's own buff", function()
    local w = rig()
    local me = UnitGUID("player")
    w.R:onEvent("PLAYER_REGEN_DISABLED")
    w.R.log.f.mw.stacks = 5
    w.R:onEvent("COMBAT_LOG_EVENT_UNFILTERED", 0, "SPELL_AURA_REFRESH", me, "Me", 0, me, "Me", 0, fightlog.MW_ID, "Maelstrom Weapon", 8, "BUFF")
    w.R:onEvent("COMBAT_LOG_EVENT_UNFILTERED", 0, "SPELL_AURA_REFRESH", "x", "X", 0, "other", "Other", 0, fightlog.MW_ID, "Maelstrom Weapon", 8, "BUFF")
    assert.are.equal(1, w.R.log.f.mw.wasted)
  end)

  it("the window hides when a fight begins", function()
    local w = rig()
    w.R:open("last")
    assert.is_true(w.R.window.frame:IsShown())
    w.R:onEvent("PLAYER_REGEN_DISABLED")
    assert.is_false(w.R.window.frame:IsShown())
  end)

  it("difficulty: none outside instances, the client's name inside", function()
    G.install()
    _G.GetInstanceInfo = function() return "Azeroth", "none", 1, "", 5 end
    assert.are.equal("", review.difficulty())
    _G.GetInstanceInfo = function() return "Icecrown Citadel", "raid", 2, "25 Player", 25 end
    assert.are.equal("25 Player", review.difficulty())
  end)
end)
```

Если в `game_mock` GUID игрока задаётся иначе — взять его способ (поиск `UnitGUID` в `spec/support/game_mock.lua`) и поправить тест.

- [ ] **Step 2: интеграционный тест** — в том же файле, отдельный `describe` с тегом:

```lua
describe("addon fight review on recorded states #integration", function()
  local path = "spec/fixtures/recorded.lua"
  local f = io.open(path, "rb")
  if not f then return pending("no " .. path) end
  f:close()
  local search = require("search")
  local Sc = require("scenario")
  local advice = require("advice")

  it("a fight of real searches, wrong presses valued after it, gives tips", function()
    local list = dofile(path)
    local t = 0
    local F = fightlog.new({ now = function() return t end, state = function() return nil end, due = function() return nil end,
                             boss = function() return nil end, targetName = function() return "Mob" end,
                             difficulty = function() return nil end })
    F:begin()
    local n = 0
    for _, rec in ipairs(list) do
      local res = search.best(rec.S, Sc.OPTS)
      local first = res.steps[1] and res.steps[1].key
      if first then
        local other
        for k in pairs(rec.S.spells) do if k ~= first then other = k break end end
        t = t + 1
        F:press({ t = t, key = other or first, sug = first, due = t,
                  last = { now = t, value = res.value, firstValue = res.firstValue, s = rec.S } })
        n = n + 1
      end
    end
    assert.is_true(n >= fightlog.MIN_PRESSES)
    t = math.max(t, fightlog.MIN_SECONDS) + 1
    local fight = F:finish()
    local evaluate = function(s, steps) return (search.evaluate(s, steps, Sc.OPTS)) end
    while not fightlog.settle(fight, evaluate) do end
    assert.is_true(fight.lost >= 0)
    local tips = advice.tips(fight)
    assert.is_true(#tips >= 1)
    assert.is_truthy(advice.summary(fight, tips):find("/dmr last$"))
  end)
end)
```

- [ ] **Step 3:** `docker compose run --rm test busted spec/addon_review_spec.lua` — FAIL (`module 'review' not found`).

- [ ] **Step 4: реализация** — `addon/review.lua`:

```lua
-- The fight review in the game: the collector (fightlog) on the client's events and the
-- engine's press hook, the copied presses valued out of combat one a frame, then the tips,
-- the history, a line in chat and the window.
local fightlog = require("fightlog")
local advice = require("advice")
local history = require("history")
local fightwin = require("fightwin")
local search = require("search")

local M = {}
M.EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "COMBAT_LOG_EVENT_UNFILTERED", "UNIT_SPELLCAST_START" }

function M.boss()
  if UnitExists("boss1") then return UnitName("boss1") end
  if UnitExists("target") and UnitClassification("target") == "worldboss" then return UnitName("target") end
  return nil
end

-- "25 Player", "10 Player (Heroic)", ... ; "" outside instances
function M.difficulty()
  local _, kind, _, name = GetInstanceInfo()
  if kind == nil or kind == "none" then return "" end
  return name or ""
end

local function evaluate(s, steps) return (search.evaluate(s, steps)) end

local R = {}
R.__index = R

-- deps: rt() -> the engine's rt or nil, db, say(line), config(), now(), time(), date(fmt, t)
function M.new(deps)
  local self = setmetatable({ deps = deps }, R)
  self.log = fightlog.new({
    now = deps.now,
    state = function() local rt = deps.rt(); return rt and rt.S end,
    due = function() local rt = deps.rt(); return rt and rt.due end,
    boss = M.boss,
    targetName = function() if UnitExists("target") and UnitCanAttack("player", "target") then return UnitName("target") end end,
    difficulty = M.difficulty,
  })
  self.history = history.new(deps.db, deps.time)
  return self
end

function R:report(f)
  local tips = advice.tips(f)
  local entry = self.history:add(f, tips)
  if self.deps.config().fightSummary ~= false then self.deps.say(advice.summary(f, tips, entry.trend)) end
  if self.window and self.window.frame:IsShown() then self.window:refresh() end
end

function R:onEvent(event, ...)
  if event == "PLAYER_REGEN_DISABLED" then
    if self.settling then
      fightlog.abandon(self.settling)
      self:report(self.settling)
      self.settling = nil
    end
    if self.window then self.window:hide() end
    self.log:begin()
  elseif event == "PLAYER_REGEN_ENABLED" then
    -- a second ENABLED without DISABLED (a /reload) must not drop a fight still being valued
    local f = self.log:finish()
    if f then self.settling = f end
  elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
    local _, sub, _, _, _, dst, _, _, spellId, _, _, _, amount = ...
    if spellId == fightlog.MW_ID and dst == UnitGUID("player") then self.log:aura(sub, amount) end
  elseif event == "UNIT_SPELLCAST_START" then
    if (...) ~= "player" then return end
    local _, _, _, _, startMs, endMs = UnitCastingInfo("player")
    self.log:castStart((startMs and endMs) and (endMs - startMs) / 1000 or 0)
  end
end

function R:onUpdate(dt)
  if self.log:active() then
    self.log:tick(dt)
  elseif self.settling and fightlog.settle(self.settling, evaluate) then
    local f = self.settling
    self.settling = nil
    self:report(f)
  end
end

function R:press(e) self.log:press(e) end

function R:open(mode)
  self.window = self.window or fightwin.new({ history = self.history, date = self.deps.date })
  self.window:open(mode)
end

function R:start(frame)
  for _, e in ipairs(M.EVENTS) do frame:RegisterEvent(e) end
  frame:SetScript("OnEvent", function(_, event, ...) self:onEvent(event, ...) end)
  frame:SetScript("OnUpdate", function(_, dt) self:onUpdate(dt) end)
  return frame
end

return M
```

- [ ] **Step 5: подключение**:
  - `tools/build.lua` `B.ADDON_MODULES`: перед `{ "core", "addon/core.lua" }` вставить `{ "fightlog", "addon/fightlog.lua" }, { "advice", "addon/advice.lua" }, { "history", "addon/history.lua" }, { "fightwin", "addon/fightwin.lua" }, { "review", "addon/review.lua" }`.
  - `addon/settings.lua`: `M.ACTIONS` + `last = true, history = true`; в `M.HELP` строка `"/dmr last - review of the last fights; /dmr history - per boss"`.
  - `addon/panel.lua` `M.SECTIONS`, Combat: `options = { "mode", "cdFeralSpirit", "cdFireElemental", "cdShamanisticRage", "shield", "fightSummary" }`.
  - `addon/core.lua`:
    - `local review = require("review")`, `local fightlog = require("fightlog")`;
    - `withUpdate` → `withExtras`: дописывает `update.OPTION` и `fightlog.OPTION`, каждый — только если такого ключа ещё нет (`boot` может прийти дважды);
    - в `M.login` env с зацепкой и запуск связки:

```lua
  M.env = { region = M.frame, saved = M.db.saved, libs = o.libs,
            onPress = function(e) if M.review then M.review:press(e) end end }
  start()
  M.review = M.review or review.new({
    rt = function() return M.rt end, db = M.db, say = say, config = function() return M.db.config end,
    now = GetTime, time = time, date = date,
  })
  M.review:start(DoubtMyRotationFights or CreateFrame("Frame", "DoubtMyRotationFights"))
```

    - в `M.handle`: `elseif a == "last" or a == "history" then M.review:open(a)`.
  - `spec/support/game_mock.lua`: в список сбрасываемых имён (~строка 299) добавить `"Fights"`; заглушки `GetInstanceInfo` (`"Azeroth", "none", 1, "", 5`), `UnitExists`, `UnitName`, `UnitCanAttack`, `time`, `date`, если их нет.

- [ ] **Step 6: тесты core/settings** — в `spec/addon_core_spec.lua` по образцу соседних тестов `/dmr`:

```lua
  it("/dmr last opens the fight review window, /dmr history its boss history", function()
    -- запуск аддона как в соседних тестах (boot + ADDON_LOADED + PLAYER_LOGIN шамана)
    SlashCmdList.DOUBTMYROTATION("last")
    assert.is_true(DoubtMyRotationFightWindow:IsShown())
    SlashCmdList.DOUBTMYROTATION("history")
    assert.is_true(DoubtMyRotationFightWindow:IsShown())
  end)

  it("hands the engine a press hook and adds the fight summary option once", function()
    -- после запуска: M.env.onPress — функция; в списке опций ровно один fightSummary и один updateCheck
  end)
```

Второй тест дописать по конкретике файла (как он достаёт `o.options` и `M.env`) — с настоящими проверками, без пустых тел. В `spec/addon_settings_spec.lua` — проверить, что `/dmr last` и `/dmr history` дают `r.action == "last"` / `"history"`; если `build_spec` сверяет `B.ADDON_MODULES` — обновить ожидание.

- [ ] **Step 7:** `docker compose run --rm test busted spec/addon_review_spec.lua spec/addon_core_spec.lua spec/addon_settings_spec.lua spec/addon_panel_spec.lua spec/build_spec.lua` — PASS. Затем сборка: `docker compose run --rm test lua tools/build.lua` — без ошибок; в `dist/DoubtMyRotation/DoubtMyRotation.lua` есть `fightlog`, `review`; строка ауры не выросла сверх лимита.

- [ ] **Step 8: коммит**

```bash
git add addon/review.lua addon/core.lua addon/settings.lua addon/panel.lua tools/build.lua spec/addon_review_spec.lua spec/addon_core_spec.lua spec/addon_settings_spec.lua spec/build_spec.lua spec/support/game_mock.lua
git commit -m "Разбор боя: связка с событиями игры, /dmr last и /dmr history, опция строки в чат"
```

---

### Task 8: документация и полный прогон

**Files:**
- Modify: `README.md` (раздел про аддон: `/dmr last`, `/dmr history`, опция Fight summary — по-русски, как остальной README), `.claude/rules/ARCHITECTURE.md` (таблица «Аддон»: `fightlog`, `advice`, `history`, `fightwin`, `review`), `docs/superpowers/specs/2026-10-01-addon-roadmap.md` (пункт «Разбор после боя» этапа 1 — пометка «сделано, спека `2026-10-01-fight-review-design.md`»)

- [ ] **Step 1:** правки документации (строки таблицы ARCHITECTURE — в стиле существующих: `| \`fightlog\` | сборщик за бой: нажатия, механики, подготовка | — |` и т.д.).
- [ ] **Step 2:** весь набор `docker compose run --rm test busted` — PASS; `docker compose run --rm test busted --tags=perf` — PASS, числа инструкций и мусора — в отчёт.
- [ ] **Step 3: коммит**

```bash
git add README.md .claude/rules/ARCHITECTURE.md docs/superpowers/specs/2026-10-01-addon-roadmap.md
git commit -m "Разбор боя: README и карта проекта"
```
