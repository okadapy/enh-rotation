## Contract additions

Дополнения к контракту модулей из этой части (остальные задачи должны использовать эти имена):

```lua
-- swing.lua
swing.new(saved) -> c                   -- saved: таблица для калибровки (aura_env.saved.swing), создаётся если nil
swing.HAND_TOLERANCE = 0.25
swing.CALIBRATE_VOTES = 3
swing.HORIZON = 6.0                     -- как далеко castWindow ищет окно
swing.CAST_RESET = { lightningBolt = true, chainLightning = true }
c:onAttack(now, on)                     -- PLAYER_ENTER_COMBAT (on=true) / PLAYER_LEAVE_COMBAT (on=false)
c:onSwing(now, isExtra) -> "mh"|"oh"|"extra"|nil   -- возвращает, какой руке приписан удар
c.resyncs                               -- счётчик пересинхронизаций (для /enhrot debug)
c.saved.votes[key] = { reset = n, keep = n }
c.saved.reset[key] = true|false         -- итог калибровки (nil = ещё не решено)
-- castWindow: если автоатака не идёт -> 0, swing.HORIZON; окна нет в горизонте -> nil

-- enemies.lua
enemies.MELEE_WINDOW = 2.5
enemies.NEARBY_WINDOW = 6
-- onEvent дополнительно понимает SPELL_SUMMON от игрока: призванный GUID (тотем, волки)
-- считается «своим», его урон по врагам учитывается в nearby.

-- ttd.lua
ttd.WINDOW = 10; ttd.MIN_SAMPLES = 3; ttd.MIN_SPAN = 1.5; ttd.HEAL_RESET = 0.05; ttd.FORGET = 30
t:reset(guid)                           -- забыть одну цель (nil = всех); вызывать при смене цели
```

Семантика времени в `swing`: внутри часы хранят **абсолютные** моменты (`due`), наружу `state(now)` отдаёт остатки `next = due - now` (не меньше 0) — ровно в форме `S.swing` из контракта.

---

### Task 4: Часы ударов (`src/swing.lua`)

Чистый модуль без вызовов API игры: время всегда передаётся аргументом. Логика событий взята из установленного у пользователя бэкпорта (`SwingTimerAPI`/`WeavingAPI` с wago.io/joURtkngg), но переписана с исправлениями из спеки §6:

- рука определяется по ближайшему ожидаемому удару в допуске `HAND_TOLERANCE`, вне допуска — пересинхронизация;
- лишние удары Windfury не двигают отсчёт;
- смена скорости масштабирует остаток;
- каст Bolt/Chain Lightning без стаков Maelstrom сбрасывает обе руки в конце каста, с 1–4 стаками — только откладывает созревшие удары до конца каста;
- мгновенные заклинания калибруются голосованием.

Почему для проверки калибровки в тестах используется двуручное оружие (одна рука): так ожидаемые моменты не зависят от левой руки, и тест детерминирован.

**Files:**
- Create: `src/swing.lua`
- Test: `spec/swing_spec.lua`

**Interfaces:**
- Consumes: ничего (чистый модуль).
- Produces: `swing.new(saved)`, методы `onAttack`, `onSwing`, `onExtraAttacks`, `onSpeed`, `onCastStart`, `onCastEnd`, `onInstant`, `state`, `castWindow`, поля `saved`, `resyncs`; константы `HAND_TOLERANCE`, `CALIBRATE_VOTES`, `HORIZON`, `CAST_RESET`. `state(now)` возвращает таблицу формы `S.swing`.

- [ ] **Step 1: Написать падающие тесты**

Create `spec/swing_spec.lua`:

```lua
local swing = require("swing")

-- Две руки по 2.6 с, атака начата в 100. После двух ударов:
-- mh due = 105.2, oh due = 105.4.
local function dual()
  local c = swing.new()
  c:onSpeed(100, 2.6, 2.6)
  c:onAttack(100, true)
  assert.are.equal("mh", c:onSwing(102.6, false))
  assert.are.equal("oh", c:onSwing(102.8, false))
  return c
end

-- Двуручник 3.6 с, один удар в 103.6 -> due = 107.2.
local function twoHand(saved)
  local c = swing.new(saved)
  c:onSpeed(100, 3.6, nil)
  c:onAttack(100, true)
  assert.are.equal("mh", c:onSwing(103.6, false))
  return c
end

-- Мгновенное заклинание за 1.3 с до ожидаемого удара, затем удар:
-- "reset" — удар пришёл через полную скорость после заклинания, "keep" — по старому отсчёту.
local function instantThenSwing(c, key, arrive)
  local s = c:state(0)
  local due = s.mh.next -- state(0) -> next = абсолютный due
  local t = due - 1.3
  c:onInstant(t, key)
  local at = arrive == "reset" and (t + 3.6) or due
  c:onSwing(at, false)
  return at
end

describe("swing", function()
  describe("speed and state", function()
    it("first onSpeed schedules each hand one full swing ahead", function()
      local c = swing.new()
      c:onSpeed(100, 2.6, 1.8)
      local s = c:state(100)
      assert.are.near(2.6, s.mh.next, 1e-9)
      assert.are.near(1.8, s.oh.next, 1e-9)
      assert.are.equal(2.6, s.mh.speed)
    end)

    it("has no oh when off-hand speed is nil", function()
      local c = swing.new()
      c:onSpeed(100, 3.6, nil)
      assert.is_nil(c:state(100).oh)
    end)

    it("removes oh when the off-hand disappears", function()
      local c = dual()
      c:onSpeed(103, 2.6, nil)
      assert.is_nil(c:state(103).oh)
      assert.is_not_nil(c:state(103).mh)
    end)

    it("reports attacking flag and never negative next", function()
      local c = dual()
      local s = c:state(110)
      assert.is_true(s.attacking)
      assert.are.equal(0, s.mh.next)
      c:onAttack(111, false)
      assert.is_false(c:state(111).attacking)
    end)

    it("speed change rescales the remaining time proportionally", function()
      local c = dual()                 -- mh due 105.2 (2.2 left at 103)
      c:onSpeed(103, 2.0, 2.6)         -- Flurry: 2.6 -> 2.0
      local s = c:state(103)
      assert.are.near(2.2 * 2.0 / 2.6, s.mh.next, 1e-9)
      assert.are.equal(2.0, s.mh.speed)
      assert.are.near(2.4, s.oh.next, 1e-9) -- oh untouched
    end)

    it("attack start pulls overdue hands to now", function()
      local c = swing.new()
      c:onSpeed(100, 2.6, 2.6)
      c:onAttack(110, true)
      local s = c:state(110)
      assert.are.equal(0, s.mh.next)
      assert.are.equal(0, s.oh.next)
    end)
  end)

  describe("hand attribution", function()
    it("attributes to the hand whose expected swing is nearest", function()
      local c = dual()
      local s = c:state(103)
      assert.are.near(2.2, s.mh.next, 1e-9)
      assert.are.near(2.4, s.oh.next, 1e-9)
      assert.are.equal("oh", c:onSwing(105.35, false))
      assert.are.equal("mh", c:onSwing(105.25, false))
      assert.are.equal(0, c.resyncs)
    end)

    it("resyncs to the earliest-due hand when no hand is within tolerance", function()
      local c = dual()                 -- mh 105.2, oh 105.4
      assert.are.equal("mh", c:onSwing(104.0, false))
      assert.are.equal(1, c.resyncs)
      assert.are.near(2.6, c:state(104.0).mh.next, 1e-9)
      assert.are.near(1.4, c:state(104.0).oh.next, 1e-9)
    end)

    it("returns nil when no weapon speed is known", function()
      local c = swing.new()
      assert.is_nil(c:onSwing(100, false))
    end)
  end)

  describe("extra attacks", function()
    it("explicit extra swing does not move timers", function()
      local c = dual()
      assert.are.equal("extra", c:onSwing(103.0, true))
      assert.are.near(2.2, c:state(103).mh.next, 1e-9)
    end)

    it("swing right after SPELL_EXTRA_ATTACKS is the extra one", function()
      local c = dual()                 -- mh 105.2
      assert.are.equal("mh", c:onSwing(105.2, false))  -- real swing, procs Windfury
      c:onExtraAttacks(105.2, 1)
      assert.are.equal("extra", c:onSwing(105.22, false))
      assert.are.near(107.8 - 105.3, c:state(105.3).mh.next, 1e-9)
    end)

    it("extra window expires after 0.1 s", function()
      local c = dual()
      c:onExtraAttacks(104.0, 1)
      assert.are_not.equal("extra", c:onSwing(105.2, false))
    end)
  end)

  describe("casts", function()
    it("Lightning Bolt with 0 Maelstrom resets both hands at cast end", function()
      local c = dual()
      c:onCastStart(103.0, "lightningBolt", 0, 2.5)
      -- во время каста прогноз уже учитывает сброс
      assert.are.near(105.5 + 2.6 - 103.0, c:state(103.0).mh.next, 1e-9)
      c:onCastEnd(105.5, "lightningBolt", 0, true)
      local s = c:state(105.5)
      assert.are.near(2.6, s.mh.next, 1e-9)
      assert.are.near(2.6, s.oh.next, 1e-9)
    end)

    it("Chain Lightning with 0 Maelstrom also resets", function()
      local c = dual()
      c:onCastStart(103.0, "chainLightning", 0, 2.0)
      c:onCastEnd(105.0, "chainLightning", 0, true)
      assert.are.near(2.6, c:state(105.0).mh.next, 1e-9)
    end)

    it("cast with 1-4 Maelstrom delays swings that come due during the cast", function()
      local c = dual()                 -- mh 105.2, oh 105.4
      c:onCastStart(104.0, "lightningBolt", 3, 1.5) -- ends 105.5
      local s = c:state(104.2)
      assert.are.near(1.3, s.mh.next, 1e-9)
      assert.are.near(1.3, s.oh.next, 1e-9)
      c:onCastEnd(105.5, "lightningBolt", 3, true)
      assert.are.equal(0, c:state(105.5).mh.next)
      assert.are.equal("mh", c:onSwing(105.5, false))
      assert.are.equal("oh", c:onSwing(105.7, false))
    end)

    it("cast with 1-4 Maelstrom does not touch swings due after the cast", function()
      local c = dual()                 -- mh 105.2
      c:onCastStart(103.0, "lightningBolt", 4, 1.0) -- ends 104.0
      assert.are.near(2.2, c:state(103.0).mh.next, 1e-9)
      c:onCastEnd(104.0, "lightningBolt", 4, true)
      assert.are.near(1.2, c:state(104.0).mh.next, 1e-9)
    end)

    it("interrupted 0-stack cast does not reset, only releases delayed swings", function()
      local c = dual()                 -- mh 105.2, oh 105.4
      c:onCastStart(104.0, "lightningBolt", 0, 2.5)
      c:onCastEnd(105.3, "lightningBolt", 0, false)
      local s = c:state(105.3)
      assert.are.equal(0, s.mh.next)
      assert.are.near(0.1, s.oh.next, 1e-9)
    end)

    it("instant (5 stacks) cast start is ignored", function()
      local c = dual()
      c:onCastStart(103.0, "lightningBolt", 5, 0)
      assert.are.near(2.2, c:state(103.0).mh.next, 1e-9)
      c:onCastEnd(103.0, "lightningBolt", 5, true)
      assert.are.near(2.2, c:state(103.0).mh.next, 1e-9)
    end)

    it("non-reset spell with 0 stacks only delays", function()
      local c = dual()
      c:onCastStart(104.0, "hex", 0, 1.5)
      c:onCastEnd(105.5, "hex", 0, true)
      assert.are.equal(0, c:state(105.5).mh.next)
    end)
  end)

  describe("instant calibration", function()
    it("three reset observations mark the spell as resetting", function()
      local c = twoHand()
      for _ = 1, 3 do instantThenSwing(c, "earthShock", "reset") end
      assert.is_true(c.saved.reset.earthShock)
      assert.is_true(c:state(0).resetByInstant.earthShock)
    end)

    it("three keep observations mark the spell as not resetting", function()
      local c = twoHand()
      for _ = 1, 3 do instantThenSwing(c, "stormstrike", "keep") end
      assert.is_false(c.saved.reset.stormstrike)
      assert.is_nil(c:state(0).resetByInstant.stormstrike)
    end)

    it("undecided after two votes", function()
      local c = twoHand()
      for _ = 1, 2 do instantThenSwing(c, "earthShock", "reset") end
      assert.is_nil(c.saved.reset.earthShock)
      assert.are.equal(2, c.saved.votes.earthShock.reset)
    end)

    it("a calibrated resetting instant resets the swing immediately", function()
      local c = twoHand()
      for _ = 1, 3 do instantThenSwing(c, "earthShock", "reset") end
      local due = c:state(0).mh.next
      local t = due - 1.0
      c:onInstant(t, "earthShock")
      assert.are.near(3.6, c:state(t).mh.next, 1e-9)
    end)

    it("ambiguous observation (old and reset moments too close) is not counted", function()
      local c = twoHand()              -- due 107.2
      c:onInstant(103.8, "earthShock") -- reset due 107.4, only 0.2 from old
      c:onSwing(107.2, false)
      assert.is_nil(c.saved.votes.earthShock)
    end)

    it("calibration survives into a new clock through saved", function()
      local saved = {}
      local c = twoHand(saved)
      for _ = 1, 3 do instantThenSwing(c, "earthShock", "reset") end
      local c2 = twoHand(saved)
      assert.is_true(c2:state(0).resetByInstant.earthShock)
    end)

    it("a cast between instant and swing cancels the observation", function()
      local c = twoHand()              -- due 107.2
      c:onInstant(105.9, "earthShock")
      c:onCastStart(106.0, "lightningBolt", 2, 1.0)
      c:onCastEnd(107.0, "lightningBolt", 2, true)
      c:onSwing(107.2, false)
      assert.is_nil(c.saved.votes.earthShock)
    end)
  end)

  describe("castWindow", function()
    it("any time is fine when not auto-attacking", function()
      local c = swing.new()
      c:onSpeed(100, 2.6, 2.6)
      local a, b = c:castWindow(100, 1.0, 0.15)
      assert.are.equal(0, a)
      assert.are.equal(swing.HORIZON, b)
    end)

    it("finds the first gap between swings long enough for cast + latency", function()
      local c = dual()                 -- mh due 105.2, oh due 105.4
      c:onSwing(105.2, false)          -- mh -> 107.8
      c:onSwing(105.4, false)          -- oh -> 108.0
      -- at 105.5: events 2.3, 2.5, 4.9, 5.1; gap 0..2.3 fits 1.0 + 0.15
      local a, b = c:castWindow(105.5, 1.0, 0.15)
      assert.are.near(0, a, 1e-9)
      assert.are.near(2.3 - 1.15, b, 1e-9)
    end)

    it("skips gaps that are too short", function()
      local c = dual()                 -- at 105.1: mh next 0.1, oh 0.3
      local a, b = c:castWindow(105.1, 1.0, 0.15)
      -- events: 0.1, 0.3, 2.7, 2.9, 5.3, 5.5 -> first fitting gap 0.3..2.7
      assert.are.near(0.3, a, 1e-9)
      assert.are.near(2.7 - 1.15, b, 1e-9)
    end)

    it("returns nil when no gap fits inside the horizon", function()
      local c = dual()
      assert.is_nil(c:castWindow(105.1, 3.0, 0.15))
    end)
  end)
end)
```

Примечание к хелперу `instantThenSwing`: `c:state(0).mh.next` равен абсолютному `due`, потому что `next = due - now`, а `now = 0`. Мгновенное заклинание ставится за 1,3 с до ожидаемого удара: так старый (`due`) и сброшенный (`t + 3.6`) моменты отличаются на 2,3 с, и наблюдение однозначно.

- [ ] **Step 2: Запустить тесты и убедиться, что они падают**

Run: `docker compose run --rm test busted spec/swing_spec.lua`
Expected: FAIL — `module 'swing' not found`.

- [ ] **Step 3: Реализовать модуль**

Create `src/swing.lua`:

```lua
local M = {}

M.HAND_TOLERANCE = 0.25
M.CALIBRATE_VOTES = 3
M.HORIZON = 6.0
M.EXTRA_WINDOW = 0.1
M.CAST_RESET = { lightningBolt = true, chainLightning = true }

local HANDS = { "mh", "oh" }

local Clock = {}
Clock.__index = Clock

function M.new(saved)
  saved = saved or {}
  saved.votes = saved.votes or {}
  saved.reset = saved.reset or {}
  return setmetatable({
    saved = saved,
    attacking = false,
    hands = {},
    cast = nil,
    extraLeft = 0,
    extraAt = -1,
    obs = nil,
    resyncs = 0,
  }, Clock)
end

function Clock:onSpeed(now, mhSpeed, ohSpeed)
  local speeds = { mh = mhSpeed, oh = ohSpeed }
  for _, h in ipairs(HANDS) do
    local sp = speeds[h]
    local st = self.hands[h]
    if not sp or sp <= 0 then
      self.hands[h] = nil
    elseif not st then
      self.hands[h] = { speed = sp, due = now + sp }
    else
      local left = st.due - now
      if left > 0 then st.due = now + left * sp / st.speed end
      st.speed = sp
    end
  end
end

function Clock:onAttack(now, on)
  self.attacking = on and true or false
  if not self.attacking then return end
  for _, h in ipairs(HANDS) do
    local st = self.hands[h]
    if st and st.due < now then st.due = now end
  end
end

function Clock:onExtraAttacks(now, count)
  self.extraLeft = self.extraLeft + (count or 1)
  self.extraAt = now
end

-- Returns "mh" if this swing settles a pending instant-spell observation.
function Clock:_calibrate(now)
  local o = self.obs
  if not o then return nil end
  local oh = self.hands.oh
  if oh and math.abs(now - oh.due) <= M.HAND_TOLERANCE then return nil end
  self.obs = nil
  local dOld, dReset = math.abs(now - o.oldDue), math.abs(now - o.resetDue)
  if math.min(dOld, dReset) > M.HAND_TOLERANCE then return nil end
  local v = self.saved.votes[o.key]
  if not v then
    v = { reset = 0, keep = 0 }
    self.saved.votes[o.key] = v
  end
  if dReset < dOld then v.reset = v.reset + 1 else v.keep = v.keep + 1 end
  if v.reset - v.keep >= M.CALIBRATE_VOTES then
    self.saved.reset[o.key] = true
  elseif v.keep - v.reset >= M.CALIBRATE_VOTES then
    self.saved.reset[o.key] = false
  end
  return "mh"
end

function Clock:onSwing(now, isExtra)
  if isExtra then return "extra" end
  if self.extraLeft > 0 then
    if now - self.extraAt <= M.EXTRA_WINDOW then
      self.extraLeft = self.extraLeft - 1
      return "extra"
    end
    self.extraLeft = 0
  end
  local best = self:_calibrate(now)
  if not best then
    local bestErr
    for _, h in ipairs(HANDS) do
      local st = self.hands[h]
      if st then
        local err = math.abs(now - st.due)
        if not bestErr or err < bestErr then best, bestErr = h, err end
      end
    end
    if not best then return nil end
    if bestErr > M.HAND_TOLERANCE then
      self.resyncs = self.resyncs + 1
      local early
      for _, h in ipairs(HANDS) do
        local st = self.hands[h]
        if st and (not early or st.due < self.hands[early].due) then early = h end
      end
      best = early
    end
  end
  local st = self.hands[best]
  if not st then return nil end
  st.due = now + st.speed
  return best
end

function Clock:onCastStart(now, key, mwStacks, castTime)
  if not castTime or castTime <= 0 then return end
  self.obs = nil
  self.cast = { key = key, start = now, finish = now + castTime, mw = mwStacks or 0 }
end

function Clock:onCastEnd(now, key, mwStacks, ok)
  local c = self.cast
  self.cast = nil
  if not c then return end
  local reset = ok and M.CAST_RESET[c.key] and (c.mw or 0) == 0
  for _, h in ipairs(HANDS) do
    local st = self.hands[h]
    if st then
      if reset then
        st.due = now + st.speed
      elseif st.due < now then
        st.due = now
      end
    end
  end
end

function Clock:onInstant(now, key)
  self.obs = nil
  local mh = self.hands.mh
  if not mh or not self.attacking then return end
  local decided = self.saved.reset[key]
  if decided == true then
    for _, h in ipairs(HANDS) do
      local st = self.hands[h]
      if st then st.due = now + st.speed end
    end
    return
  end
  if decided == false then return end
  local resetDue = now + mh.speed
  if math.abs(resetDue - mh.due) >= 2 * M.HAND_TOLERANCE then
    self.obs = { key = key, at = now, oldDue = mh.due, resetDue = resetDue }
  end
end

function Clock:state(now)
  local out = { attacking = self.attacking, resetByInstant = {} }
  for k, v in pairs(self.saved.reset) do
    if v then out.resetByInstant[k] = true end
  end
  local c = self.cast
  for _, h in ipairs(HANDS) do
    local st = self.hands[h]
    if st then
      local due = st.due
      if c and now < c.finish then
        if M.CAST_RESET[c.key] and c.mw == 0 then
          due = c.finish + st.speed
        elseif due < c.finish then
          due = c.finish
        end
      end
      out[h] = { next = math.max(0, due - now), speed = st.speed }
    end
  end
  return out
end

function Clock:castWindow(now, castTime, latency)
  if not self.attacking then return 0, M.HORIZON end
  local s = self:state(now)
  local need = castTime + (latency or 0)
  local events = {}
  for _, h in ipairs(HANDS) do
    local st = s[h]
    if st and st.speed > 0 then
      local t = st.next
      while t <= M.HORIZON do
        events[#events + 1] = t
        t = t + st.speed
      end
    end
  end
  table.sort(events)
  local prev = 0
  for _, t in ipairs(events) do
    if t - prev >= need then return prev, t - need end
    prev = t
  end
  if M.HORIZON - prev >= need then return prev, M.HORIZON - need end
  return nil
end

return M
```

- [ ] **Step 4: Запустить тесты и убедиться, что они проходят**

Run: `docker compose run --rm test busted spec/swing_spec.lua`
Expected: PASS, 0 failures.

Если падает тест `castWindow ... skips gaps that are too short` на последнем промежутке (`5.5 .. 6.0` < 1.15) — это ожидаемо не должно давать окна, проверь, что `HORIZON - prev >= need` сравнивается с `need`, а не с `castTime`.

- [ ] **Step 5: Commit**

```bash
git add src/swing.lua spec/swing_spec.lua
git commit -m "Часы ударов: определение руки, касты, калибровка мгновенных"
```

---

### Task 5: Счётчик врагов рядом (`src/enemies.lua`)

Клиент 3.3.5a не умеет перечислять врагов вокруг, поэтому считаем по боевому логу:
- `melee` — сколько разных существ ударили игрока с руки за последние 2,5 с;
- `nearby` — сколько разных врагов было в бою с игроком (урон в любую сторону) за 6 с.

Призванные игроком существа (тотемы, волки Feral Spirit) — «свои»: урон Magma Totem по мобам тоже добавляет их в `nearby`. Умершие удаляются сразу. `nearby` никогда не меньше `melee`.

**Files:**
- Create: `src/enemies.lua`
- Test: `spec/enemies_spec.lua`

**Interfaces:**
- Consumes: ничего.
- Produces: `enemies.new()`, `e:onEvent(now, subEvent, srcGUID, dstGUID, playerGUID)`, `e:counts(now) -> melee, nearby`, константы `MELEE_WINDOW`, `NEARBY_WINDOW`. `runtime` передаёт сюда поля `COMBAT_LOG_EVENT_UNFILTERED` 3.3.5a: `(timestamp, subEvent, srcGUID, srcName, srcFlags, dstGUID, ...)` → `onEvent(GetTime(), subEvent, srcGUID, dstGUID, UnitGUID("player"))`.

- [ ] **Step 1: Написать падающие тесты**

Create `spec/enemies_spec.lua`:

```lua
local enemies = require("enemies")

local ME = "0x01"

describe("enemies", function()
  it("starts empty", function()
    local e = enemies.new()
    local m, n = e:counts(100)
    assert.are.equal(0, m)
    assert.are.equal(0, n)
  end)

  it("counts distinct melee attackers of the player", function()
    local e = enemies.new()
    e:onEvent(100.0, "SWING_DAMAGE", "0xA", ME, ME)
    e:onEvent(100.5, "SWING_MISSED", "0xB", ME, ME)
    e:onEvent(101.0, "SWING_DAMAGE", "0xA", ME, ME)
    local m, n = e:counts(101.0)
    assert.are.equal(2, m)
    assert.are.equal(2, n)
  end)

  it("melee attackers expire after 2.5 s but stay nearby until 6 s", function()
    local e = enemies.new()
    e:onEvent(100.0, "SWING_DAMAGE", "0xA", ME, ME)
    local m, n = e:counts(102.6)
    assert.are.equal(0, m)
    assert.are.equal(1, n)
    m, n = e:counts(106.1)
    assert.are.equal(0, n)
  end)

  it("spell damage to the player counts as nearby, not melee", function()
    local e = enemies.new()
    e:onEvent(100, "SPELL_DAMAGE", "0xC", ME, ME)
    local m, n = e:counts(100)
    assert.are.equal(0, m)
    assert.are.equal(1, n)
  end)

  it("player's outgoing damage marks targets as nearby", function()
    local e = enemies.new()
    e:onEvent(100, "SPELL_DAMAGE", ME, "0xA", ME)
    e:onEvent(100, "SWING_DAMAGE", ME, "0xB", ME)
    e:onEvent(100, "SPELL_PERIODIC_DAMAGE", ME, "0xC", ME)
    local _, n = e:counts(100)
    assert.are.equal(3, n)
  end)

  it("damage done by a summoned totem counts as the player's", function()
    local e = enemies.new()
    e:onEvent(100, "SPELL_SUMMON", ME, "0xT", ME)
    e:onEvent(101, "SPELL_DAMAGE", "0xT", "0xA", ME)
    e:onEvent(101, "SPELL_DAMAGE", "0xT", "0xB", ME)
    local _, n = e:counts(101)
    assert.are.equal(2, n)
  end)

  it("ignores events not involving the player or own summons", function()
    local e = enemies.new()
    e:onEvent(100, "SPELL_DAMAGE", "0xX", "0xY", ME)
    e:onEvent(100, "SPELL_HEAL", ME, "0xA", ME)
    e:onEvent(100, "SPELL_AURA_APPLIED", "0xA", ME, ME)
    local m, n = e:counts(100)
    assert.are.equal(0, m)
    assert.are.equal(0, n)
  end)

  it("removes dead units immediately", function()
    local e = enemies.new()
    e:onEvent(100, "SWING_DAMAGE", "0xA", ME, ME)
    e:onEvent(100, "SWING_DAMAGE", "0xB", ME, ME)
    e:onEvent(100.5, "UNIT_DIED", nil, "0xA", ME)
    local m, n = e:counts(100.5)
    assert.are.equal(1, m)
    assert.are.equal(1, n)
  end)

  it("PARTY_KILL removes the killed unit", function()
    local e = enemies.new()
    e:onEvent(100, "SPELL_DAMAGE", ME, "0xA", ME)
    e:onEvent(100.2, "PARTY_KILL", ME, "0xA", ME)
    local _, n = e:counts(100.2)
    assert.are.equal(0, n)
  end)

  it("nearby is never below melee", function()
    local e = enemies.new()
    e:onEvent(100, "SWING_DAMAGE", "0xA", ME, ME)
    local m, n = e:counts(100)
    assert.is_true(n >= m)
  end)

  it("ignores nil subEvent safely", function()
    local e = enemies.new()
    e:onEvent(100, nil, nil, nil, ME)
    local m = e:counts(100)
    assert.are.equal(0, m)
  end)
end)
```

- [ ] **Step 2: Запустить тесты и убедиться, что они падают**

Run: `docker compose run --rm test busted spec/enemies_spec.lua`
Expected: FAIL — `module 'enemies' not found`.

- [ ] **Step 3: Реализовать модуль**

Create `src/enemies.lua`:

```lua
local M = {}

M.MELEE_WINDOW = 2.5
M.NEARBY_WINDOW = 6

local DAMAGE = {
  SWING_DAMAGE = true, SWING_MISSED = true, RANGE_DAMAGE = true, RANGE_MISSED = true,
  SPELL_DAMAGE = true, SPELL_MISSED = true, SPELL_PERIODIC_DAMAGE = true,
  SPELL_PERIODIC_MISSED = true, DAMAGE_SHIELD = true,
}
local MELEE = { SWING_DAMAGE = true, SWING_MISSED = true }
local DEATH = { UNIT_DIED = true, UNIT_DESTROYED = true, PARTY_KILL = true }

local E = {}
E.__index = E

function M.new()
  return setmetatable({ melee = {}, nearby = {}, mine = {} }, E)
end

function E:onEvent(now, subEvent, src, dst, player)
  if not subEvent then return end
  if subEvent == "SPELL_SUMMON" then
    if src and src == player and dst then self.mine[dst] = true end
    return
  end
  if DEATH[subEvent] then
    if dst then
      self.melee[dst] = nil
      self.nearby[dst] = nil
      self.mine[dst] = nil
    end
    return
  end
  if not DAMAGE[subEvent] then return end
  local fromMe = src ~= nil and (src == player or self.mine[src])
  local toMe = dst ~= nil and (dst == player or self.mine[dst])
  if fromMe and dst and not toMe then
    self.nearby[dst] = now
  elseif toMe and src and not fromMe then
    self.nearby[src] = now
    if MELEE[subEvent] and dst == player then self.melee[src] = now end
  end
end

function E:counts(now)
  local m, n = 0, 0
  for g, t in pairs(self.melee) do
    if now - t <= M.MELEE_WINDOW then m = m + 1 else self.melee[g] = nil end
  end
  for g, t in pairs(self.nearby) do
    if now - t <= M.NEARBY_WINDOW then n = n + 1 else self.nearby[g] = nil end
  end
  if n < m then n = m end
  return m, n
end

return M
```

- [ ] **Step 4: Запустить тесты и убедиться, что они проходят**

Run: `docker compose run --rm test busted spec/enemies_spec.lua`
Expected: PASS, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add src/enemies.lua spec/enemies_spec.lua
git commit -m "Счётчик врагов рядом по боевому логу"
```

---

### Task 6: Время жизни цели (`src/ttd.lua`)

Оценка «сколько ещё проживёт цель» по линейной регрессии процента здоровья за последние 10 с (метод наименьших квадратов). Пока данных мало — меньше 3 замеров или охват меньше 1,5 с — возвращает `nil`, и `value`/`damage` считают цель «живёт долго». Если здоровье выросло больше чем на 5% (лечение, эвейд), замеры этой цели сбрасываются. Цели, которых не видели 30 с, забываются.

**Files:**
- Create: `src/ttd.lua`
- Test: `spec/ttd_spec.lua`

**Interfaces:**
- Consumes: ничего.
- Produces: `ttd.new()`, `t:add(now, guid, hpPct)` (hpPct — доля 0..1), `t:estimate(now, guid) -> сек|nil`, `t:reset(guid)`; константы `WINDOW`, `MIN_SAMPLES`, `MIN_SPAN`, `HEAL_RESET`, `FORGET`. `snapshot` кладёт результат в `S.target.ttd`; `runtime` вызывает `t:reset(oldGuid)` на `PLAYER_TARGET_CHANGED` не обязательно — достаточно того, что оценка ведётся по GUID.

- [ ] **Step 1: Написать падающие тесты**

Create `spec/ttd_spec.lua`:

```lua
local ttd = require("ttd")

local function feed(t, guid, start, samples)
  for i, hp in ipairs(samples) do
    t:add(start + (i - 1), guid, hp)
  end
end

describe("ttd", function()
  it("unknown guid gives nil", function()
    assert.is_nil(ttd.new():estimate(100, "0xA"))
  end)

  it("needs at least 3 samples", function()
    local t = ttd.new()
    feed(t, "0xA", 100, { 1.0, 0.9 })
    assert.is_nil(t:estimate(101, "0xA"))
  end)

  it("needs at least 1.5 s of span", function()
    local t = ttd.new()
    t:add(100.0, "0xA", 1.0)
    t:add(100.5, "0xA", 0.95)
    t:add(101.0, "0xA", 0.9)
    assert.is_nil(t:estimate(101.0, "0xA"))
  end)

  it("linear decline of 10%/s at 80% gives 8 s", function()
    local t = ttd.new()
    feed(t, "0xA", 100, { 1.0, 0.9, 0.8 })
    assert.are.near(8, t:estimate(102, "0xA"), 1e-6)
  end)

  it("accounts for time passed since the last sample", function()
    local t = ttd.new()
    feed(t, "0xA", 100, { 1.0, 0.9, 0.8 })
    assert.are.near(7, t:estimate(103, "0xA"), 1e-6)
  end)

  it("never returns negative", function()
    local t = ttd.new()
    feed(t, "0xA", 100, { 0.3, 0.2, 0.1 })
    assert.are.equal(0, t:estimate(150, "0xA"))
  end)

  it("flat or rising health gives nil", function()
    local t = ttd.new()
    feed(t, "0xA", 100, { 0.5, 0.5, 0.5 })
    assert.is_nil(t:estimate(102, "0xA"))
    local r = ttd.new()
    feed(r, "0xB", 100, { 0.50, 0.52, 0.54 })
    assert.is_nil(r:estimate(102, "0xB"))
  end)

  it("heal-up above 5% resets the samples", function()
    local t = ttd.new()
    feed(t, "0xA", 100, { 1.0, 0.9, 0.8 })
    t:add(103, "0xA", 1.0)
    assert.is_nil(t:estimate(103, "0xA"))
  end)

  it("drops samples older than the window", function()
    local t = ttd.new()
    -- fast early drop, then slow: only the last 10 s matter
    t:add(100, "0xA", 1.0)
    t:add(101, "0xA", 0.5)
    for i = 0, 4 do t:add(112 + i, "0xA", 0.5 - 0.01 * i) end
    -- slope -0.01/s over 112..116, hp 0.46 -> 46 s
    assert.are.near(46, t:estimate(116, "0xA"), 1e-6)
  end)

  it("keeps separate estimates per guid", function()
    local t = ttd.new()
    feed(t, "0xA", 100, { 1.0, 0.9, 0.8 })
    feed(t, "0xB", 100, { 1.0, 0.8, 0.6 })
    assert.are.near(8, t:estimate(102, "0xA"), 1e-6)
    assert.are.near(3, t:estimate(102, "0xB"), 1e-6)
  end)

  it("reset forgets one guid or all", function()
    local t = ttd.new()
    feed(t, "0xA", 100, { 1.0, 0.9, 0.8 })
    feed(t, "0xB", 100, { 1.0, 0.9, 0.8 })
    t:reset("0xA")
    assert.is_nil(t:estimate(102, "0xA"))
    assert.is_not_nil(t:estimate(102, "0xB"))
    t:reset()
    assert.is_nil(t:estimate(102, "0xB"))
  end)

  it("forgets guids not seen for 30 s", function()
    local t = ttd.new()
    feed(t, "0xA", 100, { 1.0, 0.9, 0.8 })
    t:add(140, "0xB", 1.0)
    assert.is_nil(t.units["0xA"])
  end)

  it("ignores nil guid or hp", function()
    local t = ttd.new()
    t:add(100, nil, 0.5)
    t:add(100, "0xA", nil)
    assert.is_nil(t:estimate(100, "0xA"))
  end)
end)
```

- [ ] **Step 2: Запустить тесты и убедиться, что они падают**

Run: `docker compose run --rm test busted spec/ttd_spec.lua`
Expected: FAIL — `module 'ttd' not found`.

- [ ] **Step 3: Реализовать модуль**

Create `src/ttd.lua`:

```lua
local M = {}

M.WINDOW = 10
M.MIN_SAMPLES = 3
M.MIN_SPAN = 1.5
M.HEAL_RESET = 0.05
M.FORGET = 30

local T = {}
T.__index = T

function M.new()
  return setmetatable({ units = {} }, T)
end

function T:reset(guid)
  if guid then self.units[guid] = nil else self.units = {} end
end

function T:add(now, guid, hpPct)
  if not guid or not hpPct then return end
  for g, u in pairs(self.units) do
    if now - u.seen > M.FORGET then self.units[g] = nil end
  end
  local u = self.units[guid]
  if not u then
    u = { samples = {}, seen = now }
    self.units[guid] = u
  end
  u.seen = now
  local s = u.samples
  local last = s[#s]
  if last and hpPct > last.hp + M.HEAL_RESET then
    s = {}
    u.samples = s
  end
  s[#s + 1] = { t = now, hp = hpPct }
  while #s > 0 and now - s[1].t > M.WINDOW do table.remove(s, 1) end
end

function T:estimate(now, guid)
  local u = guid and self.units[guid]
  if not u then return nil end
  local s = u.samples
  local n = #s
  if n < M.MIN_SAMPLES or s[n].t - s[1].t < M.MIN_SPAN then return nil end
  local t0 = s[1].t
  local st, sh, stt, sth = 0, 0, 0, 0
  for i = 1, n do
    local t = s[i].t - t0
    st = st + t
    sh = sh + s[i].hp
    stt = stt + t * t
    sth = sth + t * s[i].hp
  end
  local den = n * stt - st * st
  if den <= 0 then return nil end
  local slope = (n * sth - st * sh) / den
  if slope >= 0 then return nil end
  local left = s[n].hp / -slope - (now - s[n].t)
  if left < 0 then left = 0 end
  return left
end

return M
```

- [ ] **Step 4: Запустить тесты и убедиться, что они проходят**

Run: `docker compose run --rm test busted spec/ttd_spec.lua`
Expected: PASS, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add src/ttd.lua spec/ttd_spec.lua
git commit -m "Оценка времени жизни цели"
```
