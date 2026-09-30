# Часть 3. Урон и модель перехода (задачи 7–8)

## Contract additions

Эта часть опирается на контракт из `2026-09-30-enh-rotation.md` и добавляет к нему:

1. **Ключи талантов**, которые читает `damage`/`model` (их должен выдавать `talents.KEYS` из части 2; отсутствующий ключ = ранг 0):
   `concussion` (0–5), `callOfFlame` (0–3), `elementalFury` (0–5), `reverberation` (0–5), `improvedFireNova` (0–2), `improvedShields` (0–3), `elementalWeapons` (0–3), `staticShock` (0–3), `maelstromWeapon` (0–5).
   Таланты `weaponMastery`, `dualWieldSpec`, `mentalQuickness`, `flurry` **не** применяются повторно: их эффект уже внутри `UnitDamage`, `GetSpellBonusDamage`, `GetCombatRatingBonus` и `S.player.meleeHaste`, которые читает `snapshot`.
2. **Поля состояния `S`:**
   - `S.weapons.mh.min/max` и `S.weapons.oh.min/max` — **ровно значения `UnitDamage("player")`**: уже включают силу атаки, штраф левой руки и процентные модификаторы.
   - `S.weapons.mh.twoHand = true|nil` — двуручное оружие (нормализованная скорость 3.3 вместо 2.4).
   - `S.target.armor` — необязательное переопределение брони цели.
   - `S.target.dead = true|nil` — цель умерла (ставит `model`).
   - `S.pets = { wolves = 0 }` — остаток Feral Spirit.
   - `S.buffs.mw.stacks` может быть дробным (ожидаемое значение). Для времени каста берётся `math.floor`.
3. **Строки `spells_data`**, которые нужны `damage` (генерирует часть 2):
   - `lightningBolt`, `chainLightning`, `earthShock`, `frostShock`, `fireNova` — `{min, max, coef}` прямого урона. Для `fireNova` — строка урона от тотема (ID 8349…61654), а не заклинания-триггера.
   - `flameShock` — `{min, max, coef, tick, tickCoef, ticks, period}`. Если `period == nil`, считается 3.
   - `magmaTotem` — строка импульса (ID 8187…58735): `{min, max, coef}`.
   - `searingTotem` — строка выстрела «Attack» (ID 3606…58702): `{min, max, coef}`.
   - `lightningShield` — строка удара шара (ID 26364…49279): `{min, max, coef}`.

   Здесь `min = basePoints + 1`, `max = basePoints + dieSides`.
4. **Дополнительные функции `damage`:**
   ```lua
   damage.row(S, key) -> row|nil
   damage.spellHit(S) -> 0..1
   damage.spellCritFactor(S) -> >=1
   damage.meleeTable(S, white) -> { miss, dodge, glance, crit, factor, landed }
   damage.armorMult(S) -> 0..1
   damage.targetArmor(level) -> n
   damage.white(S, hand) -> n
   damage.normalized(S, hand) -> n
   damage.wf(S) -> dmgPerMhSwing, procsPerMhSwing
   damage.ftHit(S, hand) -> n
   damage.staticHit(S) -> n
   damage.mwPerHit(S, hand) -> stacks
   damage.periodic(S, source) -> dps  -- source: "flameShock"|"magmaTotem"|"searingTotem"|"fireElemental"|"feralSpirit"
   ```
   `damage.periodic` нужна части 4 (`value.terminal`) для остаточной ценности DoT, тотемов и питомцев.
5. **Дополнительные функции `model`:**
   ```lua
   model.HORIZON = 6.0
   model.copy(t)
   model.advance(n, dt, cast) -> dmg   -- на месте, без копии; cast = { ends = сек, reset = bool } | nil
   model.cooldownFor(S, key)
   model.gcdFor(S, key)
   model.lsMaxCharges(S)
   model.addMw(n, x)
   model.resetSwings(n)
   ```
6. **Разделение урона.** `damage.action` возвращает **только мгновенную часть**. Тики Flame Shock, импульсы тотемов, Fire Elemental и волки начисляются в `model.advance` непрерывно, как `dps × время`, в пределах остатка и `ttd`.
7. **`spells.CATALOG[i]` должен содержать поля** `key`, `gcd` (1.5 | 1.0 | 0), `cd`, `sharedCd`, `castBase`. У шоков `sharedCd = "shock"`, у `lightningBolt` `castBase = 2.5`, у `chainLightning` `castBase = 2.0`, у тотемов `gcd = 1.0`.

Приближённые константы помечены `-- approx` в коде и проверяются по записям из реальных боёв (`recorder`, часть 5):
- `FT_PER_SPEED` — урон Flametongue на единицу скорости оружия;
- `FE_DPS` — урон Fire Elemental в секунду;
- волки — формула урона Feral Spirit;
- `SEARING_PERIOD` — интервал выстрелов Searing Totem.

---

### Task 7: Формулы урона (`src/damage.lua`)

**Files:**
- Create: `src/damage.lua`
- Test: `spec/damage_spec.lua`

**Interfaces:**
- Consumes: `spells.rank(key, id) -> row` (часть 2); форма `S` из контракта и «Contract additions» выше.
- Produces: `damage.action`, `damage.dot`, `damage.auto`, `damage.mwPerSwing`, `damage.targets` (контракт) + функции из п. 4 «Contract additions».

Проверочные расчёты для тестов. Фикстура 80 уровня против цели 83 уровня:
- **Промах заклинания:** 17% − 10% попадания = 7%, то есть попадание 0,93.
- **Крит заклинания:** 20% с множителем 1,5 → фактор 1,1.
- **Lightning Bolt ранга 14:** (715 + 815)/2 + 0,714 · 1200 = 1621,8 → 1621,8 · 0,93 · 1,1 = **1659,1014**.
- **Белый удар, два оружия:**
  - промах 27% − 8% = 19%;
  - уклонение 6,5%;
  - скользящий удар 24% с потерей 25% урона;
  - крит 30% − 4,8% = 25,2%.
  - Фактор = 0,253 + 0,24 · 0,75 + 0,252 · 2 = **0,937**.
- **Жёлтый удар:** промах 0, уклонение 6,5%, крит 25,2% → фактор = 0,683 + 0,504 = **1,187**.
- **Броня 10643 против атакующего 80 уровня:** `k = 400 + 85 · (80 + 4,5 · 21) = 15232,5`.

Уровень 20 против цели 20 уровня:
- **Lightning Bolt ранга 4** (83–95, коэффициент 0,714), SP 50, попадание 0,96, крит 5% → 124,7 · 0,96 · 1,025 = **122,7048**.
- **Двуручник** 40–60: фактор 0,945, броня 600, `k = 2100` → **36,75**.

- [ ] **Step 1: Write the failing test**

`spec/damage_spec.lua`:

```lua
local spells = require("spells")
local damage = require("damage")

local ROWS = {
  lightningBolt = { id = 49238, level = 79, min = 715, max = 815, coef = 0.714 },
  earthShock = { id = 49231, level = 79, min = 849, max = 895, coef = 0.386 },
  chainLightning = { id = 49271, level = 80, min = 973, max = 1111, coef = 0.571 },
  fireNova = { id = 61654, level = 80, min = 893, max = 997, coef = 0.214 },
  flameShock = { id = 49233, level = 80, min = 500, max = 500, coef = 0.214, tick = 139, tickCoef = 0.1, ticks = 6, period = 3 },
  magmaTotem = { id = 58735, level = 78, min = 371, max = 371, coef = 0.1 },
  lightningShield = { id = 49279, level = 80, min = 380, max = 380, coef = 0.267 },
}
local ROWS20 = {
  lightningBolt = { id = 915, level = 20, min = 83, max = 95, coef = 0.714 },
}

local function s80(o)
  local S = {
    now = 100, gcdRemains = 0, castRemains = 0, gcd = 1.5, latency = 0.15, mode = "raid",
    player = { level = 80, mana = 8000, manaMax = 10000, baseMana = 4396, hpPct = 1, ap = 4000,
               spNature = 1200, spFire = 1200, meleeCrit = 0.30, spellCrit = 0.20, meleeHit = 0.08,
               spellHit = 0.10, spellHaste = 1.0, meleeHaste = 1.0, moving = false, inCombat = true },
    weapons = { mh = { speed = 2.6, min = 600, max = 900, enchant = "wf" },
                oh = { speed = 2.6, min = 300, max = 450, enchant = "ft" } },
    talents = {},
    spells = {
      lightningBolt = { id = 49238, rank = 14, cd = 0, cost = 300, cast = 2.5 },
      earthShock = { id = 49231, rank = 10, cd = 0, cost = 800, cast = 0 },
      chainLightning = { id = 49271, rank = 8, cd = 0, cost = 1100, cast = 2 },
      fireNova = { id = 61657, rank = 9, cd = 0, cost = 900, cast = 0 },
      flameShock = { id = 49233, rank = 9, cd = 0, cost = 700, cast = 0 },
      magmaTotem = { id = 58734, rank = 7, cd = 0, cost = 1000, cast = 0 },
      lightningShield = { id = 49281, rank = 11, cd = 0, cost = 0, cast = 0 },
    },
    buffs = { mw = { stacks = 0, remains = 0 }, ls = { charges = 0, remains = 0 },
              flurry = { charges = 0, remains = 0 }, rage = 0, lust = 0, em = 0 },
    target = { exists = true, enemy = true, level = 83, hp = 1e6, hpMax = 1e6, hpPct = 1, ttd = 60,
               range = "melee", fs = 0, ss = { charges = 0, remains = 0 } },
    totems = { fire = { remains = 0 }, water = { remains = 0 } },
    swing = { attacking = true, mh = { next = 1, speed = 2.6 }, oh = { next = 1, speed = 2.6 }, resetByInstant = {} },
    enemies = { melee = 1, nearby = 1 },
    inflight = {}, pets = { wolves = 0 },
  }
  for k, v in pairs(o or {}) do S[k] = v end
  return S
end

local function s20()
  local S = s80()
  S.player.level, S.player.ap, S.player.spNature, S.player.spFire = 20, 300, 50, 50
  S.player.meleeCrit, S.player.spellCrit, S.player.meleeHit, S.player.spellHit = 0.05, 0.05, 0, 0
  S.weapons = { mh = { speed = 3.4, min = 40, max = 60, enchant = "rb", twoHand = true } }
  S.target.level = 20
  S.spells = { lightningBolt = { id = 915, rank = 4, cd = 0, cost = 60, cast = 2.5 } }
  return S
end

local AM80 = 1 - 10643 / (10643 + 15232.5)
local AP14 = 4000 / 14

describe("damage", function()
  local orig
  before_each(function()
    orig = spells.rank
    spells.rank = function(key, id)
      if id == 915 then return ROWS20.lightningBolt end
      return ROWS[key]
    end
  end)
  after_each(function() spells.rank = orig end)

  describe("spell hit and crit", function()
    it("uses 17% base miss against +3 level and subtracts hit", function()
      assert.are.near(0.93, damage.spellHit(s80()), 1e-9)
    end)
    it("uses 4% base miss against same level", function()
      assert.are.near(0.96, damage.spellHit(s20()), 1e-9)
    end)
    it("treats unknown target level (-1) as +3", function()
      local S = s80(); S.target.level = -1
      assert.are.near(0.93, damage.spellHit(S), 1e-9)
    end)
    it("crit factor 1.5 base, +0.1 per Elemental Fury rank", function()
      local S = s80()
      assert.are.near(1.1, damage.spellCritFactor(S), 1e-9)
      S.talents.elementalFury = 5
      assert.are.near(1.2, damage.spellCritFactor(S), 1e-9)
    end)
  end)

  describe("direct spells", function()
    it("Lightning Bolt at 80", function()
      assert.are.near(1659.1014, damage.action(s80(), "lightningBolt"), 1e-6)
    end)
    it("Lightning Bolt at 20", function()
      assert.are.near(122.7048, damage.action(s20(), "lightningBolt"), 1e-6)
    end)
    it("Concussion adds 1% per rank", function()
      local S = s80(); S.talents.concussion = 5
      assert.are.near(1659.1014 * 1.05, damage.action(S, "lightningBolt"), 1e-6)
    end)
    it("Stormstrike debuff adds 20% to nature spells", function()
      local S = s80(); S.target.ss = { charges = 2, remains = 10 }
      assert.are.near(1659.1014 * 1.2, damage.action(S, "lightningBolt"), 1e-6)
      assert.are.near((872 + 0.386 * 1200) * 0.93 * 1.1 * 1.2, damage.action(S, "earthShock"), 1e-6)
    end)
    it("Stormstrike debuff does not affect fire", function()
      local S = s80(); S.target.ss = { charges = 2, remains = 10 }
      assert.are.near((500 + 0.214 * 1200) * 0.93 * 1.1, damage.action(S, "flameShock"), 1e-6)
    end)
    it("Chain Lightning hits up to 3 targets with 30% falloff", function()
      local S = s80(); S.enemies.nearby = 5
      local single = (1042 + 0.571 * 1200) * 0.93 * 1.1
      assert.are.equal(3, damage.targets(S, "chainLightning"))
      assert.are.near(single * 2.19, damage.action(S, "chainLightning"), 1e-6)
    end)
    it("Fire Nova hits every nearby enemy, Improved Fire Nova +10%/rank", function()
      local S = s80(); S.enemies.nearby = 4; S.talents.improvedFireNova = 2
      local per = (945 + 0.214 * 1200) * 0.93 * 1.1 * 1.2
      assert.are.equal(4, damage.targets(S, "fireNova"))
      assert.are.near(per * 4, damage.action(S, "fireNova"), 1e-6)
    end)
    it("totems, shield, cooldowns have no immediate damage", function()
      local S = s80()
      for _, k in ipairs({ "magmaTotem", "searingTotem", "fireElemental", "feralSpirit",
                           "lightningShield", "callOfElements", "shamanisticRage" }) do
        assert.are.equal(0, damage.action(S, k))
      end
    end)
    it("unknown spell returns 0", function()
      local S = s80(); S.spells.lightningBolt = nil
      assert.are.equal(0, damage.action(S, "lightningBolt"))
    end)
  end)

  describe("flame shock dot", function()
    it("returns per tick, ticks, period", function()
      local per, ticks, period = damage.dot(s80(), "flameShock")
      assert.are.near((139 + 0.1 * 1200) * 1.1, per, 1e-6)
      assert.are.equal(6, ticks)
      assert.are.equal(3, period)
    end)
    it("periodic flameShock = perTick / period", function()
      local S = s80()
      local per = damage.dot(S, "flameShock")
      assert.are.near(per / 3, damage.periodic(S, "flameShock"), 1e-9)
    end)
    it("magma pulses every 2 s on every nearby enemy", function()
      local S = s80(); S.enemies.nearby = 3
      assert.are.near((371 + 0.1 * 1200) * 0.93 * 1.1 * 3 / 2, damage.periodic(S, "magmaTotem"), 1e-6)
    end)
  end)

  describe("armor", function()
    it("boss armor for level 83 and unknown", function()
      assert.are.equal(10643, damage.targetArmor(83))
      assert.are.equal(10643, damage.targetArmor(-1))
      assert.are.equal(10643, damage.targetArmor(nil))
    end)
    it("interpolates by level", function()
      assert.are.equal(600, damage.targetArmor(20))
      assert.are.equal(1100, damage.targetArmor(30))
    end)
    it("mitigation formula for level 80 attacker", function()
      assert.are.near(AM80, damage.armorMult(s80()), 1e-12)
    end)
    it("explicit target.armor overrides", function()
      local S = s80(); S.target.armor = 0
      assert.are.equal(1, damage.armorMult(S))
    end)
  end)

  describe("melee", function()
    it("white table with dual wield vs +3", function()
      local t = damage.meleeTable(s80(), true)
      assert.are.near(0.19, t.miss, 1e-9)
      assert.are.near(0.065, t.dodge, 1e-9)
      assert.are.near(0.24, t.glance, 1e-9)
      assert.are.near(0.252, t.crit, 1e-9)
      assert.are.near(0.937, t.factor, 1e-9)
      assert.are.near(0.745, t.landed, 1e-9)
    end)
    it("yellow table has no glancing and no dual wield penalty", function()
      local t = damage.meleeTable(s80(), false)
      assert.are.near(0, t.miss, 1e-9)
      assert.are.near(1.187, t.factor, 1e-9)
      assert.are.near(0.935, t.landed, 1e-9)
    end)
    it("white main hand at 80", function()
      assert.are.near(750 * 0.937 * AM80, damage.white(s80(), "mh"), 1e-6)
    end)
    it("level 20 two-hander, rockbiter adds nothing", function()
      assert.are.near(36.75, damage.white(s20(), "mh"), 1e-9)
      assert.are.near(36.75, damage.auto(s20(), "mh"), 1e-9)
    end)
    it("normalized weapon damage uses 2.4 (3.3 for two-hand)", function()
      local S = s80()
      assert.are.near(750 - AP14 * 2.6 + AP14 * 2.4, damage.normalized(S, "mh"), 1e-9)
      assert.are.near(375 + 0.5 * (AP14 * 2.4 - AP14 * 2.6), damage.normalized(S, "oh"), 1e-9)
      local L = s20()
      assert.are.near(50 - 300 / 14 * 3.4 + 300 / 14 * 3.3, damage.normalized(L, "mh"), 1e-9)
    end)
    it("windfury: 20% with 3 s ICD, 2 attacks with AP bonus", function()
      local S = s80()
      local dmg, procs = damage.wf(S)
      assert.are.near(0.2 / 1.2, procs, 1e-9)
      assert.are.near((0.2 / 1.2) * 2 * (750 + 1250 / 14 * 2.6) * 1.187 * AM80, dmg, 1e-6)
    end)
    it("windfury: Elemental Weapons 3/3 adds 40% to AP bonus", function()
      local S = s80(); S.talents.elementalWeapons = 3
      local dmg = damage.wf(S)
      assert.are.near((0.2 / 1.2) * 2 * (750 + 1250 * 1.4 / 14 * 2.6) * 1.187 * AM80, dmg, 1e-6)
    end)
    it("no windfury without the enchant", function()
      local S = s80(); S.weapons.mh.enchant = "ft"
      local dmg, procs = damage.wf(S)
      assert.are.equal(0, dmg); assert.are.equal(0, procs)
    end)
    it("flametongue hit on off hand", function()
      assert.are.near((52 * 2.6 + 0.1 * 1200) * 0.93 * 1.1, damage.ftHit(s80(), "oh"), 1e-6)
      assert.are.equal(0, damage.ftHit(s80(), "mh"))
    end)
    it("static shock needs shield charges", function()
      local S = s80(); S.talents.staticShock = 3
      assert.are.equal(0, damage.staticHit(S))
      S.buffs.ls = { charges = 3, remains = 600 }
      assert.are.near(0.06 * (380 + 0.267 * 1200) * 0.93 * 1.1, damage.staticHit(S), 1e-6)
    end)
    it("auto off hand = white + flametongue per landed hit", function()
      local S = s80()
      local expected = damage.white(S, "oh") + damage.ftHit(S, "oh") * 0.745
      assert.are.near(expected, damage.auto(S, "oh"), 1e-6)
    end)
    it("auto main hand includes windfury", function()
      local S = s80()
      local wf = damage.wf(S)
      assert.are.near(damage.white(S, "mh") + wf, damage.auto(S, "mh"), 1e-6)
    end)
  end)

  describe("weapon strikes", function()
    it("Stormstrike = both weapons normalized, yellow, armor", function()
      local S = s80(); S.weapons.oh.enchant = nil
      S.spells.stormstrike = { id = 17364, rank = 1, cd = 0, cost = 400, cast = 0 }
      local w = (750 - AP14 * 2.6 + AP14 * 2.4) + (375 + 0.5 * (AP14 * 2.4 - AP14 * 2.6))
      assert.are.near(w * 1.187 * AM80, damage.action(S, "stormstrike"), 1e-6)
    end)
    it("Lava Lash = off hand normalized, +25% with flametongue, no armor, plus FT proc", function()
      local S = s80()
      S.spells.lavaLash = { id = 60103, rank = 1, cd = 0, cost = 200, cast = 0 }
      local oh = 375 + 0.5 * (AP14 * 2.4 - AP14 * 2.6)
      local expected = oh * 1.25 * 1.187 + damage.ftHit(S, "oh") * 0.935
      assert.are.near(expected, damage.action(S, "lavaLash"), 1e-6)
    end)
    it("Lava Lash without off hand = 0", function()
      local S = s80(); S.weapons.oh = nil
      S.spells.lavaLash = { id = 60103, rank = 1, cd = 0, cost = 200, cast = 0 }
      assert.are.equal(0, damage.action(S, "lavaLash"))
    end)
  end)

  describe("maelstrom", function()
    it("no talent, no stacks", function()
      assert.are.equal(0, damage.mwPerSwing(s80(), "oh"))
    end)
    it("PPM 2 per rank, scaled by landed white hits", function()
      local S = s80(); S.talents.maelstromWeapon = 5
      assert.are.near(10 * 2.6 / 60 * 0.745, damage.mwPerSwing(S, "oh"), 1e-9)
    end)
    it("main hand also counts windfury extra attacks", function()
      local S = s80(); S.talents.maelstromWeapon = 5
      local c = 10 * 2.6 / 60
      local _, procs = damage.wf(S)
      assert.are.near(c * 0.745 + procs * 2 * c * 0.935, damage.mwPerSwing(S, "mh"), 1e-9)
    end)
    it("per special hit uses yellow landed", function()
      local S = s80(); S.talents.maelstromWeapon = 5
      assert.are.near(10 * 2.6 / 60 * 0.935, damage.mwPerHit(S, "oh"), 1e-9)
    end)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose run --rm test busted spec/damage_spec.lua`
Expected: FAIL — `module 'damage' not found`.

- [ ] **Step 3: Write minimal implementation**

`src/damage.lua`:

```lua
local spells = require("spells")

local M = {}

M.BOSS_ARMOR = 10643
M.ARMOR_POINTS = { { 1, 20 }, { 20, 600 }, { 40, 1600 }, { 60, 3200 }, { 70, 6000 }, { 80, 9700 }, { 83, 10643 } }
-- Windfury Weapon rank (by learn level) -> attack power bonus
M.WF_AP = { { 80, 1250 }, { 76, 1090 }, { 71, 835 }, { 68, 445 }, { 60, 333 }, { 50, 249 }, { 40, 119 }, { 30, 46 } }
-- approx: Flametongue fire damage per 1.0 weapon speed, by rank learn level
M.FT_PER_SPEED = { { 80, 52 }, { 76, 45 }, { 71, 40 }, { 64, 35.5 }, { 56, 24 }, { 46, 17 }, { 36, 11 }, { 26, 7 }, { 18, 4.5 }, { 10, 2.5 } }
M.EW_WF = { 0.13, 0.27, 0.40 }
M.EW_FT = { 0.10, 0.20, 0.30 }
M.WF_CHANCE, M.WF_ICD = 0.2, 3
M.CL_FALLOFF = { 1, 0.7, 0.49 }
M.MAGMA_PERIOD = 2
M.SEARING_PERIOD = 2.2 -- approx
M.FE_BASE_DPS, M.FE_SP = 200, 0.5 -- approx
M.WOLF_BASE, M.WOLF_AP, M.WOLF_SPEED = 120, 0.31, 1.5 -- approx

local SCHOOL = {
  earthShock = "nature", lightningBolt = "nature", chainLightning = "nature", lightningShield = "nature",
  flameShock = "fire", fireNova = "fire", magmaTotem = "fire", searingTotem = "fire", frostShock = "frost",
}
local CONCUSSION = { earthShock = true, flameShock = true, frostShock = true, lightningBolt = true, chainLightning = true }
local CALL_OF_FLAME = { searingTotem = true, magmaTotem = true, fireNova = true, fireElemental = true }
local NATURE_SS = { earthShock = true, lightningBolt = true, chainLightning = true, lightningShield = true }
local DIRECT = { earthShock = true, frostShock = true, lightningBolt = true, flameShock = true }

local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
local function talent(S, k) return (S.talents and S.talents[k]) or 0 end

local function lvlDiff(S)
  local tl = S.target and S.target.level
  if not tl or tl < 0 then tl = S.player.level + 3 end
  return tl - S.player.level
end

local function byLevel(tbl, level)
  for _, p in ipairs(tbl) do
    if level >= p[1] then return p[2] end
  end
  return 0
end

function M.row(S, key)
  local sp = S.spells and S.spells[key]
  if not sp then return nil end
  return spells.rank(key, sp.id)
end

function M.spellHit(S)
  local d = lvlDiff(S)
  local miss
  if d >= 3 then miss = 0.17
  elseif d <= 0 then miss = math.max(0.01, 0.04 + 0.01 * d)
  else miss = 0.04 + 0.01 * d end
  return 1 - math.max(0, miss - (S.player.spellHit or 0))
end

function M.spellCritFactor(S)
  local mult = 1.5 + 0.1 * talent(S, "elementalFury")
  return 1 + clamp(S.player.spellCrit or 0, 0, 1) * (mult - 1)
end

function M.spellMult(S, key)
  local m = 1
  if CONCUSSION[key] then m = m * (1 + 0.01 * talent(S, "concussion")) end
  if CALL_OF_FLAME[key] then m = m * (1 + 0.05 * talent(S, "callOfFlame")) end
  if key == "fireNova" then m = m * (1 + 0.1 * talent(S, "improvedFireNova")) end
  if key == "lightningShield" then m = m * (1 + 0.05 * talent(S, "improvedShields")) end
  local ss = S.target and S.target.ss
  if NATURE_SS[key] and ss and (ss.charges or 0) > 0 then m = m * 1.2 end
  return m
end

local function spellPower(S, school)
  if school == "nature" then return S.player.spNature or 0 end
  return S.player.spFire or 0
end

local function spellDamage(S, key, row)
  if not row then return 0 end
  local base = (row.min + row.max) / 2 + (row.coef or 0) * spellPower(S, SCHOOL[key])
  return base * M.spellMult(S, key) * M.spellHit(S) * M.spellCritFactor(S)
end

function M.targetArmor(level)
  if not level or level < 0 or level >= 83 then return M.BOSS_ARMOR end
  local pts = M.ARMOR_POINTS
  if level <= pts[1][1] then return pts[1][2] end
  for i = 2, #pts do
    local a, b = pts[i - 1], pts[i]
    if level <= b[1] then
      return a[2] + (b[2] - a[2]) * (level - a[1]) / (b[1] - a[1])
    end
  end
  return M.BOSS_ARMOR
end

function M.armorMult(S)
  local armor = S.target.armor or M.targetArmor(S.target.level)
  local L = S.player.level
  local k
  if L >= 60 then k = 400 + 85 * (L + 4.5 * (L - 59)) else k = 400 + 85 * L end
  return 1 - armor / (armor + k)
end

local GLANCE = { [0] = { 0.10, 0.05 }, { 0.15, 0.05 }, { 0.20, 0.15 }, { 0.24, 0.25 } }

function M.meleeTable(S, white)
  local d = lvlDiff(S)
  local dp = math.max(d, 0)
  local miss = d >= 3 and 0.08 or (0.05 + 0.005 * dp)
  if white and S.weapons.oh then miss = miss + 0.19 end
  miss = math.max(0, miss - (S.player.meleeHit or 0))
  local dodge = 0.05 + 0.005 * dp
  local glance, glanceRed = 0, 0
  if white then
    local g = GLANCE[math.min(dp, 3)]
    glance, glanceRed = g[1], g[2]
  end
  local crit = math.max(0, (S.player.meleeCrit or 0) - (d >= 3 and 0.048 or 0.002 * dp))
  crit = math.min(crit, math.max(0, 1 - miss - dodge - glance))
  local hit = 1 - miss - dodge - glance - crit
  return { miss = miss, dodge = dodge, glance = glance, crit = crit,
           factor = hit + glance * (1 - glanceRed) + crit * 2, landed = 1 - miss - dodge }
end

local function avg(w) return (w.min + w.max) / 2 end

function M.white(S, hand)
  local w = S.weapons[hand]
  if not w then return 0 end
  return avg(w) * M.meleeTable(S, true).factor * M.armorMult(S)
end

function M.normalized(S, hand)
  local w = S.weapons[hand]
  if not w then return 0 end
  local ap = (S.player.ap or 0) / 14
  local mult = hand == "oh" and 0.5 or 1
  local norm = w.twoHand and 3.3 or 2.4
  return avg(w) - ap * w.speed * mult + ap * norm * mult
end

function M.wf(S)
  local w = S.weapons.mh
  if not w or w.enchant ~= "wf" then return 0, 0 end
  local ew = talent(S, "elementalWeapons")
  local bonus = byLevel(M.WF_AP, S.player.level) * (1 + (M.EW_WF[ew] or 0))
  local procs = M.WF_CHANCE / (1 + M.WF_CHANCE * math.floor(M.WF_ICD / w.speed))
  local attack = (avg(w) + bonus / 14 * w.speed) * M.meleeTable(S, false).factor * M.armorMult(S)
  return procs * 2 * attack, procs
end

function M.ftHit(S, hand)
  local w = S.weapons[hand]
  if not w or w.enchant ~= "ft" then return 0 end
  local ew = talent(S, "elementalWeapons")
  local base = byLevel(M.FT_PER_SPEED, S.player.level) * w.speed * (1 + (M.EW_FT[ew] or 0))
  local dmg = base + 0.1 * w.speed / 2.6 * (S.player.spFire or 0)
  return dmg * M.spellHit(S) * M.spellCritFactor(S)
end

function M.staticHit(S)
  local r = talent(S, "staticShock")
  if r == 0 or (S.buffs.ls.charges or 0) <= 0 then return 0 end
  return 0.02 * r * spellDamage(S, "lightningShield", M.row(S, "lightningShield"))
end

local function procsPerHit(S, hand) return M.ftHit(S, hand) + M.staticHit(S) end

function M.auto(S, hand)
  local w = S.weapons[hand]
  if not w then return 0 end
  local white = M.meleeTable(S, true)
  local dmg = M.white(S, hand) + procsPerHit(S, hand) * white.landed
  if hand == "mh" then
    local wfDmg, procs = M.wf(S)
    dmg = dmg + wfDmg + procs * 2 * procsPerHit(S, "mh") * M.meleeTable(S, false).landed
  end
  return dmg
end

local function mwChance(S, hand)
  local r = talent(S, "maelstromWeapon")
  local w = S.weapons[hand]
  if r == 0 or not w then return 0 end
  return math.min(1, 2 * r * w.speed / 60)
end

function M.mwPerHit(S, hand)
  return mwChance(S, hand) * M.meleeTable(S, false).landed
end

function M.mwPerSwing(S, hand)
  local c = mwChance(S, hand)
  if c == 0 then return 0 end
  local stacks = c * M.meleeTable(S, true).landed
  if hand == "mh" then
    local _, procs = M.wf(S)
    stacks = stacks + procs * 2 * c * M.meleeTable(S, false).landed
  end
  return stacks
end

function M.targets(S, key)
  local n = math.max(1, (S.enemies and S.enemies.nearby) or 1)
  if key == "fireNova" or key == "magmaTotem" then return n end
  if key == "chainLightning" then return math.min(n, 3) end
  return 1
end

function M.dot(S, key)
  local row = M.row(S, key)
  if not row or not row.tick then return 0, 0, 3 end
  local per = (row.tick + (row.tickCoef or 0) * spellPower(S, SCHOOL[key])) * M.spellMult(S, key) * M.spellCritFactor(S)
  return per, row.ticks or 0, row.period or 3
end

function M.periodic(S, source)
  if source == "flameShock" then
    local per, _, period = M.dot(S, "flameShock")
    return per / period
  elseif source == "magmaTotem" then
    return spellDamage(S, "magmaTotem", M.row(S, "magmaTotem")) * M.targets(S, "magmaTotem") / M.MAGMA_PERIOD
  elseif source == "searingTotem" then
    return spellDamage(S, "searingTotem", M.row(S, "searingTotem")) / M.SEARING_PERIOD
  elseif source == "fireElemental" then
    return (M.FE_BASE_DPS + M.FE_SP * (S.player.spFire or 0)) * (1 + 0.05 * talent(S, "callOfFlame"))
  elseif source == "feralSpirit" then
    local perHit = M.WOLF_BASE + M.WOLF_AP * (S.player.ap or 0) / 14 * M.WOLF_SPEED
    return 2 * perHit / M.WOLF_SPEED * M.armorMult(S)
  end
  return 0
end

function M.action(S, key)
  if not (S.spells and S.spells[key]) then return 0 end
  if DIRECT[key] then return spellDamage(S, key, M.row(S, key)) end
  if key == "chainLightning" then
    local single = spellDamage(S, key, M.row(S, key))
    local total = 0
    for i = 1, M.targets(S, key) do total = total + single * M.CL_FALLOFF[i] end
    return total
  end
  if key == "fireNova" then
    return spellDamage(S, key, M.row(S, key)) * M.targets(S, key)
  end
  if key == "stormstrike" then
    local y = M.meleeTable(S, false)
    local w = M.normalized(S, "mh") + M.normalized(S, "oh")
    local procs = procsPerHit(S, "mh") * y.landed
    if S.weapons.oh then procs = procs + procsPerHit(S, "oh") * y.landed end
    return w * y.factor * M.armorMult(S) + procs
  end
  if key == "lavaLash" then
    local oh = S.weapons.oh
    if not oh then return 0 end
    local y = M.meleeTable(S, false)
    local bonus = oh.enchant == "ft" and 1.25 or 1
    return M.normalized(S, "oh") * bonus * y.factor + procsPerHit(S, "oh") * y.landed
  end
  return 0
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `docker compose run --rm test busted spec/damage_spec.lua`
Expected: PASS, все `it` зелёные.

Если красный тест про `ftHit`/`auto`/`static` — проверь, что `spells.rank` в тесте подменён (`before_each`), а не взят из сгенерированных данных.

- [ ] **Step 5: Commit**

```bash
git add src/damage.lua spec/damage_spec.lua
git commit -m "Формулы ожидаемого урона энх-шамана (damage)"
```

---

### Task 8: Модель перехода (`src/model.lua`)

**Files:**
- Create: `src/model.lua`
- Test: `spec/model_spec.lua`

**Interfaces:**
- Consumes:
  - `spells.CATALOG` и `spells.byKey[key]` с полями `key, gcd, cd, sharedCd, castBase` (часть 2);
  - все функции `damage` из задачи 7.
- Produces:
  - по контракту: `model.readyIn`, `model.castTime`, `model.apply`, `model.wait`, `model.actions`;
  - из «Contract additions»: `model.HORIZON`, `model.copy`, `model.advance`, `model.cooldownFor`, `model.gcdFor`, `model.lsMaxCharges`, `model.addMw`, `model.resetSwings`.

Правила, которые проверяют тесты (из спеки §5.2 и §6):
- **Шоки** делят один кулдаун: `6 − 0,2 · reverberation`. Fire Nova: `10 − 2 · improvedFireNova`, работает только при стоящем огненном тотеме.
- **Searing и Magma** нельзя ставить, пока стоит Fire Elemental.
- **Время каста:** `castBase · (1 − 0,2 · floor(MW)) / spellHaste`, 0 при 5 стаках. Каст с временем больше нуля нельзя начать в движении.
- **Удары во время каста:**
  - каст с 0 стаков MW — удары во время каста пропадают, в конце каста таймеры обеих рук сбрасываются на полную скорость;
  - каст с 1–4 стаками — удар, «созревший» во время каста, вылетает в момент окончания каста;
  - мгновенное заклинание из `swing.resetByInstant` — сразу сбрасывает таймеры.
- **Maelstrom:** Lightning Bolt и Chain Lightning тратят все стаки. Автоудары, Stormstrike и Lava Lash добавляют ожидаемые стаки, максимум 5.
- **Заряды Stormstrike** тратят Earth Shock, Lightning Bolt и Chain Lightning.
- **Непрерывный урон** — DoT, тотемы, волки — считается только в пределах остатка эффекта и `ttd`. Мёртвая цель не получает урона.
- **Shamanistic Rage:** каждый удар при активном бафе возвращает `0,15 · AP` маны.
- **Входной `S` никогда не меняется.**

- [ ] **Step 1: Write the failing test**

`spec/model_spec.lua`:

```lua
local model = require("model")
local damage = require("damage")

local function base()
  return {
    now = 100, gcdRemains = 0, castRemains = 0, gcd = 1.5, latency = 0.15, mode = "raid",
    player = { level = 80, mana = 8000, manaMax = 10000, baseMana = 4396, hpPct = 1, ap = 4000,
               spNature = 1200, spFire = 1200, meleeCrit = 0.30, spellCrit = 0.20, meleeHit = 0.08,
               spellHit = 0.10, spellHaste = 1.0, meleeHaste = 1.0, moving = false, inCombat = true },
    weapons = { mh = { speed = 2.6, min = 600, max = 900, enchant = "wf" },
                oh = { speed = 2.6, min = 300, max = 450, enchant = "ft" } },
    talents = { maelstromWeapon = 5 },
    spells = {
      lightningBolt = { id = 49238, rank = 14, cd = 0, cost = 300, cast = 2.5 },
      chainLightning = { id = 49271, rank = 8, cd = 0, cost = 1100, cast = 2 },
      earthShock = { id = 49231, rank = 10, cd = 0, cost = 800, cast = 0 },
      flameShock = { id = 49233, rank = 9, cd = 0, cost = 700, cast = 0 },
      frostShock = { id = 49236, rank = 7, cd = 0, cost = 800, cast = 0 },
      stormstrike = { id = 17364, rank = 1, cd = 0, cost = 400, cast = 0 },
      lavaLash = { id = 60103, rank = 1, cd = 0, cost = 200, cast = 0 },
      fireNova = { id = 61657, rank = 9, cd = 0, cost = 900, cast = 0 },
      magmaTotem = { id = 58734, rank = 7, cd = 0, cost = 1000, cast = 0 },
      searingTotem = { id = 58704, rank = 10, cd = 0, cost = 300, cast = 0 },
      lightningShield = { id = 49281, rank = 11, cd = 0, cost = 0, cast = 0 },
      shamanisticRage = { id = 30823, rank = 1, cd = 0, cost = 0, cast = 0 },
    },
    buffs = { mw = { stacks = 0, remains = 0 }, ls = { charges = 3, remains = 600 },
              flurry = { charges = 0, remains = 0 }, rage = 0, lust = 0, em = 0 },
    target = { exists = true, enemy = true, level = 83, hp = 1e7, hpMax = 1e7, hpPct = 1, ttd = 300,
               range = "melee", fs = 0, ss = { charges = 0, remains = 0 } },
    totems = { fire = { remains = 0 }, water = { remains = 0 } },
    swing = { attacking = true, mh = { next = 5, speed = 2.6 }, oh = { next = 5, speed = 2.6 }, resetByInstant = {} },
    enemies = { melee = 1, nearby = 1 },
    inflight = {}, pets = { wolves = 0 },
  }
end

describe("model", function()
  describe("castTime", function()
    it("2.5 s base, -20% per Maelstrom stack, divided by haste", function()
      local S = base()
      assert.are.near(2.5, model.castTime(S, "lightningBolt"), 1e-9)
      S.buffs.mw.stacks = 3
      assert.are.near(1.0, model.castTime(S, "lightningBolt"), 1e-9)
      S.player.spellHaste = 1.25
      assert.are.near(0.8, model.castTime(S, "lightningBolt"), 1e-9)
    end)
    it("fractional stacks are floored", function()
      local S = base(); S.buffs.mw.stacks = 3.9
      assert.are.near(1.0, model.castTime(S, "lightningBolt"), 1e-9)
    end)
    it("instant at 5 stacks and for instants", function()
      local S = base(); S.buffs.mw.stacks = 5
      assert.are.equal(0, model.castTime(S, "lightningBolt"))
      assert.are.equal(0, model.castTime(S, "earthShock"))
    end)
  end)

  describe("readyIn", function()
    it("nil for unknown spells", function()
      local S = base(); S.spells.lavaLash = nil
      assert.is_nil(model.readyIn(S, "lavaLash"))
    end)
    it("waits for GCD and cooldown", function()
      local S = base(); S.gcdRemains = 0.7; S.spells.stormstrike.cd = 2
      assert.are.near(0.7, model.readyIn(S, "earthShock"), 1e-9)
      assert.are.near(2, model.readyIn(S, "stormstrike"), 1e-9)
    end)
    it("nil beyond the horizon", function()
      local S = base(); S.spells.stormstrike.cd = 7
      assert.is_nil(model.readyIn(S, "stormstrike"))
    end)
    it("nil without mana", function()
      local S = base(); S.player.mana = 100
      assert.is_nil(model.readyIn(S, "earthShock"))
    end)
    it("nil without an enemy target for targeted spells", function()
      local S = base(); S.target.exists = false
      assert.is_nil(model.readyIn(S, "earthShock"))
      S.buffs.ls.charges = 0
      assert.are.equal(0, model.readyIn(S, "lightningShield"))
    end)
    it("melee strikes need melee range, shocks 20 yd, bolts not far", function()
      local S = base(); S.target.range = "20"
      assert.is_nil(model.readyIn(S, "stormstrike"))
      assert.are.equal(0, model.readyIn(S, "earthShock"))
      S.target.range = "30"
      assert.is_nil(model.readyIn(S, "earthShock"))
      assert.are.equal(0, model.readyIn(S, "lightningBolt"))
      S.target.range = "far"
      assert.is_nil(model.readyIn(S, "lightningBolt"))
    end)
    it("Lava Lash needs an off hand", function()
      local S = base(); S.weapons.oh = nil
      assert.is_nil(model.readyIn(S, "lavaLash"))
    end)
    it("Fire Nova needs an active fire totem", function()
      local S = base()
      assert.is_nil(model.readyIn(S, "fireNova"))
      S.totems.fire = { kind = "searing", remains = 30 }
      assert.are.equal(0, model.readyIn(S, "fireNova"))
    end)
    it("does not replace Fire Elemental with Searing or Magma", function()
      local S = base(); S.totems.fire = { kind = "fireElemental", remains = 100 }
      assert.is_nil(model.readyIn(S, "magmaTotem"))
      assert.is_nil(model.readyIn(S, "searingTotem"))
    end)
    it("moving blocks hard casts but not 5-stack bolts", function()
      local S = base(); S.player.moving = true
      assert.is_nil(model.readyIn(S, "lightningBolt"))
      S.buffs.mw.stacks = 5
      assert.are.equal(0, model.readyIn(S, "lightningBolt"))
    end)
    it("Lightning Shield only when charges are missing", function()
      local S = base()
      assert.is_nil(model.readyIn(S, "lightningShield"))
      S.buffs.ls.charges = 1
      assert.are.equal(0, model.readyIn(S, "lightningShield"))
    end)
  end)

  describe("apply", function()
    it("never mutates the input state", function()
      local S = base(); S.buffs.mw.stacks = 5
      local before = model.copy(S)
      model.apply(S, "lightningBolt")
      assert.are.same(before, S)
    end)
    it("spends mana, sets cooldown and advances by GCD", function()
      local S = base()
      local S2, dmg, dt = model.apply(S, "stormstrike")
      assert.are.near(1.5, dt, 1e-9)
      assert.are.near(101.5, S2.now, 1e-9)
      assert.are.equal(7600, S2.player.mana)
      assert.are.near(8 - 1.5, S2.spells.stormstrike.cd, 1e-9)
      assert.is_true(dmg > 0)
    end)
    it("totems use a 1 s GCD", function()
      local _, _, dt = model.apply(base(), "searingTotem")
      assert.are.near(1.0, dt, 1e-9)
    end)
    it("shocks share one cooldown, Reverberation shortens it", function()
      local S = base()
      local S2 = model.apply(S, "earthShock")
      assert.are.near(6 - 1.5, S2.spells.flameShock.cd, 1e-9)
      assert.are.near(6 - 1.5, S2.spells.frostShock.cd, 1e-9)
      S.talents.reverberation = 5
      S2 = model.apply(S, "earthShock")
      assert.are.near(5 - 1.5, S2.spells.flameShock.cd, 1e-9)
    end)
    it("Improved Fire Nova shortens its cooldown", function()
      local S = base(); S.totems.fire = { kind = "searing", remains = 30 }; S.talents.improvedFireNova = 2
      local S2 = model.apply(S, "fireNova")
      assert.are.near(6 - 1.5, S2.spells.fireNova.cd, 1e-9)
    end)
    it("Lightning Bolt consumes all Maelstrom stacks", function()
      local S = base(); S.buffs.mw = { stacks = 5, remains = 20 }
      local S2 = model.apply(S, "lightningBolt")
      assert.is_true(S2.buffs.mw.stacks < 5)
      assert.is_true(S2.buffs.mw.stacks >= 0)
    end)
    it("Stormstrike puts 4 charges, nature spells consume one", function()
      local S = base()
      local S2 = model.apply(S, "stormstrike")
      assert.are.equal(4, S2.target.ss.charges)
      S2.spells.earthShock.cd = 0; S2.gcdRemains = 0
      local S3 = model.apply(S2, "earthShock")
      assert.are.equal(3, S3.target.ss.charges)
    end)
    it("Stormstrike and Lava Lash add expected Maelstrom", function()
      local S = base()
      local S2 = model.apply(S, "stormstrike")
      local expected = damage.mwPerHit(S, "mh") + damage.mwPerHit(S, "oh")
      assert.are.near(expected, S2.buffs.mw.stacks, 1e-9)
    end)
    it("Maelstrom is capped at 5", function()
      local S = base(); S.buffs.mw = { stacks = 4.9, remains = 20 }
      local S2 = model.apply(S, "stormstrike")
      assert.are.equal(5, S2.buffs.mw.stacks)
    end)
    it("Flame Shock sets the dot for ticks * period", function()
      local S2 = model.apply(base(), "flameShock")
      local _, ticks, period = damage.dot(base(), "flameShock")
      assert.are.near(ticks * period - 1.5, S2.target.fs, 1e-9)
      assert.is_nil(S2.inflight.flameShock)
    end)
    it("totems occupy the fire slot", function()
      local S2 = model.apply(base(), "magmaTotem")
      assert.are.equal("magma", S2.totems.fire.kind)
      assert.are.near(20 - 1.0, S2.totems.fire.remains, 1e-9)
    end)
    it("Lightning Shield restores charges (5 with Static Shock)", function()
      local S = base(); S.buffs.ls.charges = 0; S.talents.staticShock = 3
      local S2 = model.apply(S, "lightningShield")
      assert.are.equal(5, S2.buffs.ls.charges)
    end)
    it("Shamanistic Rage returns mana on every swing", function()
      local S = base(); S.swing.mh.next = 0.5; S.swing.oh.next = 0.6
      local S2 = model.apply(S, "shamanisticRage")
      assert.are.near(8000 + 2 * 0.15 * 4000, S2.player.mana, 1e-6)
    end)
  end)

  describe("swings during casts", function()
    it("0-stack bolt: swings during the cast are lost and timers reset at cast end", function()
      local S = base(); S.swing.mh.next = 1.0; S.swing.oh.next = 2.0
      local S2, dmg, dt = model.apply(S, "lightningBolt")
      assert.are.near(2.5, dt, 1e-9)
      assert.are.near(2.6, S2.swing.mh.next, 1e-9)
      assert.are.near(2.6, S2.swing.oh.next, 1e-9)
      assert.are.near(damage.action(S, "lightningBolt"), dmg, 1e-6)
    end)
    it("3-stack bolt: a swing due during the cast lands at cast end", function()
      local S = base(); S.buffs.mw = { stacks = 3, remains = 20 }
      S.swing.mh.next = 0.4; S.swing.oh.next = 1.2
      local S2, dmg, dt = model.apply(S, "lightningBolt")
      assert.are.near(1.5, dt, 1e-9)
      assert.are.near(1.0 + 2.6 - 1.5, S2.swing.mh.next, 1e-9)
      assert.are.near(1.2 + 2.6 - 1.5, S2.swing.oh.next, 1e-9)
      local expected = damage.action(S, "lightningBolt")
      assert.is_true(dmg > expected)
    end)
    it("instant spell does not touch swings by default", function()
      local S = base(); S.swing.mh.next = 0.4
      local S2 = model.apply(S, "earthShock")
      assert.are.near(0.4 + 2.6 - 1.5, S2.swing.mh.next, 1e-9)
    end)
    it("instant spell resets swings when calibration says so", function()
      local S = base(); S.swing.mh.next = 0.4; S.swing.resetByInstant = { earthShock = true }
      local S2 = model.apply(S, "earthShock")
      assert.are.near(2.6 - 1.5, S2.swing.mh.next, 1e-9)
    end)
  end)

  describe("wait", function()
    it("autos land on schedule and add Maelstrom", function()
      local S = base(); S.swing.mh.next = 0.5; S.swing.oh.next = 1.0
      local S2, dmg = model.wait(S, 2)
      assert.are.near(damage.auto(S, "mh") + damage.auto(S, "oh"), dmg, 1e-6)
      assert.are.near(0.5 + 2.6 - 2, S2.swing.mh.next, 1e-9)
      assert.are.near(damage.mwPerSwing(S, "mh") + damage.mwPerSwing(S, "oh"), S2.buffs.mw.stacks, 1e-9)
    end)
    it("no swings when not attacking or not in melee range", function()
      local S = base(); S.swing.mh.next = 0.5; S.swing.attacking = false
      local _, dmg = model.wait(S, 2)
      assert.are.equal(0, dmg)
      S.swing.attacking = true; S.target.range = "30"
      _, dmg = model.wait(S, 2)
      assert.are.equal(0, dmg)
    end)
    it("Flame Shock ticks continuously, limited by its remaining time", function()
      local S = base(); S.target.fs = 2
      local _, dmg = model.wait(S, 3)
      assert.are.near(damage.periodic(S, "flameShock") * 2, dmg, 1e-6)
    end)
    it("damage is limited by time to die", function()
      local S = base(); S.target.fs = 10; S.target.ttd = 1
      local S2, dmg = model.wait(S, 3)
      assert.are.near(damage.periodic(S, "flameShock") * 1, dmg, 1e-6)
      assert.is_true(S2.target.dead)
    end)
    it("dead target takes no damage", function()
      local S = base(); S.target.dead = true; S.target.fs = 10; S.swing.mh.next = 0.1
      local _, dmg = model.wait(S, 3)
      assert.are.equal(0, dmg)
    end)
    it("fire totem and wolves deal damage while active", function()
      local S = base(); S.totems.fire = { kind = "magma", remains = 1 }; S.pets.wolves = 2
      local _, dmg = model.wait(S, 3)
      local expected = damage.periodic(S, "magmaTotem") * 1 + damage.periodic(S, "feralSpirit") * 2
      assert.are.near(expected, dmg, 1e-6)
    end)
    it("timers count down and expire", function()
      local S = base()
      S.spells.stormstrike.cd = 2; S.gcdRemains = 1; S.target.fs = 1
      S.target.ss = { charges = 2, remains = 1 }; S.buffs.mw = { stacks = 2, remains = 1 }
      S.totems.fire = { kind = "searing", remains = 1 }; S.inflight = { flameShock = 1 }
      local S2 = model.wait(S, 1.5)
      assert.are.near(0.5, S2.spells.stormstrike.cd, 1e-9)
      assert.are.equal(0, S2.gcdRemains)
      assert.are.equal(0, S2.target.fs)
      assert.are.equal(0, S2.target.ss.charges)
      assert.are.equal(0, S2.buffs.mw.stacks)
      assert.is_nil(S2.totems.fire.kind)
      assert.is_nil(S2.inflight.flameShock)
    end)
  end)

  describe("actions", function()
    it("lists ready spells and waitSwing", function()
      local S = base(); S.swing.mh.next = 0.8; S.swing.oh.next = 1.3
      local keys = {}
      for _, a in ipairs(model.actions(S)) do keys[a.key] = a.readyIn end
      assert.are.equal(0, keys.stormstrike)
      assert.is_nil(keys.fireNova)
      assert.is_nil(keys.lightningShield)
      assert.are.near(0.81, keys.waitSwing, 1e-9)
    end)
  end)
end)
```

Примечание к тесту «Flame Shock sets the dot»: вторая проверка — про `inflight`. После сдвига на 1,5 с запись `inflight.flameShock` (1,0 с) уже истекла, поэтому её нет.

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose run --rm test busted spec/model_spec.lua`
Expected: FAIL — `module 'model' not found`.

- [ ] **Step 3: Write minimal implementation**

`src/model.lua`:

```lua
local spells = require("spells")
local damage = require("damage")

local M = {}

M.HORIZON = 6.0
M.MW_DURATION = 30
M.SS_CHARGES, M.SS_DURATION = 4, 12
M.TOTEM_KIND = { searingTotem = "searing", magmaTotem = "magma", fireElemental = "fireElemental" }
M.TOTEM_DURATION = { searingTotem = 60, magmaTotem = 20, fireElemental = 120 }
M.FIRE_SOURCE = { searing = "searingTotem", magma = "magmaTotem", fireElemental = "fireElemental" }
M.WATER_DURATION = 300
M.WOLVES_DURATION = 45
M.RAGE_DURATION = 15
M.RAGE_MANA_AP = 0.15
M.LS_DURATION = 600
M.INFLIGHT = 1.0
M.CAST_SPELLS = { lightningBolt = true, chainLightning = true }
M.NATURE_CONSUME = { earthShock = true, lightningBolt = true, chainLightning = true }
M.NEEDS_TARGET = { stormstrike = true, lavaLash = true, earthShock = true, flameShock = true,
                   frostShock = true, lightningBolt = true, chainLightning = true }
M.MELEE_ONLY = { stormstrike = true, lavaLash = true }
M.SHOCK_RANGE = { earthShock = true, flameShock = true, frostShock = true }
M.HANDS = { "mh", "oh" }

function M.copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = M.copy(v) end
  return out
end

local function talent(S, k) return (S.talents and S.talents[k]) or 0 end

function M.cooldownFor(S, key)
  local meta = spells.byKey[key]
  if meta.sharedCd == "shock" then return 6 - 0.2 * talent(S, "reverberation") end
  if key == "fireNova" then return 10 - 2 * talent(S, "improvedFireNova") end
  return meta.cd or 0
end

function M.gcdFor(S, key)
  local g = spells.byKey[key].gcd or 0
  if g <= 0 then return 0 end
  if g < 1.5 then return 1.0 end
  return math.max(1.0, S.gcd or 1.5)
end

function M.lsMaxCharges(S)
  return 3 + (talent(S, "staticShock") > 0 and 2 or 0)
end

function M.castTime(S, key)
  local meta = spells.byKey[key]
  if not meta or (meta.castBase or 0) <= 0 then return 0 end
  local mw = math.floor((S.buffs.mw.stacks or 0) + 1e-9)
  if mw >= 5 then return 0 end
  return meta.castBase * (1 - 0.2 * mw) / (S.player.spellHaste or 1)
end

function M.readyIn(S, key)
  local meta, sp = spells.byKey[key], S.spells[key]
  if not meta or not sp then return nil end
  local t = S.target
  local hasTarget = t and t.exists and t.enemy and not t.dead
  if M.NEEDS_TARGET[key] then
    if not hasTarget or t.range == "far" then return nil end
    if M.MELEE_ONLY[key] and t.range ~= "melee" then return nil end
    if M.SHOCK_RANGE[key] and t.range ~= "melee" and t.range ~= "20" then return nil end
  end
  local fire = S.totems.fire
  if key == "lavaLash" and not S.weapons.oh then return nil end
  if key == "fireNova" and not (fire.kind and (fire.remains or 0) > 0) then return nil end
  if (key == "searingTotem" or key == "magmaTotem") and fire.kind == "fireElemental" and (fire.remains or 0) > 0 then return nil end
  if key == "magmaTotem" and not hasTarget and (S.enemies.nearby or 0) < 1 then return nil end
  if key == "lightningShield" and (S.buffs.ls.charges or 0) >= M.lsMaxCharges(S) then return nil end
  if (sp.cost or 0) > S.player.mana then return nil end
  if S.player.moving and M.castTime(S, key) > 0 then return nil end
  local r = math.max(sp.cd or 0, S.castRemains or 0)
  if M.gcdFor(S, key) > 0 then r = math.max(r, S.gcdRemains or 0) end
  if r > M.HORIZON then return nil end
  return r
end

function M.addMw(n, x)
  if x <= 0 then return end
  local mw = n.buffs.mw
  mw.stacks = math.min(5, (mw.stacks or 0) + x)
  mw.remains = M.MW_DURATION
end

function M.resetSwings(n)
  for _, h in ipairs(M.HANDS) do
    local s = n.swing[h]
    if s then s.next = s.speed end
  end
end

local function runSwings(n, dt, cast)
  local dmg = 0
  for _, hand in ipairs(M.HANDS) do
    local s = n.swing[hand]
    if s and (s.speed or 0) > 0 then
      local at = s.next
      if cast then
        if cast.reset then
          at = cast.ends + s.speed
        elseif at < cast.ends then
          at = cast.ends
        end
      end
      while at <= dt + 1e-9 do
        dmg = dmg + damage.auto(n, hand)
        M.addMw(n, damage.mwPerSwing(n, hand))
        if (n.buffs.rage or 0) > at then
          n.player.mana = math.min(n.player.manaMax, n.player.mana + M.RAGE_MANA_AP * n.player.ap)
        end
        at = at + s.speed
      end
      s.next = at - dt
    end
  end
  return dmg
end

local function dec(x, dt) return math.max(0, (x or 0) - dt) end

function M.advance(n, dt, cast)
  local t = n.target
  local alive = t.exists and t.enemy and not t.dead
  local dmg = 0
  if n.swing.attacking and alive and t.range == "melee" then
    dmg = dmg + runSwings(n, dt, cast)
  else
    for _, h in ipairs(M.HANDS) do
      local s = n.swing[h]
      if s then s.next = dec(s.next, dt) end
    end
  end
  if alive then
    local life = dt
    if t.ttd then life = math.min(life, math.max(0, t.ttd)) end
    if (t.fs or 0) > 0 then dmg = dmg + damage.periodic(n, "flameShock") * math.min(life, t.fs) end
    local fire = n.totems.fire
    if fire.kind and (fire.remains or 0) > 0 then
      dmg = dmg + damage.periodic(n, M.FIRE_SOURCE[fire.kind]) * math.min(life, fire.remains)
    end
    if (n.pets.wolves or 0) > 0 then
      dmg = dmg + damage.periodic(n, "feralSpirit") * math.min(life, n.pets.wolves)
    end
  end
  for _, sp in pairs(n.spells) do sp.cd = dec(sp.cd, dt) end
  n.gcdRemains, n.castRemains = dec(n.gcdRemains, dt), dec(n.castRemains, dt)
  local b = n.buffs
  b.mw.remains = dec(b.mw.remains, dt); if b.mw.remains <= 0 then b.mw.stacks = 0 end
  b.ls.remains = dec(b.ls.remains, dt); if b.ls.remains <= 0 then b.ls.charges = 0 end
  b.flurry.remains = dec(b.flurry.remains, dt); if b.flurry.remains <= 0 then b.flurry.charges = 0 end
  b.rage, b.lust, b.em = dec(b.rage, dt), dec(b.lust, dt), dec(b.em, dt)
  t.fs = dec(t.fs, dt)
  t.ss.remains = dec(t.ss.remains, dt); if t.ss.remains <= 0 then t.ss.charges = 0 end
  local fire = n.totems.fire
  fire.remains = dec(fire.remains, dt); if fire.remains <= 0 then fire.kind = nil end
  n.totems.water.remains = dec(n.totems.water.remains, dt)
  n.pets.wolves = dec(n.pets.wolves, dt)
  for k, v in pairs(n.inflight) do
    local left = v - dt
    if left <= 0 then n.inflight[k] = nil else n.inflight[k] = left end
  end
  n.now = n.now + dt
  if alive then
    t.hp = t.hp - dmg
    if t.ttd then t.ttd = t.ttd - dt end
    if t.hp <= 0 or (t.ttd and t.ttd <= 0) then t.dead = true end
  end
  return dmg
end

function M.wait(S, dt)
  local n = M.copy(S)
  local dmg = M.advance(n, dt, nil)
  return n, dmg
end

function M.apply(S, key)
  local meta = spells.byKey[key]
  local n = M.copy(S)
  local sp = n.spells[key]
  local ct = M.castTime(n, key)
  local dt = math.max(M.gcdFor(n, key), ct)
  local dmg = damage.action(n, key)
  local mwAtCast = math.floor((n.buffs.mw.stacks or 0) + 1e-9)

  n.player.mana = n.player.mana - (sp.cost or 0)
  local cd = M.cooldownFor(n, key)
  if meta.sharedCd then
    for k, other in pairs(n.spells) do
      local m = spells.byKey[k]
      if m and m.sharedCd == meta.sharedCd then other.cd = cd end
    end
  else
    sp.cd = cd
  end

  local ss = n.target.ss
  if M.NATURE_CONSUME[key] and (ss.charges or 0) > 0 then
    ss.charges = ss.charges - 1
    if ss.charges <= 0 then ss.remains = 0 end
  end
  if M.CAST_SPELLS[key] then n.buffs.mw.stacks = 0; n.buffs.mw.remains = 0 end
  if key == "stormstrike" then
    n.target.ss = { charges = M.SS_CHARGES, remains = M.SS_DURATION }
    M.addMw(n, damage.mwPerHit(n, "mh") + (n.weapons.oh and damage.mwPerHit(n, "oh") or 0))
  elseif key == "lavaLash" then
    M.addMw(n, damage.mwPerHit(n, "oh"))
  elseif key == "flameShock" then
    local _, ticks, period = damage.dot(n, "flameShock")
    n.target.fs = ticks * period
  elseif M.TOTEM_KIND[key] then
    n.totems.fire = { kind = M.TOTEM_KIND[key], remains = M.TOTEM_DURATION[key] }
  elseif key == "callOfElements" then
    n.totems.water.remains = M.WATER_DURATION
    if not n.totems.fire.kind then n.totems.fire = { kind = "searing", remains = M.TOTEM_DURATION.searingTotem } end
  elseif key == "lightningShield" then
    n.buffs.ls = { charges = M.lsMaxCharges(n), remains = M.LS_DURATION }
  elseif key == "shamanisticRage" then
    n.buffs.rage = M.RAGE_DURATION
  elseif key == "feralSpirit" then
    n.pets.wolves = M.WOLVES_DURATION
  end
  n.inflight[key] = M.INFLIGHT
  if n.target.exists and not n.target.dead then n.target.hp = n.target.hp - dmg end

  local cast
  if ct > 0 then
    cast = { ends = ct, reset = mwAtCast == 0 }
  elseif n.swing.resetByInstant and n.swing.resetByInstant[key] then
    M.resetSwings(n)
  end
  local autoDmg = M.advance(n, dt, cast)
  return n, dmg + autoDmg, dt
end

function M.actions(S)
  local out = {}
  for _, meta in ipairs(spells.CATALOG) do
    local r = M.readyIn(S, meta.key)
    if r then out[#out + 1] = { key = meta.key, readyIn = r } end
  end
  local sw = S.swing
  if sw and sw.attacking then
    local nxt = sw.mh and sw.mh.next or math.huge
    if sw.oh then nxt = math.min(nxt, sw.oh.next) end
    if nxt < M.HORIZON then out[#out + 1] = { key = "waitSwing", readyIn = nxt + 0.01 } end
  end
  return out
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `docker compose run --rm test busted spec/model_spec.lua`
Expected: PASS.

Затем: `docker compose run --rm test busted spec/damage_spec.lua spec/model_spec.lua` — оба файла зелёные.

- [ ] **Step 5: Commit**

```bash
git add src/model.lua spec/model_spec.lua
git commit -m "Модель перехода состояния: кулдауны, стаки, удары во время каста (model)"
```

---

## Review Focus (кандидаты от части 3 для общего списка)

- **Неизвестный уровень цели** (`UnitLevel` = −1 у боссов): считается как +3, броня босса. Закреплено тестами `spellHit` и `targetArmor(-1)`.
- **Цель умирает посреди горизонта:** после смерти ни автоатаки, ни DoT, ни тотемы урона не дают. Иначе поиск переоценит длинные цепочки на мобе при прокачке. Закреплено тестами `ttd` и `dead`.
- **Нет левой руки** (прокачка до 40 уровня, двуручник): Lava Lash недоступен, белые удары без штрафа двуручника, нормализация 3.3. Закреплено тестами уровня 20 и `lavaLash without off hand`.
- **Дробные стаки Maelstrom:** на время каста влияют только целые. Закреплено тестом `fractional stacks are floored`.
