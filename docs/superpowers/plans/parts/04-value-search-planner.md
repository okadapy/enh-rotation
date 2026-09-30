# Часть 4. Оценка, поиск, планировщик (задачи 9–11)

## Contract additions

Дополнения к общему контракту. Задачи других частей, которые их затрагивают, обязаны им следовать.

1. **Внедрение зависимостей в поиск.** `search.best(S, opts)` и `search.evaluate(S, steps, opts)` принимают:
   - `opts.model` — по умолчанию `require("model")`;
   - `opts.value` — по умолчанию `require("value")`.

   Интерфейсы те же, что в контракте. Это нужно, чтобы тестировать поиск на игрушечной модели с известными числами.
2. **`search.evaluate(S, steps, opts) -> value, retimedSteps | nil`.** Переигрывает готовый список шагов на новом `S`. Возвращает `nil`, если какой-то шаг стал невозможен (`model.readyIn` вернул `nil`) или ни один шаг не уложился в горизонт.
3. **`search.signature(S) -> string`** и **`search.reason(S, key, afterSwing) -> string`** — публичные функции, их используют тесты.
4. **`model.actions(S)`** возвращает кандидатов в порядке `spells.CATALOG` (детерминированно, не через `pairs`). Требования к записям:
   - запись `waitSwing` идёт последней, её `readyIn` равен времени до ближайшего удара любой рукой + 0.01;
   - если автоатака выключена или удар за горизонтом, записи `waitSwing` нет;
   - кандидаты с `readyIn >= HORIZON` не возвращаются.
5. **`model.readyIn(S, key)` ≥ `max(S.gcdRemains, S.castRemains)`.** Именно так соблюдается правило спеки §7 «считать на момент, когда игрок сможет действовать». Планировщик сам время не сдвигает.
6. **`model.apply(S, key)` сдвигает время на `dt`.** Итог `S2.now = S.now + dt`; в `dmg` входит всё, что случилось за `dt`: сам удар, автоатаки, тики.
7. **`model.apply` и `model.wait` уменьшают `S2.target.hp` на нанесённый урон**, не ниже 0.
8. **`damage.dot(S, key)`** поддерживает `flameShock`, `magmaTotem` и `searingTotem`: для тотемов это пульс, `period` — период атаки тотема. Для остальных ключей возвращает `0, 0, 1`.
9. **`util.copy(t)`** — глубокая копия. Модуль `src/util.lua` создаёт задача-заготовка из части 1, он такой же, как в `frost-rotation`.
10. **`fixtures.state(overrides)`** (часть 1) по умолчанию:
    - уровень 80, выучены все 15 ключей действий с `cd = 0`;
    - `mode = "group"`, `swing.attacking = true`;
    - `target.hp = hpMax = 1e6`, `ttd = 60`;
    - `overrides` сливаются глубоко.
11. **Поле плана `held = true`** означает, что планировщик оставил прежний план. Лента может использовать его для плавной анимации.

---

### Task 9: Оценка цепочки (`src/value.lua`)

**Files:**
- Create: `src/value.lua`
- Test: `spec/value_spec.lua`

**Interfaces:**
- Consumes:
  - `damage.action(S, key) -> dmg`, `damage.dot(S, key) -> perTick, ticks, period`, `damage.targets(S, key) -> n` (часть 3);
  - `fixtures.state(overrides)` и `util.copy(t)` (часть 1).
- Produces:
  - `value.WEIGHTS[mode] -> { mana =, overkill =, kill = }`;
  - `value.manaPrice(S) -> урон за 1 ед. маны`;
  - `value.step(S, S2, dmg, manaSpent) -> v`;
  - `value.terminal(S) -> v`;
  - константы `value.DISCOUNT = 0.5`, `value.MW_SHARE = 0.2`.

Почему DoT и тотемы после горизонта берутся с дисконтом 0.5. Без него цепочка «Earth Shock сейчас, Flame Shock через 5 с» получает за хвост дебаффа после горизонта столько же, сколько цепочка «Flame Shock сейчас». Хвост за горизонтом всё равно перекрылся бы следующим наложением, поэтому полная цена его завышает. С дисконтом поиск перестаёт откладывать спавший Flame Shock, но и не обновляет его раньше времени: обновление срезает старые тики, а новые за горизонтом стоят вдвое меньше.

- [ ] **Step 1: Write the failing test**

`spec/value_spec.lua`:

```lua
local value = require("value")
local damage = require("damage")
local fixtures = require("fixtures")
local util = require("util")

local function after(S, hp)
  local S2 = util.copy(S)
  S2.target.hp = hp
  return S2
end

describe("value.step", function()
  it("solo: damage above the target's remaining health is worth nothing, killing gives a bonus", function()
    local S = fixtures.state({ mode = "solo", target = { hp = 500, hpMax = 10000 } })
    local v = value.step(S, after(S, 0), 2000, 0)
    assert.are.near(500 + value.WEIGHTS.solo.kill * 10000, v, 1e-6)
  end)

  it("group: overkill counts at 0.2 and there is no kill bonus", function()
    local S = fixtures.state({ mode = "group", target = { hp = 500, hpMax = 10000 } })
    local v = value.step(S, after(S, 0), 2000, 0)
    assert.are.near(500 + 1500 * 0.2, v, 1e-6)
  end)

  it("subtracts spent mana at the mode's price and rewards mana gained", function()
    local S = fixtures.state({ mode = "solo" })
    local price = value.manaPrice(S)
    assert.are.near(1000 - 300 * price, value.step(S, after(S, S.target.hp - 1000), 1000, 300), 1e-6)
    assert.are.near(1000 + 300 * price, value.step(S, after(S, S.target.hp - 1000), 1000, -300), 1e-6)
  end)

  it("pvp uses group weights", function()
    assert.are.same(value.WEIGHTS.group, value.WEIGHTS.pvp)
  end)
end)

describe("value.manaPrice", function()
  it("solo: mana gets more expensive as it runs low", function()
    local full = fixtures.state({ mode = "solo", player = { mana = 10000, manaMax = 10000 } })
    local low = fixtures.state({ mode = "solo", player = { mana = 2000, manaMax = 10000 } })
    assert.is_true(value.manaPrice(low) > value.manaPrice(full) * 2)
  end)

  it("solo: mana is dearer while Shamanistic Rage is on cooldown", function()
    local ready = fixtures.state({ mode = "solo", spells = { shamanisticRage = { cd = 0 } } })
    local onCd = fixtures.state({ mode = "solo", spells = { shamanisticRage = { cd = 30 } } })
    assert.are.near(value.manaPrice(ready) * 1.5, value.manaPrice(onCd), 1e-9)
  end)

  it("group: nearly free unless the fight outlasts the mana", function()
    local fine = fixtures.state({ mode = "group", player = { mana = 9000, manaMax = 10000 }, target = { ttd = 60 } })
    local oom = fixtures.state({ mode = "group", player = { mana = 1000, manaMax = 10000 }, target = { ttd = 60 } })
    local solo = fixtures.state({ mode = "solo", player = { mana = 9000, manaMax = 10000 } })
    assert.is_true(value.manaPrice(fine) < value.manaPrice(solo) * 0.1)
    assert.is_true(value.manaPrice(oom) > value.manaPrice(fine) * 5)
  end)
end)

describe("value.terminal", function()
  local function base(over)
    local o = { totems = { fire = { kind = false, remains = 0 } }, target = { fs = 0 }, buffs = { mw = { stacks = 0, remains = 0 } } }
    for k, v in pairs(over or {}) do o[k] = v end
    return fixtures.state(o)
  end

  it("more Maelstrom stacks are worth more", function()
    local s0 = base()
    local s4 = base({ buffs = { mw = { stacks = 4, remains = 20 } } })
    local lb = damage.action(s4, "lightningBolt")
    assert.are.near(4 * value.MW_SHARE * lb, value.terminal(s4) - value.terminal(s0), 1e-6)
  end)

  it("counts remaining Flame Shock ticks at the discount, limited by time to die", function()
    local long = base({ target = { fs = 9, ttd = 60 } })
    local short = base({ target = { fs = 9, ttd = 3 } })
    local perTick = damage.dot(long, "flameShock")
    -- 3 ticks vs 1 tick, both at DISCOUNT 0.5
    assert.are.near(2 * perTick * value.DISCOUNT, value.terminal(long) - value.terminal(short), 1e-6)
  end)

  it("a ready Stormstrike is worth half of pressing it", function()
    local ready = base({ spells = { stormstrike = { cd = 0 } } })
    local onCd = base({ spells = { stormstrike = { cd = 5 } } })
    local ss = damage.action(ready, "stormstrike")
    assert.are.near(ss * value.DISCOUNT, value.terminal(ready) - value.terminal(onCd), 1e-6)
  end)

  it("an active Magma Totem adds its remaining pulses", function()
    local none = base()
    local magma = base({ totems = { fire = { kind = "magma", remains = 10 } } })
    assert.is_true(value.terminal(magma) > value.terminal(none))
  end)
end)
```

Замечание: `kind = false` в `base` означает «тотема нет». Глубокое слияние в `fixtures.state` не умеет ставить `nil`, поэтому `value` проверяет тотем через `if not fire.kind`.

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose run --rm test busted spec/value_spec.lua`
Expected: FAIL with `module 'value' not found`

- [ ] **Step 3: Write minimal implementation**

`src/value.lua`:

```lua
local damage = require("damage")

local M = {}

M.WEIGHTS = {
  solo  = { mana = 1.0,  overkill = 0.0, kill = 0.15 },
  group = { mana = 0.05, overkill = 0.2, kill = 0.0 },
  raid  = { mana = 0.05, overkill = 0.2, kill = 0.0 },
}
M.WEIGHTS.pvp = M.WEIGHTS.group

M.DISCOUNT = 0.5             -- ready cooldowns, DoT ticks and totem pulses after the horizon
M.MW_SHARE = 0.2             -- one Maelstrom stack = 1/5 of an instant Lightning Bolt
M.OOM_WEIGHT = 0.5           -- group/raid mana weight when the fight outlasts the mana
M.FIGHT_MANA_PER_SEC = 0.01  -- share of max mana spent per second, for the OOM projection
M.READY_KEYS = { "stormstrike", "lavaLash", "earthShock", "fireNova" }

local function weights(S) return M.WEIGHTS[S.mode] or M.WEIGHTS.group end

-- damage points one mana point is worth; scales with the character through AP + SP
function M.manaPrice(S)
  local p = S.player
  local ref = ((p.ap or 0) + (p.spNature or 0)) / 4000
  local w = weights(S)
  if S.mode == "solo" then
    local frac = (p.manaMax and p.manaMax > 0) and (p.mana / p.manaMax) or 1
    local scarcity = 1 + 3 * (1 - frac) * (1 - frac)
    local rage = S.spells.shamanisticRage
    if not rage or rage.cd > 0 then scarcity = scarcity * 1.5 end
    return w.mana * scarcity * ref
  end
  local ttd = S.target.ttd
  if ttd and p.manaMax and p.mana < ttd * p.manaMax * M.FIGHT_MANA_PER_SEC then
    return M.OOM_WEIGHT * ref
  end
  return w.mana * ref
end

function M.step(S, S2, dmg, manaSpent)
  local w = weights(S)
  local hpLeft = math.max(0, S.target.hp or 0)
  local useful = math.min(dmg, hpLeft)
  local v = useful + (dmg - useful) * w.overkill - (manaSpent or 0) * M.manaPrice(S)
  if w.kill > 0 and hpLeft > 0 and (S2.target.hp or 0) <= 0 then
    v = v + w.kill * (S.target.hpMax or hpLeft)
  end
  return v
end

local function lifetime(S, remains)
  if S.target.ttd then return math.min(remains, S.target.ttd) end
  return remains
end

local function flameShockValue(S)
  local fs = S.target.fs or 0
  if fs <= 0 then return 0 end
  local perTick, _, period = damage.dot(S, "flameShock")
  return math.floor(lifetime(S, fs) / period) * perTick * M.DISCOUNT
end

local function totemValue(S)
  local fire = S.totems.fire
  if not fire.kind or fire.kind == "fireElemental" or (fire.remains or 0) <= 0 then return 0 end
  local key = fire.kind == "magma" and "magmaTotem" or "searingTotem"
  local perTick, _, period = damage.dot(S, key)
  return math.floor(lifetime(S, fire.remains) / period) * perTick * damage.targets(S, key) * M.DISCOUNT
end

local function maelstromValue(S)
  local stacks = math.min(5, (S.buffs.mw and S.buffs.mw.stacks) or 0)
  if stacks <= 0 or not S.spells.lightningBolt then return 0 end
  return stacks * M.MW_SHARE * damage.action(S, "lightningBolt")
end

local function readyValue(S)
  local v = 0
  for _, key in ipairs(M.READY_KEYS) do
    local sp = S.spells[key]
    if sp and sp.cd <= 0 and (key ~= "fireNova" or S.totems.fire.kind) then
      v = v + damage.action(S, key) * damage.targets(S, key) * M.DISCOUNT
    end
  end
  return v
end

function M.terminal(S)
  return maelstromValue(S) + flameShockValue(S) + totemValue(S) + readyValue(S)
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `docker compose run --rm test busted spec/value_spec.lua`
Expected: PASS (10 successes)

- [ ] **Step 5: Commit**

```bash
git add src/value.lua spec/value_spec.lua
git commit -m "Оценка цепочки действий по режиму игры"
```

---

### Task 10: Лучевой поиск (`src/search.lua`)

**Files:**
- Create: `src/search.lua`
- Create: `spec/support/stub_model.lua`
- Test: `spec/search_spec.lua` (на игрушечной модели)
- Test: `spec/search_integration_spec.lua` (на настоящих `model`/`value`)

**Interfaces:**
- Consumes:
  - `model.readyIn`, `model.apply`, `model.wait`, `model.actions` (часть 3, с дополнениями 4–7);
  - `value.step`, `value.terminal` (задача 9);
  - `fixtures.state` (часть 1).
- Produces:
  - `search.best(S, opts) -> { value, steps = { {key, at, reason} }, timedOut }`;
  - `search.evaluate(S, steps, opts) -> value, retimedSteps | nil`;
  - `search.signature(S)`, `search.reason(S, key, afterSwing)`;
  - константы `search.HORIZON = 6.0`, `search.BEAM = 6`, `search.DEPTH = 4`, `search.BUDGET_MS = 2`.

Как устроен поиск:
- Слой за слоем каждый узел расширяется всеми кандидатами из `model.actions`.
- Если `readyIn > 0.05`, сначала `model.wait(readyIn)`, потом `model.apply`.
- `waitSwing` — ожидание без шага. Два ожидания подряд запрещены. Следующий за ним шаг получает причину «after swing - no clip».
- Каждый новый узел сразу оценивается как возможный конец плана: время дотягивается ожиданием до горизонта, прибавляется `value.terminal`. Поэтому цепочки разной длины сравниваются честно.
- Одинаковые состояния склеиваются по `signature`.
- Остаются `BEAM` лучших узлов, при равенстве порядок решает строка ключей — это детерминизм.
- Если бюджет времени кончился, возвращается лучший найденный план.

- [ ] **Step 1: Write the stub model**

`spec/support/stub_model.lua`:

```lua
-- Toy model honouring the model contract: direct-damage buttons, a shared cooldown group
-- and one DoT (tracked in S.target.fs). Numbers are chosen by each test.
local M = {}
M.GCD = 1.5
M.DOT_DPS = 10
M.SPELLS = {}

local function copy(t)
  if type(t) ~= "table" then return t end
  local n = {}
  for k, v in pairs(t) do n[k] = copy(v) end
  return n
end

function M.setup(spells) M.SPELLS = spells end

function M.state(o)
  o = o or {}
  local S = {
    now = 0, gcdRemains = o.gcdRemains or 0, castRemains = 0, mode = "group",
    player = { mana = 1000, manaMax = 1000 },
    buffs = { mw = { stacks = o.mw or 0, remains = 0 } },
    target = { hp = 1e6, hpMax = 1e6, fs = o.fs or 0, ttd = 60 },
    swing = { attacking = true, mh = { next = o.swing or 99, speed = 2 } },
    enemies = { melee = 1, nearby = 1 },
    totems = { fire = { remains = 0 }, water = { remains = 0 } },
    spells = {},
  }
  for k in pairs(M.SPELLS) do S.spells[k] = { cd = (o.cd and o.cd[k]) or 0 } end
  return S
end

local function tick(S, dt)
  local dmg = 0
  if S.target.fs > 0 then
    local t = math.min(dt, S.target.fs)
    dmg = t * M.DOT_DPS
    S.target.fs = S.target.fs - t
  end
  for _, sp in pairs(S.spells) do sp.cd = math.max(0, sp.cd - dt) end
  S.gcdRemains = math.max(0, S.gcdRemains - dt)
  S.swing.mh.next = S.swing.mh.next - dt
  if S.swing.mh.next <= 0 then S.swing.mh.next = S.swing.mh.next + S.swing.mh.speed end
  S.now = S.now + dt
  S.target.hp = math.max(0, S.target.hp - dmg)
  return dmg
end

function M.readyIn(S, key)
  local sp = S.spells[key]
  if not sp then return nil end
  return math.max(S.gcdRemains, S.castRemains, sp.cd)
end

function M.castTime() return 0 end

function M.wait(S, dt)
  local n = copy(S)
  return n, tick(n, dt)
end

function M.apply(S, key)
  local n = copy(S)
  local def = M.SPELLS[key]
  local direct = def.dmg or 0
  n.target.hp = math.max(0, n.target.hp - direct)
  if def.dot then n.target.fs = def.dot end
  for k, other in pairs(M.SPELLS) do
    if k == key or (def.shared and other.shared == def.shared) then n.spells[k].cd = def.cd or 0 end
  end
  n.player.mana = n.player.mana - (def.cost or 0)
  n.gcdRemains = M.GCD
  local dmg = direct + tick(n, M.GCD)
  return n, dmg, M.GCD
end

function M.actions(S)
  local keys = {}
  for k in pairs(S.spells) do keys[#keys + 1] = k end
  table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do
    local r = M.readyIn(S, k)
    if r and r < 6 then out[#out + 1] = { key = k, readyIn = r } end
  end
  if S.swing.attacking and S.swing.mh.next < 6 then
    out[#out + 1] = { key = "waitSwing", readyIn = S.swing.mh.next + 0.01 }
  end
  return out
end

M.value = {
  step = function(_, _, dmg) return dmg end,
  terminal = function(S) return (S.target.fs or 0) * M.DOT_DPS * 0.5 end,
}

return M
```

- [ ] **Step 2: Write the failing unit tests**

`spec/search_spec.lua`:

```lua
local search = require("search")
local stub = require("stub_model")

local function opts(extra)
  local o = { model = stub, value = stub.value, budgetMs = 1e9 }
  for k, v in pairs(extra or {}) do o[k] = v end
  return o
end

local function keys(plan)
  local out = {}
  for i, s in ipairs(plan.steps) do out[i] = s.key end
  return table.concat(out, ",")
end

describe("search.best", function()
  it("shared shock cooldown: prefers an expired Flame Shock although Earth Shock hits harder now", function()
    stub.setup({
      es = { dmg = 100, cd = 5, shared = "shock" },
      fs = { dmg = 40, dot = 12, cd = 5, shared = "shock" },
      filler = { dmg = 30, cd = 0 },
    })
    assert.is_true(stub.SPELLS.es.dmg > stub.SPELLS.fs.dmg)
    local plan = search.best(stub.state({ fs = 0 }), opts())
    assert.are.equal("fs", plan.steps[1].key)
    assert.is_false(plan.timedOut)
  end)

  it("waits for a button that becomes ready inside the horizon", function()
    stub.setup({ big = { dmg = 300, cd = 10 } })
    local plan = search.best(stub.state({ cd = { big = 1.0 } }), opts())
    assert.are.equal("big", plan.steps[1].key)
    assert.are.near(1.0, plan.steps[1].at, 1e-9)
  end)

  it("never plans before the global cooldown ends", function()
    stub.setup({ a = { dmg = 50, cd = 0 } })
    local plan = search.best(stub.state({ gcdRemains = 1.0 }), opts())
    assert.are.near(1.0, plan.steps[1].at, 1e-9)
  end)

  it("never plans a step at or after the horizon", function()
    stub.setup({ a = { dmg = 50, cd = 0 }, b = { dmg = 20, cd = 0 } })
    local plan = search.best(stub.state(), opts())
    assert.is_true(#plan.steps >= 1 and #plan.steps <= search.DEPTH)
    for _, s in ipairs(plan.steps) do assert.is_true(s.at < search.HORIZON) end
  end)

  it("a step after waitSwing is marked 'after swing - no clip'", function()
    stub.setup({ a = { dmg = 50, cd = 0 } })
    local S = stub.state({ swing = 0.3, mw = 3 })
    stub.value.step = function(_, S2, dmg) return dmg + ((S2.now >= 0.3 and S2.now < 0.35) and 1000 or 0) end
    local plan = search.best(S, opts())
    stub.value.step = function(_, _, dmg) return dmg end
    assert.are.equal("a", plan.steps[1].key)
    assert.are.near(0.31, plan.steps[1].at, 1e-9)
  end)

  it("returns the best plan found so far when the time budget runs out", function()
    stub.setup({ a = { dmg = 50, cd = 0 }, b = { dmg = 20, cd = 0 }, c = { dmg = 10, cd = 0 } })
    local t = 0
    local plan = search.best(stub.state(), opts({ budgetMs = 2, clock = function() t = t + 1; return t end }))
    assert.is_true(plan.timedOut)
    assert.is_true(#plan.steps >= 1)
  end)

  it("is deterministic", function()
    stub.setup({ a = { dmg = 50, cd = 3 }, b = { dmg = 50, cd = 3 }, c = { dmg = 20, cd = 0 } })
    local p1 = search.best(stub.state(), opts())
    local p2 = search.best(stub.state(), opts())
    assert.are.equal(keys(p1), keys(p2))
    assert.are.equal(p1.value, p2.value)
  end)

  it("returns an empty plan when nothing can be pressed", function()
    stub.setup({})
    local plan = search.best(stub.state(), opts())
    assert.are.equal(0, #plan.steps)
    assert.are.equal(0, plan.value)
  end)
end)

describe("search.evaluate", function()
  it("replays planned steps and keeps a planned wait", function()
    stub.setup({ a = { dmg = 50, cd = 0 } })
    local v, steps = search.evaluate(stub.state(), { { key = "a", at = 0.5, reason = "r" } }, opts())
    assert.is_number(v)
    assert.are.near(0.5, steps[1].at, 1e-9)
    assert.are.equal("r", steps[1].reason)
  end)

  it("returns nil when a planned step is no longer possible", function()
    stub.setup({ a = { dmg = 50, cd = 0 } })
    assert.is_nil(search.evaluate(stub.state(), { { key = "gone", at = 0, reason = "" } }, opts()))
  end)
end)

describe("search.signature and reason", function()
  it("ignores irrelevant fields but not cooldowns", function()
    stub.setup({ a = { dmg = 1, cd = 0 } })
    local s1, s2, s3 = stub.state(), stub.state(), stub.state({ cd = { a = 2 } })
    s2.enemies.nearby = 5
    assert.are.equal(search.signature(s1), search.signature(s2))
    assert.are_not.equal(search.signature(s1), search.signature(s3))
  end)

  it("explains Lightning Bolt and Flame Shock", function()
    stub.setup({})
    assert.are.equal("5 Maelstrom stacks", search.reason(stub.state({ mw = 5 }), "lightningBolt", false))
    assert.are.equal("after swing - no clip", search.reason(stub.state({ mw = 3 }), "lightningBolt", true))
    assert.are.equal("3 Maelstrom stacks", search.reason(stub.state({ mw = 3 }), "lightningBolt", false))
    assert.are.equal("Flame Shock expired", search.reason(stub.state({ fs = 0 }), "flameShock", false))
    assert.are.equal("refresh Flame Shock", search.reason(stub.state({ fs = 4 }), "flameShock", false))
  end)
end)
```

В тесте про `waitSwing` ценность шага временно подменяется: бонус 1000 дают только нажатия, которые заканчиваются сразу после удара (`0.3 ≤ now < 0.35`). Так проверяется механика ожидания, а не цифры урона. Проверка «ждать удара выгодно» — в интеграционном тесте ниже.

- [ ] **Step 3: Run test to verify it fails**

Run: `docker compose run --rm test busted spec/search_spec.lua`
Expected: FAIL with `module 'search' not found`

- [ ] **Step 4: Write minimal implementation**

`src/search.lua`:

```lua
local M = {}

M.HORIZON = 6.0
M.BEAM = 6
M.DEPTH = 4
M.BUDGET_MS = 2
M.READY_EPS = 0.05

M.REASONS = {
  stormstrike = "Stormstrike: +20% nature",
  lavaLash = "filler",
  earthShock = "shock filler",
  frostShock = "shock filler",
  searingTotem = "no fire totem",
  fireElemental = "big cooldown",
  feralSpirit = "big cooldown",
  callOfElements = "totems expiring",
  lightningShield = "Lightning Shield missing",
}

local function q(x) return math.floor((x or 0) * 4 + 0.5) end

function M.signature(S)
  local hpStep = math.max(1, (S.target.hpMax or 1) * 0.005)
  local parts = {
    q(S.now), math.floor((S.player.mana or 0) / 50),
    q(S.buffs.mw and S.buffs.mw.stacks), q(S.target.fs), math.floor((S.target.hp or 0) / hpStep),
  }
  local keys = {}
  for k in pairs(S.spells) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do parts[#parts + 1] = k .. q(S.spells[k].cd) end
  return table.concat(parts, ":")
end

function M.reason(S, key, afterSwing)
  local mw = (S.buffs and S.buffs.mw and S.buffs.mw.stacks) or 0
  if key == "lightningBolt" or key == "chainLightning" then
    if mw >= 5 then return "5 Maelstrom stacks" end
    if afterSwing then return "after swing - no clip" end
    return ("%d Maelstrom stacks"):format(math.floor(mw))
  elseif key == "flameShock" then
    return (S.target.fs or 0) <= 0 and "Flame Shock expired" or "refresh Flame Shock"
  elseif key == "fireNova" or key == "magmaTotem" then
    local n = (S.enemies and S.enemies.nearby) or 1
    if n >= 2 then return ("%d targets"):format(n) end
    return key == "fireNova" and "Fire Nova ready" or "Magma Totem down"
  elseif key == "shamanisticRage" then
    local p = S.player
    return (p.manaMax and p.mana / p.manaMax < 0.3) and "low mana" or "damage cooldown"
  end
  return M.REASONS[key] or key
end

local function defaultClock()
  if os and os.clock then return os.clock() * 1000 end
  return 0
end

local function defaults(opts)
  opts = opts or {}
  return {
    model = opts.model or require("model"),
    value = opts.value or require("value"),
    horizon = opts.horizon or M.HORIZON,
    beam = opts.beam or M.BEAM,
    depth = opts.depth or M.DEPTH,
    budgetMs = opts.budgetMs or M.BUDGET_MS,
    clock = opts.clock or defaultClock,
  }
end

-- pad the chain with waiting up to the horizon, then add what the end state is still worth
local function finalScore(o, node, rootNow)
  local S, v = node.S, node.v
  local t = S.now - rootNow
  if t < o.horizon then
    local S2, dmg = o.model.wait(S, o.horizon - t)
    v = v + o.value.step(S, S2, dmg, 0)
    S = S2
  end
  return v + o.value.terminal(S)
end

local function extend(o, node, a, rootNow)
  local S, v = node.S, node.v
  if a.key == "waitSwing" then
    if node.waited or S.now + a.readyIn - rootNow >= o.horizon then return nil end
    local S1, d = o.model.wait(S, a.readyIn)
    return { S = S1, v = v + o.value.step(S, S1, d, 0), steps = node.steps, depth = node.depth,
             waited = true, afterSwing = true }
  end
  local afterSwing = node.afterSwing
  if a.readyIn > M.READY_EPS then
    if S.now + a.readyIn - rootNow >= o.horizon then return nil end
    local S1, d = o.model.wait(S, a.readyIn)
    v = v + o.value.step(S, S1, d, 0)
    S = S1
    afterSwing = false
  end
  local at = S.now - rootNow
  if at >= o.horizon then return nil end
  local S2, dmg = o.model.apply(S, a.key)
  v = v + o.value.step(S, S2, dmg, (S.player.mana or 0) - (S2.player.mana or 0))
  local steps = {}
  for i, s in ipairs(node.steps) do steps[i] = s end
  steps[#steps + 1] = { key = a.key, at = at, reason = M.reason(S, a.key, afterSwing) }
  return { S = S2, v = v, steps = steps, depth = node.depth + 1 }
end

local function chainKey(node)
  local parts = {}
  for i, s in ipairs(node.steps) do parts[i] = s.key .. "@" .. q(s.at) end
  return table.concat(parts, ",") .. (node.waited and "+w" or "")
end

function M.best(S, opts)
  local o = defaults(opts)
  local start = o.clock()
  local rootNow = S.now
  local frontier = { { S = S, v = 0, steps = {}, depth = 0 } }
  local best = { value = -math.huge, steps = {} }
  local timedOut = false
  for _ = 1, o.depth * 2 do
    local seen, order = {}, {}
    for _, node in ipairs(frontier) do
      if node.depth < o.depth then
        for _, a in ipairs(o.model.actions(node.S)) do
          local c = extend(o, node, a, rootNow)
          if c then
            c.score = finalScore(o, c, rootNow)
            if #c.steps > 0 and c.score > best.value then best = { value = c.score, steps = c.steps } end
            local sig = M.signature(c.S) .. (c.waited and "w" or "")
            local prev = seen[sig]
            if not prev then order[#order + 1] = sig end
            if not prev or c.score > prev.score then seen[sig] = c end
            if o.clock() - start > o.budgetMs then timedOut = true; break end
          end
        end
      end
      if timedOut then break end
    end
    if timedOut then break end
    local children = {}
    for i, sig in ipairs(order) do children[i] = seen[sig] end
    table.sort(children, function(x, y)
      if x.score ~= y.score then return x.score > y.score end
      return chainKey(x) < chainKey(y)
    end)
    frontier = {}
    for i = 1, math.min(o.beam, #children) do frontier[i] = children[i] end
    if #frontier == 0 then break end
  end
  if best.value == -math.huge then return { value = 0, steps = {}, timedOut = timedOut } end
  return { value = best.value, steps = best.steps, timedOut = timedOut }
end

-- replay an existing plan on a fresh state; nil if a step is no longer possible
function M.evaluate(S, steps, opts)
  local o = defaults(opts)
  local rootNow = S.now
  local node = { S = S, v = 0, steps = {}, depth = 0 }
  for _, st in ipairs(steps) do
    local r = o.model.readyIn(node.S, st.key)
    if r == nil then return nil end
    local planned = st.at - (node.S.now - rootNow)
    local c = extend(o, node, { key = st.key, readyIn = math.max(r, planned) }, rootNow)
    if not c then break end
    c.steps[#c.steps].reason = st.reason
    node = c
  end
  if #node.steps == 0 then return nil end
  return finalScore(o, node, rootNow), node.steps
end

return M
```

- [ ] **Step 5: Run unit tests to verify they pass**

Run: `docker compose run --rm test busted spec/search_spec.lua`
Expected: PASS (12 successes)

- [ ] **Step 6: Write the failing integration tests**

`spec/search_integration_spec.lua`. Проверяются три случая из правил wowsims на настоящих `model`/`damage`/`value`:
1. спавший Flame Shock важнее Earth Shock;
2. при 5 стаках — Lightning Bolt;
3. 3 стака, Windfury, правая рука ударит через 0.3 с, левая — через 1.5 с. Правило wowsims `MW>=3 && castTime+300ms < timeToNextSwing` выполняется только после удара правой, поэтому ждём удар и кастуем. Каст сразу задержал бы удар правой на ~0.6 с.

```lua
local search = require("search")
local fixtures = require("fixtures")

local function merge(a, b)
  for k, v in pairs(b) do
    if type(v) == "table" and type(a[k]) == "table" then merge(a[k], v) else a[k] = v end
  end
  return a
end

-- level 80, every button except the ones a test frees is on cooldown, magma already down
local function busy(over)
  local base = {
    spells = {
      stormstrike = { cd = 9 }, lavaLash = { cd = 9 }, earthShock = { cd = 9 }, flameShock = { cd = 9 },
      frostShock = { cd = 9 }, fireNova = { cd = 9 }, chainLightning = { cd = 9 }, feralSpirit = { cd = 90 },
      fireElemental = { cd = 90 }, shamanisticRage = { cd = 50 }, callOfElements = { cd = 0 },
    },
    totems = { fire = { kind = "magma", remains = 20 }, water = { remains = 100 } },
    buffs = { ls = { charges = 3, remains = 600 }, mw = { stacks = 0, remains = 0 } },
    target = { fs = 10 },
    weapons = { mh = { enchant = "wf" }, oh = { enchant = "ft" } },
  }
  return fixtures.state(merge(base, over or {}))
end

describe("search on the real model (wowsims rules)", function()
  it("an expired Flame Shock goes before Earth Shock", function()
    local plan = search.best(busy({ spells = { flameShock = { cd = 0 }, earthShock = { cd = 0 } }, target = { fs = 0 } }),
      { budgetMs = 1e9 })
    assert.are.equal("flameShock", plan.steps[1].key)
    assert.are.equal("Flame Shock expired", plan.steps[1].reason)
  end)

  it("5 Maelstrom stacks -> instant Lightning Bolt", function()
    local plan = search.best(busy({ buffs = { mw = { stacks = 5, remains = 20 } } }), { budgetMs = 1e9 })
    assert.are.equal("lightningBolt", plan.steps[1].key)
    assert.are.equal("5 Maelstrom stacks", plan.steps[1].reason)
  end)

  it("3 stacks: waits for the main-hand swing, then weaves Lightning Bolt without a clip", function()
    local S = busy({
      buffs = { mw = { stacks = 3, remains = 20 } },
      player = { meleeHaste = 1.25, spellHaste = 1.10 },
      swing = { attacking = true, mh = { next = 0.3, speed = 2.6 }, oh = { next = 1.5, speed = 2.6 } },
    })
    local plan = search.best(S, { budgetMs = 1e9 })
    assert.are.equal("lightningBolt", plan.steps[1].key)
    assert.is_true(plan.steps[1].at >= 0.29 and plan.steps[1].at < 0.45, "at=" .. plan.steps[1].at)
    assert.are.equal("after swing - no clip", plan.steps[1].reason)
  end)
end)
```

- [ ] **Step 7: Run integration tests**

Run: `docker compose run --rm test busted spec/search_integration_spec.lua`
Expected: PASS (3 successes).

Если падает, сначала проверить модель, а не поиск:
- `model.apply(S, "lightningBolt")` при 3 стаках должна задерживать удар, который выпадает на каст (часть 3, спека §6.4);
- `model.actions` должна выдавать `waitSwing` (дополнение 4).

Подкручивать тест под результат нельзя. Если поиск прав, а правило wowsims здесь неприменимо, это записывается комментарием в тесте с обоснованием (спека §10.2).

- [ ] **Step 8: Commit**

```bash
git add src/search.lua spec/search_spec.lua spec/search_integration_spec.lua spec/support/stub_model.lua
git commit -m "Лучевой поиск плана на 6 секунд вперёд"
```

---

### Task 11: Планировщик и стабильность (`src/planner.lua`)

**Files:**
- Create: `src/planner.lua`
- Test: `spec/planner_spec.lua` (заглушка поиска)
- Test: `spec/stability_spec.lua` (покадровое проигрывание, настоящий поиск)
- Test: `spec/perf_spec.lua`

**Interfaces:**
- Consumes:
  - `search.best`, `search.evaluate` (задача 10);
  - `util.copy`, `fixtures.state` (часть 1);
  - `model.wait` (часть 3) — только в `stability_spec`.
- Produces:
  - `planner.new(opts) -> p`, где `opts = { search =, searchOpts =, hysteresis = }`;
  - `p:update(S, ev) -> plan`;
  - `p.inflight` (ключ → момент, когда перестать считать эффект наложенным);
  - константы `planner.HYSTERESIS = 0.03`, `planner.INFLIGHT = 1.0`;
  - `planner.EFFECTS[key](S)` — как «летящее» заклинание меняет снимок.

Правила (спека §7):
- **Замена плана.** Новый план заменяет текущий, если:
  - текущего нет;
  - пришло событие `target`;
  - игрок скастовал не то, что стояло первым;
  - прежний план не переигрывается на новом `S` (`evaluate` вернул `nil`);
  - новый ценнее хотя бы на `|old| * HYSTERESIS`.

  Иначе остаётся прежний план с пересчитанными `at`.
- **Каст первого шага.** Шаг считается выполненным: остаток плана переигрывается без него.
- **«Летящие» заклинания.** После события `cast` эффект заклинания 1 с считается уже наложенным: `EFFECTS` правит копию `S` перед поиском.

- [ ] **Step 1: Write the failing unit tests**

`spec/planner_spec.lua`:

```lua
local planner = require("planner")
local fixtures = require("fixtures")

local function stubSearch(script)
  local s = { seen = {} }
  function s.best(S)
    s.seen[#s.seen + 1] = S
    return { value = script.best, steps = script.steps or { { key = script.bestKey or "fresh", at = 0, reason = "" } } }
  end
  function s.evaluate(_, steps)
    s.lastEval = steps
    if script.evaluate == false then return nil end
    return script.evaluate, steps
  end
  return s
end

local function at(now, over)
  local o = { now = now }
  for k, v in pairs(over or {}) do o[k] = v end
  return fixtures.state(o)
end

describe("planner", function()
  it("takes the first plan as is", function()
    local p = planner.new({ search = stubSearch({ best = 100, bestKey = "a" }) })
    assert.are.equal("a", p:update(at(100)).steps[1].key)
  end)

  it("holds the current plan when the new one is less than 3% better", function()
    local script = { best = 100, bestKey = "a" }
    local p = planner.new({ search = stubSearch(script) })
    p:update(at(100))
    script.best, script.bestKey, script.evaluate = 102, "b", 100
    local plan = p:update(at(100.1))
    assert.are.equal("a", plan.steps[1].key)
    assert.is_true(plan.held)
  end)

  it("switches when the new plan is more than 3% better", function()
    local script = { best = 100, bestKey = "a" }
    local p = planner.new({ search = stubSearch(script) })
    p:update(at(100))
    script.best, script.bestKey, script.evaluate = 104, "b", 100
    assert.are.equal("b", p:update(at(100.1)).steps[1].key)
  end)

  it("hysteresis works with negative values", function()
    local script = { best = -100, bestKey = "a" }
    local p = planner.new({ search = stubSearch(script) })
    p:update(at(100))
    script.best, script.bestKey, script.evaluate = -99, "b", -100
    assert.are.equal("a", p:update(at(100.1)).steps[1].key)
  end)

  it("switches when the held plan can no longer be played", function()
    local script = { best = 100, bestKey = "a" }
    local p = planner.new({ search = stubSearch(script) })
    p:update(at(100))
    script.best, script.bestKey, script.evaluate = 50, "b", false
    assert.are.equal("b", p:update(at(100.1)).steps[1].key)
  end)

  it("switches when the player cast something else", function()
    local script = { best = 100, bestKey = "a" }
    local p = planner.new({ search = stubSearch(script) })
    p:update(at(100))
    script.best, script.bestKey, script.evaluate = 101, "b", 100
    assert.are.equal("b", p:update(at(100.1), { kind = "cast", key = "earthShock" }).steps[1].key)
  end)

  it("switches on target change", function()
    local script = { best = 100, bestKey = "a" }
    local p = planner.new({ search = stubSearch(script) })
    p:update(at(100))
    script.best, script.bestKey, script.evaluate = 100, "b", 100
    assert.are.equal("b", p:update(at(100.1), { kind = "target" }).steps[1].key)
  end)

  it("casting the planned first step drops it and replays the rest", function()
    local script = { best = 100, steps = { { key = "stormstrike", at = 0, reason = "" }, { key = "lavaLash", at = 1.5, reason = "" } } }
    local s = stubSearch(script)
    local p = planner.new({ search = s })
    p:update(at(100))
    script.evaluate = 100
    p:update(at(100.2), { kind = "cast", key = "stormstrike" })
    assert.are.equal(1, #s.lastEval)
    assert.are.equal("lavaLash", s.lastEval[1].key)
    assert.are.near(1.3, s.lastEval[1].at, 1e-9)
  end)

  it("shifts held steps by the elapsed time", function()
    local script = { best = 100, steps = { { key = "a", at = 1.0, reason = "" } } }
    local s = stubSearch(script)
    local p = planner.new({ search = s })
    p:update(at(100))
    script.evaluate = 100
    p:update(at(100.4))
    assert.are.near(0.6, s.lastEval[1].at, 1e-9)
  end)

  it("treats a just-cast Flame Shock as applied for up to 1 second", function()
    local s = stubSearch({ best = 100 })
    local p = planner.new({ search = s })
    p:update(at(100, { target = { fs = 0 } }), { kind = "cast", key = "flameShock" })
    assert.is_true(s.seen[1].target.fs >= 12)
    assert.is_true(s.seen[1].inflight.flameShock > 0)
    p:update(at(100.5, { target = { fs = 0 } }))
    assert.is_true(s.seen[2].target.fs >= 12)
    p:update(at(101.2, { target = { fs = 0 } }))
    assert.are.equal(0, s.seen[3].target.fs)
    assert.is_nil(p.inflight.flameShock)
  end)

  it("does not mutate the snapshot it was given", function()
    local p = planner.new({ search = stubSearch({ best = 100 }) })
    local S = at(100, { target = { fs = 0 } })
    p:update(S, { kind = "cast", key = "flameShock" })
    assert.are.equal(0, S.target.fs)
  end)

  it("survives empty plans", function()
    local script = { best = 0, steps = {} }
    local p = planner.new({ search = stubSearch(script) })
    assert.are.equal(0, #p:update(at(100)).steps)
    assert.are.equal(0, #p:update(at(100.25)).steps)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose run --rm test busted spec/planner_spec.lua`
Expected: FAIL with `module 'planner' not found`

- [ ] **Step 3: Write minimal implementation**

`src/planner.lua`:

```lua
local util = require("util")

local M = {}

M.HYSTERESIS = 0.03
M.INFLIGHT = 1.0

-- what a just-cast spell does before the game confirms it with an aura update
M.EFFECTS = {
  flameShock = function(S) S.target.fs = math.max(S.target.fs or 0, 12) end,
  stormstrike = function(S) S.target.ss = { charges = 4, remains = 12 } end,
  lightningShield = function(S) S.buffs.ls = { charges = 3, remains = 600 } end,
  lightningBolt = function(S)
    if S.buffs.mw.stacks >= 5 then S.buffs.mw = { stacks = 0, remains = 0 } end
  end,
}
M.EFFECTS.chainLightning = M.EFFECTS.lightningBolt

local P = {}
P.__index = P

function M.new(opts)
  opts = opts or {}
  return setmetatable({
    search = opts.search or require("search"),
    searchOpts = opts.searchOpts,
    hysteresis = opts.hysteresis or M.HYSTERESIS,
    inflight = {},
    plan = nil,
    planNow = nil,
  }, P)
end

function P:prepare(S)
  local n = util.copy(S)
  n.inflight = {}
  for key, expires in pairs(self.inflight) do
    local left = expires - S.now
    if left > 0 then
      n.inflight[key] = left
      local fx = M.EFFECTS[key]
      if fx then fx(n) end
    else
      self.inflight[key] = nil
    end
  end
  return n
end

local function shifted(plan, elapsed, dropFirst)
  local steps = {}
  for i, st in ipairs(plan.steps) do
    if not (dropFirst and i == 1) then
      steps[#steps + 1] = { key = st.key, at = math.max(0, st.at - elapsed), reason = st.reason }
    end
  end
  return steps
end

function P:update(S, ev)
  ev = ev or { kind = "pulse" }
  local first = self.plan and self.plan.steps[1]
  local force = self.plan == nil or ev.kind == "target"
  local consumed = false
  if ev.kind == "cast" and ev.key then
    self.inflight[ev.key] = S.now + M.INFLIGHT
    if first and first.key == ev.key then consumed = true else force = true end
  end
  local s = self:prepare(S)
  local fresh = self.search.best(s, self.searchOpts)
  if not force then
    local old = shifted(self.plan, s.now - self.planNow, consumed)
    if #old > 0 then
      local oldValue, retimed = self.search.evaluate(s, old, self.searchOpts)
      if oldValue and fresh.value <= oldValue + math.abs(oldValue) * self.hysteresis then
        self.plan = { value = oldValue, steps = retimed, timedOut = fresh.timedOut, held = true }
        self.planNow = s.now
        return self.plan
      end
    end
  end
  self.plan = fresh
  self.planNow = s.now
  return fresh
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `docker compose run --rm test busted spec/planner_spec.lua`
Expected: PASS (12 successes)

- [ ] **Step 5: Write the stability and performance specs**

`spec/stability_spec.lua` (спека §10.4). Бой проигрывается кадрами по 0.05 с, «реальность» двигает сама `model.wait`. Автоатака выключена, чтобы ожидаемые доли стаков Maelstrom не меняли состояние между кадрами — иначе это были бы «события», которых в игре нет.

```lua
local planner = require("planner")
local model = require("model")
local fixtures = require("fixtures")

local FRAME = 0.05

local function quiet()
  return fixtures.state({
    swing = { attacking = false },
    target = { fs = 8 },
    buffs = { mw = { stacks = 2, remains = 20 } },
  })
end

local function replay(frames, onFrame)
  local p = planner.new({ searchOpts = { budgetMs = 1e9 } })
  local S = quiet()
  local firsts = {}
  for i = 1, frames do
    local ev = { kind = "pulse" }
    if onFrame then S, ev = onFrame(i, S, ev) end
    local plan = p:update(S, ev)
    firsts[i] = plan.steps[1] and plan.steps[1].key or "-"
    S = model.wait(S, FRAME)
  end
  return firsts
end

local function changes(firsts, from, to)
  local n = 0
  for i = from + 1, to do if firsts[i] ~= firsts[i - 1] then n = n + 1 end end
  return n
end

describe("stability", function()
  it("the first step does not change over 3 seconds without events", function()
    local firsts = replay(60)
    assert.are_not.equal("-", firsts[1])
    assert.are.equal(0, changes(firsts, 1, 60), table.concat(firsts, " "))
  end)

  it("a Maelstrom proc changes the first step at most once, and only after the proc", function()
    local firsts = replay(60, function(i, S, ev)
      if i == 20 then
        local n = require("util").copy(S)
        n.buffs.mw = { stacks = 5, remains = 30 }
        return n, { kind = "aura" }
      end
      return S, ev
    end)
    assert.are.equal(0, changes(firsts, 1, 19), table.concat(firsts, " "))
    assert.is_true(changes(firsts, 19, 60) <= 1, table.concat(firsts, " "))
  end)
end)
```

В кадре 20 копируется `S`, у которого сразу 5 стаков. Следующие кадры идут уже от него: `model.wait` продолжает именно эту копию, потому что `replay` присваивает `S` результат `onFrame`.

`spec/perf_spec.lua` (спека §10.5):

```lua
local search = require("search")
local fixtures = require("fixtures")

describe("performance", function()
  it("a full search on a level-80 state fits into 3x the in-game budget", function()
    local S = fixtures.state({})
    local runs = 20
    local t0 = os.clock()
    for _ = 1, runs do
      local plan = search.best(S, { budgetMs = 1e9 })
      assert.is_false(plan.timedOut)
    end
    local avgMs = (os.clock() - t0) * 1000 / runs
    assert.is_true(avgMs < search.BUDGET_MS * 3, ("average %.2f ms"):format(avgMs))
  end)
end)
```

- [ ] **Step 6: Run the stability and performance specs**

Run: `docker compose run --rm test busted spec/stability_spec.lua spec/perf_spec.lua`
Expected: PASS (3 successes)

**Если падает `perf_spec`** (среднее > 6 мс): нельзя поднимать бюджет или ослаблять тест. Порядок действий:
1. Профилировать `util.copy` в `model` — копировать только изменяемые ветки `S`.
2. Если не хватило — уменьшить `BEAM` до 5 и добавить тест, что три интеграционных сценария задачи 10 всё ещё проходят.

**Если падает `stability_spec`**:
1. Распечатать `firsts` — сообщение уже содержит их.
2. Найти поле `S`, которое меняется между кадрами и перевешивает гистерезис.
3. Исправить модель или оценку. Порог `HYSTERESIS` без обоснования не трогать.

- [ ] **Step 7: Commit**

```bash
git add src/planner.lua spec/planner_spec.lua spec/stability_spec.lua spec/perf_spec.lua
git commit -m "Планировщик: удержание плана, летящие заклинания, тесты стабильности"
```

---

## Кандидаты в Review Focus (для сводного раздела)

1. **Отрицательная ценность плана** (соло, мало маны, всё дорогое). Порог гистерезиса считается от `|old|`, иначе при `old < 0` любой новый план проходил бы порог. Покрыто тестом «hysteresis works with negative values».
2. **Нечего нажимать.** Уровень 1 без маны, нет цели, все кнопки за горизонтом. Поиск возвращает пустой план с `value = 0`, планировщик не падает на пустых планах. Покрыто тестами «returns an empty plan…» и «survives empty plans».
3. **Бюджет кончился на первом ребёнке.** Ребёнок-ожидание (`waitSwing`) без шагов не может стать лучшим планом, поэтому `best` остаётся пустым, а не ломает ленту. Покрыто проверкой `#c.steps > 0` и тестом таймаута.
4. **Снимок игры меняется у вызывающего.** Планировщик правит только копию (`prepare`). Покрыто тестом «does not mutate the snapshot».
5. **Моб умирает внутри горизонта.** Урон сверх здоровья в соло не ценится, тики после `ttd` не считаются. Покрыто тестами `value`: «solo: damage above…» и «limited by time to die».
