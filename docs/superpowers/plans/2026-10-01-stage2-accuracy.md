# Этап 2 — точнее расчёт: план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Модель считает урон так, как он идёт в рейде и в группе: броня цели с Sunder Armor / Faerie Fire, +13% к заклинаниям, +3% крита, +4% физического урона; не ценит свои тотемы, которые группа уже даёт (Horn of Winter, чужой Windfury Totem, Improved Icy Talons); знает реликвию, комплект T7–T10 и символы; задержку (пинг) меряет сама по нажатиям, а не берёт `GetNetStats + 0.1`.

**Architecture:** Всё, что меняет формулы, приходит в движок одной таблицей `S.mods` (только чтение, общая для всех копий состояния в поиске). Её собирает `snapshot` из двух чистых модулей: `raid` (дебаффы цели, баффы игрока, свои тотемы земли и воздуха → множители) и `gear` (+ данные `gear_data`: предметы, комплекты, символы → добавки). `damage`, `model`, `value` читают `S.mods`; без неё (`nil`) всё считается как раньше, бит в бит. Новый код и данные помечены «только в аддоне»: сборка ауры вырезает строки между `--@addon` и `--@end` и не кладёт модули `B.ADDON_SRC` — строка ауры (62 152 из 63 000 байт, запас 848) не растёт. Пинг — общий для ауры и аддона, если влезает (задача 2).

**Tech Stack:** Lua 5.1 (клиент 3.3.5a), busted 2.2.0 в Docker (`docker compose run --rm test …`).

**Spec:** этап 2 дорожной карты `docs/superpowers/specs/2026-10-01-addon-roadmap.md` (строки «Дебаффы рейда…», «Пинг», «Тотемы в группе», «Экипировка»; строка «Кулдауны под Bloodlust» — не в этом плане). Перед работой прочитать `AGENTS.md` (особенно «Поиск и скорость» и «Сверка с wowsims») и `.claude/rules/ARCHITECTURE.md`. Исполнители и владение файлами — `docs/superpowers/plans/2026-10-01-stage2-contracts.md`.

**Источники чисел** (скачаны и сверены при планировании, 2026-10-01):
- wowsims/wotlk: `sim/core/debuffs.go` (категории дебаффов, внутри категории — сильнейший, категории перемножаются), `sim/core/test_utils.go` `FullDebuffs` (набор рейда в их тестах энха), `sim/shaman/items_wotlk.go`, `items.go`, `stormstrike.go`, `lavalash.go`, `weapon_imbues.go`, `shocks.go`, `lightning_shield.go`, `lightning_bolt.go`, `talents.go`, `spirit_wolves.go`, `chain_lightning.go` (комплекты, реликвии, символы), `assets/database/db.json` (`setName` → id предметов), `assets/db_inputs/glyph_id_map.json` (id предмета символа → id заклинания, которое отдаёт `GetGlyphSocketInfo`).
- FrameXML 3.3.5a (`wowgaming/3.3.5-interface-files`): `UnitAura(unit, i, filter)` → `name, rank, icon, count, debuffType, duration, expirationTime, unitCaster, isStealable, shouldConsolidate, spellId` (`BuffFrame.lua:125`, `TargetFrame.lua:413`; `spellId` в FrameXML не читается — сверяем по имени, как `snapshot.auras` сейчас); `GetGlyphSocketInfo(socket[, talentGroup])` → `enabled, glyphType (1 major, 2 minor), glyphSpell, icon`, сокетов `NUM_GLYPH_SLOTS = 6` (`Blizzard_GlyphUI.lua:19,65`); `GetInventoryItemID("player", slot)` (`EquipmentManager.lua:80`); `INVSLOT_RANGED = 18` (реликвия), `INVSLOT_TRINKET1/2 = 13/14` (`Constants.lua`); события `UNIT_INVENTORY_CHANGED`, `GLYPH_ADDED`, `GLYPH_REMOVED`, `GLYPH_UPDATED`, `ACTIVE_TALENT_GROUP_CHANGED` есть, `PLAYER_EQUIPMENT_CHANGED` в FrameXML 3.3.5a не встречается — не использовать.

## Решения (по умолчанию, пользователь может поправить до начала)

- **Ветка** `feat/accuracy` от `feat/addon` (этап 0 ещё не в `main`); в `main` — PR после этапа 0.
- **Что получает аура.** Строке ауры осталось 848 байт: дебаффы, баффы группы, экипировка и символы — **только в аддоне** (механизм — задача 1). Пинг (задача 2) — в обоих, если сборка ауры остаётся ≤ `B.MAX_IMPORT`; если нет — код пинга тоже уходит в блок `--@addon`, аура остаётся на `GetNetStats + 0.1`. Код движка один (`src/`); аура — тот же движок без блоков `--@addon`, т. е. ровно как до этапа 2.
- **Механизм «только в аддоне»** — два вида: (1) модули `src/`, перечисленные в `B.ADDON_SRC` (`raid`, `gear_data`, `gear`), сборка ауры не кладёт; (2) строки между `--@addon` и `--@end` (каждый маркер — отдельная строка) сборка ауры заменяет пустыми строками (номера строк в ошибках совпадают с `src/`). Блок обязан быть таким, что без него код остаётся верным Lua и считает как раньше. Тесты (`busted`) гоняют `src/` целиком, то есть поведение аддона; поведение ауры проверяет `spec/build_spec.lua` на вырезанной сборке.
- **`S.mods`** — одна таблица на снимок, только чтение. Поля (все необязательные, нет поля = нейтрально):
  - из `raid`: `armor` (множитель брони цели), `spellTaken` (×урон заклинаниями: природа, огонь, лёд), `physTaken` (×физический урон), `critTaken` (+шанс крита, ближний бой и заклинания), `spellCritTaken` (+крит заклинаний), `spellHitTaken` (+меткость заклинаний), `support` (доля урона автоатак, которую ещё стоят свои тотемы поддержки, вместо `value.SUPPORT`);
  - из `gear` (все — добавки к числу без экипировки): `ssFlat`, `llFlat`, `wfAp`, `ssMult`, `llMult`, `lsMult`, `shockMult`, `lbMult`, `staticChance`, `mwPpm`, `ssNature`, `llFt`, `fsCrit`, `wolvesAp`, `wfChance`, `clTargets`, `shockGcd`, `fireNovaCd`; задача 10 добавит `proc`.
  Нет ни одного эффекта — `S.mods = nil`.
- **Чего не добавлять повторно.** Характеристики игрока (`UnitAttackPower`, `GetCritChance`, `GetSpellBonusDamage`, `GetCombatRatingBonus`) уже содержат все баффы на игроке: Strength of Earth / Horn of Winter, бафф Totem of Wrath (+280 SP), Leader of the Pack, символ Flametongue Weapon (+2% крита), прок тринкета или реликвии, пока он висит, ставки предметов. В `S.mods` идут только эффекты на **цели** (дебаффы) и модификаторы **способностей** (комплекты, реликвии, символы). Totem of Wrath: дебафф цели (+3% крита) — считаем, бафф игрока (SP) — нет.
- **Ранги талантов за дебаффом** (Heart of the Crusader 1–3, Ebon Plaguebringer, Earth and Moon, Blood Frenzy, Savage Combat, Master Poisoner) в ауре не видны — берём максимум: в рейде их берут полностью. Improved Faerie Fire (+3% меткости заклинаний) по ауре не отличить от обычного Faerie Fire — меткость от Faerie Fire не берём (только броню); +3% меткости даёт только Misery.
- **Тотемы в группе.** `value.SUPPORT = 0.06` (доля урона автоатак за свои тотемы поддержки) делится: `haste = 0.04` (Windfury Totem, 20% скорости ближнего боя) и `strength = 0.02` (Strength of Earth): +20% скорости атаки дают ~1 − 1/1,2 = 16,7% урона автоатак, 155 силы и ловкости — ~310 AP и ~1,9% крита ≈ 8–9% при 4000 AP, примерно 2 : 1. Покрыто группой: скорость — есть Improved Icy Talons или бафф Windfury Totem при своём воздушном тотеме не Windfury; сила — есть Horn of Winter или бафф Strength of Earth при своём земляном тотеме не Strength of Earth. Чужой Totem of Wrath при своём Flametongue Totem: модель уже считает свой огненный «чужим» (`kind = "other"`, урона нет) и ставит Searing / Magma, а Call of the Elements в модели кладёт Magma — менять нечего, задача 6 закрывает это тестом.
- **Экипировка:** реликвии с постоянной добавкой, комплекты T7–T10 и символы — задачи 5, 7, 8; реликвии с проком от кнопки (Totem of the Avalanche, Totem of Dueling, Totem of Indomitability, Totem of Quaking Earth, Totem of Electrifying Wind, Totem of the Elemental Plane, Stonebreaker's Totem) — задача 10. **Не входит:** тринкеты (проки статов на игроке уже в листе персонажа, пока висят, и не зависят от выбора кнопки, кроме ProcMask «только заклинания / только ближний бой»; on-use — строка дорожной карты «Кулдауны под Bloodlust»); T7 4 (+5% Flurry: модель не считает скорость Flurry, её даёт `UnitAttackSpeed`); T10 2 и 4 (в wowsims не реализованы — `TODO` в `items_wotlk.go`, сверять не с чем); Bizuri's Totem of Shattered Ice (прок от тиков Flame Shock, не от нажатия); символы Elemental Mastery, Totem of Wrath, лечебные.
- **Размер данных:** `gear_data` — ~70 id предметов и ~10 символов, в аддоне без ограничения; генерировать не нужно, списки в задаче 5 выписаны из `db.json` wowsims.

## Global Constraints

- Lua 5.1. В `src/` нельзя `pcall`, `loadstring`, `setfenv`, `getfenv`, `_G`, `SlashCmdList`, `package`, `io`, `debug` — даже в комментариях (`spec/build_spec.lua` «uses nothing the WeakAuras sandbox blocks»).
- API игры читают только `snapshot`, `runtime`, `timeline`; `raid`, `gear`, `gear_data` — чистые модули.
- **Бит в бит:** без `S.mods` (и с `S.mods`, где все поля нейтральны: множители 1, добавки 0) — те же `value`, `nodes`, шаги на `spec/fixtures/recorded.lua`, 150 состояниях perf и сценариях 10–80 уровней. Порядок операций с плавающей точкой в старых выражениях не менять: новый множитель — отдельной строкой после старого выражения (`v = v * mods.x`), не внутрь.
- **Поиск и скорость:** `S.mods` читается только внутри функций под `memoize`/`memoizeFlags` или в их вызовах; в узлах поиска и рабочих копиях `S.mods` — общая ссылка (как `S.enemies`), без копирования. Лимиты `spec/perf_spec.lua`: ≤ 600 тыс. инструкций и ≤ 300 КБ мусора на поиск — и для состояний с `S.mods` (задача 9).
- **Сверка с wowsims:** при расхождении сначала искать ошибку в `damage`/`model`/`value`/`search`; ожидание меняется только через `alt` с конкретной причиной и числами поиска. Подгонять `src/` под отдельные тестовые состояния нельзя.
- Строка импорта ауры ≤ `B.MAX_IMPORT` (63 000); тест «keeps the import string short enough» зелёный в каждой ветке.
- Тексты в игре — на английском; комментарии в коде — по-английски, «почему», а не «что».
- Все команды — в контейнере: `docker compose run --rm test busted …`; на хосте Lua нет.
- Коммиты — по-русски, в стиле `git log` (`Точность: …`), без номеров задач и без упоминаний ИИ (`Co-Authored-By`, «Generated with» запрещены).
- `src/spells_data.lua` руками не править.

## Review Focus

1. **Двойной учёт.** Бафф на игроке (Strength of Earth, Horn of Winter, бафф Totem of Wrath, Leader of the Pack, символ Flametongue Weapon, прок реликвии, пока висит) уже в характеристиках снимка — в `S.mods` его быть не должно. Totem of Wrath считается один раз: как дебафф цели (+3% крита). Внутри категории — сильнейший (Sunder 5 + Expose = 20%, не 40%; Faerie Fire + Sting = 5%), категории перемножаются (броня 0,8 × 0,95). Lava Lash — огонь: `spellTaken`, не броня и не `physTaken`; Stormstrike +20% природы и Curse of the Elements перемножаются. Одна добавка из двух источников складывается (T7 2 + символ Lightning Shield = +30%), как `DamageMultiplier` в wowsims (тест — задачи 4, 5, 7).
2. **Перформанс поиска.** `S.mods` не копируется по узлам (одна ссылка в `cloneState`/`fillState`/`fillScratch`), читается только под `memoize`; инструкции и мусор на поиск с полным рейдом и экипировкой — в лимитах (тест — задача 9). `snapshot` читает ауры цели один лишний проход за снимок, не за поиск.
3. **Расхождение с wowsims.** Те же случаи `spec/wowsims_spec.lua` — второй раз с дебаффами `FullDebuffs`; любое переключение первой кнопки — только `alt` с причиной и числами, без правки `src/` под случай (задача 9). Бит в бит без `S.mods` — на фикстуре, perf и прокачке.
4. **Рост строки ауры.** Аура собирается без блоков `--@addon` и модулей `B.ADDON_SRC`; в её коде нет `S.mods`, `raid`, `gear`; размер ≤ `B.MAX_IMPORT`; аура на записанной фикстуре даёт те же планы, что до этапа 2 (тест — задачи 1 и 12).
5. **Пинг.** Одна проба на нажатие (`START` подтвердил — `SUCCEEDED` того же каста уже не проба), `FAILED` и нажатие без `SENT` — не пробы; медиана устойчива к одному выбросу; до `PING_MIN` проб — `GetNetStats + 0.1` (тест — задача 2).
6. **Новые id заклинаний.** Дебаффы и баффы сверяются по имени (`GetSpellInfo(id)`): id должен давать **имя ауры на цели**, а не имя таланта (Ebon Plaguebringer → дебафф «Ebon Plague»). Список id для проверки в игре — задача 12.

---

## Карта файлов

- Modify `tools/build.lua` — `B.ADDON_OPEN`/`B.ADDON_CLOSE`, `B.ADDON_SRC`, `B.strip`, `B.bundle(srcDir, version, addon)`, `B.MODULES` + `raid`, `gear_data`, `gear`; `B.addonCode` собирает с `addon = true`.
- Create `src/raid.lua` — данные дебаффов и баффов группы (3.3.5a, wowsims) и `raid.effects(found, buffs, own, gearMods) -> mods | nil`.
- Create `src/gear_data.lua` — id предметов комплектов T7–T10, реликвии, символы; задача 10 — проки реликвий.
- Create `src/gear.lua` — `gear.effects(items, glyphs) -> mods | nil`.
- Modify `src/snapshot.lua` — `addPing`, `latency`; чтение дебаффов цели, баффов игрока, своих тотемов земли и воздуха, экипировки, символов → `S.mods`.
- Modify `src/runtime.lua` — проба пинга в `onCast`; `M.REGEAR` (пересчёт экипировки по событиям).
- Modify `src/damage.lua` — `S.mods` в броне, крите, меткости, уроне заклинаний и физическом; экипировка в Stormstrike, Lava Lash, Windfury, щите, шоках, Maelstrom, волках, Chain Lightning.
- Modify `src/model.lua` — `S.mods` в копиях состояния; символы Shocking и Fire Nova; задача 10 — бафф прока реликвии.
- Modify `src/value.lua` — `S.mods.support`; задача 10 — ценность прока реликвии.
- Modify `spec/support/game_mock.lua` — `GetInventoryItemID`, `GetGlyphSocketInfo`, имена id из `raid`.
- Modify `spec/support/scenario.lua` — `Sc.raidMods()`.
- Create `spec/raid_spec.lua`, `spec/gear_spec.lua`; Modify `spec/build_spec.lua`, `spec/runtime_spec.lua`, `spec/snapshot_spec.lua`, `spec/damage_spec.lua`, `spec/model_spec.lua`, `spec/value_spec.lua`, `spec/wowsims_spec.lua`, `spec/perf_spec.lua`.
- Modify `AGENTS.md`, `.claude/rules/ARCHITECTURE.md`, `README.md`.

## Волны (подробно — контракты)

| Волна | Задачи (параллельно) |
|---|---|
| 1 | 1 сборка «только в аддоне» · 2 пинг · 3 `S.mods` в формулах (рейд) |
| 2 | 4 модуль `raid` · 5 данные экипировки · 6 снимок читает рейд и экипировку · 7 экипировка в уроне · 8 символы в модели · 9 сверка wowsims и скорость с рейдом |
| 3 | 10 реликвии с проком от кнопки · 11 документация |
| 4 | 12 интеграция |

---

### Task 1: Сборка — код и модули «только в аддоне»

**Files:**
- Modify: `tools/build.lua` (`B.MODULES` ~5, `B.bundle` ~126, `B.addonCode` ~158)
- Create: `src/raid.lua`, `src/gear_data.lua`, `src/gear.lua` — заготовки с интерфейсом контракта и нейтральным поведением (содержимое пишут задачи 4 и 5)
- Test: `spec/build_spec.lua` (блок `describe("build (pure)", …)` — «lists modules…»; блок `describe("build #integration", …)` — «lists every source module…», «uses nothing the WeakAuras sandbox blocks»; новый блок `describe("addon-only code", …)` в конце файла)

**Interfaces:**
- Produces: `B.ADDON_OPEN = "--@addon"`, `B.ADDON_CLOSE = "--@end"`; `B.ADDON_SRC = { raid = true, gear_data = true, gear = true }`; `B.strip(code) -> code` (строки блока, маркеры включительно, — пустые; число строк то же; ошибка при незакрытом, вложенном или лишнем маркере); `B.bundle(srcDir, version, addon)` — `addon` ложно: без модулей `B.ADDON_SRC` и с `B.strip`; `B.initCode` — как раньше (аура); `B.addonCode` — `B.bundle(srcDir, version, true)`. `B.MODULES` = `util, spells_data, spells, talents, raid, gear_data, gear, swing, enemies, ttd, damage, model, value, search, planner, snapshot, timeline, recorder, version, runtime`.
- Produces (заготовки): `raid.DEBUFFS = {}`, `raid.BUFFS = {}`, `raid.OWN_TOTEMS = {}`, `raid.SUPPORT = { haste = 0.04, strength = 0.02 }`, `raid.effects(found, buffs, own, gearMods) -> nil`; `gear_data = { SETS = {}, BONUS = {}, RELICS = {}, GLYPHS = {} }`; `gear.effects(items, glyphs) -> nil`.

- [ ] **Step 1: Тесты.** В `spec/build_spec.lua` поправить порядок модулей:

```lua
  it("lists modules in the load order of the contract", function()
    assert.are.same({ "util", "spells_data", "spells", "talents", "raid", "gear_data", "gear", "swing", "enemies", "ttd",
                      "damage", "model", "value", "search", "planner", "snapshot", "timeline", "recorder", "version",
                      "runtime" }, build.MODULES)
    assert.are.equal("dist/DoubtMyRotation.txt", build.OUT)
  end)
```

«lists every source module and bundles code that compiles» — аура без модулей аддона, аддон со всеми:

```lua
  it("lists every source module and bundles code that compiles", function()
    local listed = {}
    for _, name in ipairs(build.MODULES) do listed[name] = true end
    for _, name in ipairs(srcModules()) do assert.is_true(listed[name] == true, "not in build.MODULES: " .. name) end
    local code = build.initCode("src")
    assert.is_not_nil(loadstring(code))
    local addon = build.bundle("src", nil, true)
    assert.is_not_nil(loadstring(addon))
    for _, name in ipairs(build.MODULES) do
      assert.are.equal(not build.ADDON_SRC[name], code:find('__mods["' .. name .. '"]', 1, true) ~= nil, name)
      assert.is_not_nil(addon:find('__mods["' .. name .. '"]', 1, true), name)
    end
  end)
```

«uses nothing the WeakAuras sandbox blocks» — и аддонная часть `src/`:

```lua
  it("uses nothing the WeakAuras sandbox blocks", function()
    assert.are.same({}, build.forbidden(build.bundle("src")))
    assert.are.same({}, build.forbidden(build.bundle("src", nil, true)))
  end)
```

Новый блок в конце файла:

```lua
describe("addon-only code", function()
  it("strip blanks the lines from --@addon to --@end, markers included, and keeps the line count", function()
    local code = "local a = 1\n--@addon\nlocal b = 2\n  --@end\nreturn a\n"
    assert.are.equal("local a = 1\n\n\n\nreturn a\n", build.strip(code))
    assert.are.equal("x\ny", build.strip("x\ny"))
  end)

  it("a marker is a whole line: a comment that only names one stays", function()
    local code = "x = 1 -- see --@addon below\n"
    assert.are.equal(code, build.strip(code))
  end)

  it("strip refuses an unclosed, a nested or a stray marker", function()
    assert.has_error(function() build.strip("--@addon\nx\n") end)
    assert.has_error(function() build.strip("x\n--@end\n") end)
    assert.has_error(function() build.strip("--@addon\n--@addon\n--@end\n") end)
  end)

  it("every source module still compiles without its addon blocks, line for line", function()
    for _, name in ipairs(build.MODULES) do
      if name ~= "version" then
        local raw = build.readFile("src/" .. name .. ".lua")
        local s = build.strip(raw)
        assert.is_not_nil(loadstring(s), name)
        assert.are.equal(select(2, raw:gsub("\n", "")), select(2, s:gsub("\n", "")), name)
      end
    end
  end)

  it("the aura gets neither addon-only modules nor addon blocks", function()
    local aura = build.bundle("src", "v0")
    for name in pairs(build.ADDON_SRC) do assert.is_nil(aura:find('__mods["' .. name .. '"]', 1, true), name) end
    assert.is_nil(aura:find("S.mods", 1, true))
  end)
end)
```

- [ ] **Step 2: Красный прогон.** `docker compose run --rm test busted spec/build_spec.lua` — падают новые тесты (`build.strip` нет, порядок модулей другой, `src/raid.lua` нет).

- [ ] **Step 3: Заготовки модулей.** `src/raid.lua`:

```lua
-- Raid debuffs on the target and what the group already gives (WotLK 3.3.5a), as S.mods
-- multipliers for damage / value. Addon only (tools/build.lua B.ADDON_SRC). Filled in by the
-- raid task of stage 2; until then nothing is found and S.mods stays nil.
local M = {}

M.DEBUFFS, M.BUFFS, M.OWN_TOTEMS = {}, {}, {}
-- value.SUPPORT (support totems' share of auto-attack damage) split by what each totem gives
M.SUPPORT = { haste = 0.04, strength = 0.02 }

function M.effects(found, buffs, own, gearMods)
  return nil
end

return M
```

`src/gear_data.lua`:

```lua
-- Enhancement equipment the model knows (WotLK 3.3.5a). Addon only (tools/build.lua B.ADDON_SRC).
-- Filled in by the gear task of stage 2.
return { SETS = {}, BONUS = {}, RELICS = {}, GLYPHS = {} }
```

`src/gear.lua`:

```lua
-- Equipment and glyphs -> S.mods additions (gear_data). Addon only (tools/build.lua B.ADDON_SRC).
-- Filled in by the gear task of stage 2; until then nothing is known.
local M = {}

function M.effects(items, glyphs)
  return nil
end

return M
```

- [ ] **Step 4: Реализация в `tools/build.lua`.** `B.MODULES`:

```lua
B.MODULES = { "util", "spells_data", "spells", "talents", "raid", "gear_data", "gear", "swing", "enemies", "ttd",
              "damage", "model", "value", "search", "planner", "snapshot", "timeline", "recorder", "version", "runtime" }
```

Под `B.MODULES`:

```lua
-- Addon-only code (AGENTS.md): whole lines from --@addon to --@end, markers included, and the
-- modules of B.ADDON_SRC go into the addon only. The aura gets blank lines in their place: line
-- numbers in errors still match src/, and the engine computes exactly as before them (the aura's
-- import string has no room left, B.MAX_IMPORT).
B.ADDON_OPEN, B.ADDON_CLOSE = "--@addon", "--@end"
B.ADDON_SRC = { raid = true, gear_data = true, gear = true }
```

Перед `B.bundle`:

```lua
function B.strip(code)
  local out, n, inside = {}, 0, false
  for line in (code .. "\n"):gmatch("(.-)\n") do
    local mark = line:match("^%s*(%-%-@%a+)%s*$")
    if mark == B.ADDON_OPEN then
      assert(not inside, "--@addon inside --@addon")
      inside, line = true, ""
    elseif mark == B.ADDON_CLOSE then
      assert(inside, "--@end without --@addon")
      inside, line = false, ""
    elseif inside then
      line = ""
    end
    n = n + 1
    out[n] = line
  end
  assert(not inside, "--@addon without --@end")
  return table.concat(out, "\n")
end
```

`B.bundle`:

```lua
-- src/version.lua в сборке заменяется строкой версии (version = nil: B.version()).
-- addon: the addon's bundle (every module, addon blocks kept); else the aura's (B.strip)
function B.bundle(srcDir, version, addon)
  version = version or B.version()
  local parts = {
    "local __mods = {}\n",
    "local function __require(name)\n  local m = __mods[name]\n  if m == nil then error('DoubtMyRotation: module not loaded: ' .. name) end\n  return m\nend\n",
  }
  for _, name in ipairs(B.MODULES) do
    if addon or not B.ADDON_SRC[name] then
      local code
      if name == "version" then
        code = ("return %q"):format(version)
      else
        code = B.readFile(srcDir .. "/" .. name .. ".lua")
        if not addon then code = B.strip(code) end
        code = B.minify(code)
      end
      parts[#parts + 1] = ('__mods["%s"] = (function(require)\n%s\nend)(__require)\n'):format(name, code)
    end
  end
  return table.concat(parts)
end
```

В `B.addonCode`: `local parts = { B.bundle(srcDir, version, true) }`.

- [ ] **Step 5: Зелёный прогон.** `docker compose run --rm test busted spec/build_spec.lua` — всё зелёное, в том числе «keeps the import string short enough» и «runs as a WeakAuras init action and draws a plan». Сборка: `docker compose run --rm test lua tools/build.lua` — размер строки ауры в выводе (было 62 152) записать в отчёт; он должен остаться прежним с точностью до байт.

- [ ] **Step 6: Весь набор.** `docker compose run --rm test busted --exclude-tags=perf` — зелёный.

- [ ] **Step 7: Коммит.**

```bash
git add tools/build.lua src/raid.lua src/gear_data.lua src/gear.lua spec/build_spec.lua
git commit -m "Точность: код и модули только для аддона — сборка ауры вырезает блоки --@addon и модули B.ADDON_SRC"
```

---
### Task 2: Пинг — медиана `SENT` → `START` / `SUCCEEDED` за сессию

Сейчас `S.latency = GetNetStats() / 1000 + 0.1` (`snapshot.build` ~449): «домашняя» задержка 3.3.5a обновляется раз в 30 с и не включает обработку на сервере, +0,1 — догадка за неё. `runtime.onCast` уже ловит нажатие (`SENT`) и ответ сервера (`START` для каста, `SUCCEEDED` для мгновенного, окно `SENT_WINDOW = 1` с): их разница — то, что нажатие на самом деле стоит, вместе с тиком сервера. Значение `S.latency` модель использует как «каст заканчивается на сервере через castTime + latency после нажатия» (`model` ~1163, ~1250; `search` ~124; `timeline` ~55) — смысл тот же.

**Files:**
- Modify: `src/snapshot.lua` (новые `M.PING_N`, `M.PING_MIN`, `M.addPing`, `M.latency` над `M.build`; `M.build` ~449–450)
- Modify: `src/runtime.lua` (`M.onCast` ~222–226; `ctx` в `M.start` ~765)
- Test: `spec/snapshot_spec.lua` (рядом с «reads the current cast, latency and player stats» ~461), `spec/runtime_spec.lua` (рядом с «takes the press from SENT…» ~673)

**Interfaces:**
- Produces: `snapshot.PING_N = 15`, `snapshot.PING_MIN = 3`; `snapshot.addPing(ping, dt)` — `ping = { n, i, median, [1..PING_N] }` (кольцо последних `PING_N` проб, `median` пересчитывается при добавлении; `dt < 0` — не проба); `snapshot.latency(ping, netMs) -> seconds` — медиана при `ping.n >= PING_MIN`, иначе `netMs / 1000 + 0.1`; `ctx.ping` (создаёт `runtime.start`, `{ n = 0, i = 0 }`).

- [ ] **Step 1: Тесты `spec/snapshot_spec.lua`.** Старый тест «reads the current cast, latency…» не трогать (без проб — прежние 0,18). Рядом:

```lua
  -- the latency is measured: the median gap between a press (SENT) and the server's answer
  it("latency: GetNetStats + 0.1 until PING_MIN presses are measured, then their median", function()
    install({ latencyMs = 80 })
    local ping = { n = 0, i = 0 }
    assert.are.near(0.18, snapshot.build(ctx({ ping = ping })).latency, 1e-9)
    snapshot.addPing(ping, 0.30)
    snapshot.addPing(ping, 0.12)
    assert.are.near(0.18, snapshot.build(ctx({ ping = ping })).latency, 1e-9) -- 2 < PING_MIN
    snapshot.addPing(ping, 0.20)
    assert.are.near(0.20, snapshot.build(ctx({ ping = ping })).latency, 1e-9)
    snapshot.addPing(ping, 0.90) -- one outlier: 0.12 0.20 0.30 0.90
    assert.are.near(0.25, snapshot.build(ctx({ ping = ping })).latency, 1e-9)
  end)

  it("addPing keeps the last PING_N samples and ignores a negative gap", function()
    local ping = { n = 0, i = 0 }
    for k = 1, snapshot.PING_N + 5 do snapshot.addPing(ping, k / 100) end
    assert.are.equal(snapshot.PING_N, ping.n)
    assert.are.near(0.13, ping.median, 1e-9) -- the 15 newest: 0.06 .. 0.20
    snapshot.addPing(ping, -0.5)
    assert.are.near(0.13, ping.median, 1e-9)
  end)
```

- [ ] **Step 2: Тест `spec/runtime_spec.lua`.** После «a hard cast confirmed by START after SENT is no second press»:

```lua
  -- one sample per press: SENT -> SUCCEEDED of an instant, SENT -> START of a cast (its SUCCEEDED
  -- is no second sample); a press without SENT or a FAILED one gives none
  it("measures the round trip of each confirmed press, once per press", function()
    local rt = start(nil, { casting = { name = "Lightning Bolt", startMs = 100120, endMs = 102620, castID = 7 } })
    runtime.onEvent(rt, "UNIT_SPELLCAST_SENT", "player", "Earth Shock", "Rank 10", "Mob")
    G.cfg.now = 100.12
    runtime.onEvent(rt, "UNIT_SPELLCAST_SUCCEEDED", "player", "Earth Shock", "Rank 10")
    runtime.onEvent(rt, "UNIT_SPELLCAST_SENT", "player", "Lightning Bolt", "Rank 14", "Mob")
    G.cfg.now = 100.30
    runtime.onEvent(rt, "UNIT_SPELLCAST_START", "player", "Lightning Bolt", "Rank 14", 7)
    G.cfg.now = 102.80
    runtime.onEvent(rt, "UNIT_SPELLCAST_SUCCEEDED", "player", "Lightning Bolt", "Rank 14", 7)
    runtime.onEvent(rt, "UNIT_SPELLCAST_SUCCEEDED", "player", "Earth Shock", "Rank 10") -- no SENT
    runtime.onEvent(rt, "UNIT_SPELLCAST_SENT", "player", "Stormstrike", "", "Mob")
    runtime.onEvent(rt, "UNIT_SPELLCAST_FAILED", "player", "Stormstrike", "")
    assert.are.equal(2, rt.ctx.ping.n)
    assert.are.near(0.12, rt.ctx.ping[1], 1e-9)
    assert.are.near(0.18, rt.ctx.ping[2], 1e-9)
  end)
```

- [ ] **Step 3: Красный прогон.** `docker compose run --rm test busted spec/snapshot_spec.lua spec/runtime_spec.lua` — новые тесты падают (`addPing` нет, `ctx.ping` нет).

- [ ] **Step 4: Реализация в `src/snapshot.lua`.** Над `M.build`:

```lua
-- Latency: the median gap between a press (UNIT_SPELLCAST_SENT) and the server's answer (START of
-- a cast, SUCCEEDED of an instant) over the session's last PING_N presses (runtime.onCast). That
-- is what a press really takes, the server's tick included. GetNetStats is the home latency the
-- client refreshes every 30 s, without the server's part; + 0.1 stood in for it, and still does
-- until PING_MIN presses are measured. The median: one lag spike moves it little.
M.PING_N, M.PING_MIN = 15, 3

function M.addPing(p, dt)
  if dt < 0 then return end
  local n = p.n or 0
  local i = (p.i or 0) % M.PING_N + 1
  p.i, p[i] = i, dt
  if n < M.PING_N then n = n + 1; p.n = n end
  local s = {}
  for k = 1, n do s[k] = p[k] end
  table.sort(s)
  local m = math.floor((n + 1) / 2)
  p.median = n % 2 == 1 and s[m] or (s[m] + s[m + 1]) / 2
end

function M.latency(p, netMs)
  if p and (p.n or 0) >= M.PING_MIN then return p.median end
  return (netMs or 0) / 1000 + 0.1
end
```

В `M.build`:

```lua
  local _, _, latMs = GetNetStats()
  S.latency = M.latency(ctx.ping, latMs)
```

- [ ] **Step 5: Реализация в `src/runtime.lua`.** В `M.onCast` заменить блок подтверждения:

```lua
  local confirmed = sentFor(rt, key, now)
  if confirmed and (event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_SUCCEEDED") then
    -- the round trip of this press (snapshot.latency); START clears rt.sent, so the cast's
    -- SUCCEEDED later is no second sample
    if ctx.ping then snapshot.addPing(ctx.ping, now - rt.sent.at) end
    if rt.rec then rt.rec:confirm(key) end
  end
```

В `ctx` из `M.start` добавить `ping = { n = 0, i = 0 }` (рядом с `inflight = {}`).

- [ ] **Step 6: Зелёный прогон и размер.** `docker compose run --rm test busted spec/snapshot_spec.lua spec/runtime_spec.lua spec/build_spec.lua` — зелёные. `docker compose run --rm test lua tools/build.lua` — записать размер строки ауры. Если вместе с задачей 1 он выйдет за `B.MAX_IMPORT` (тест «keeps the import string short enough» красный после слияния волны 1) — обернуть строки `M.addPing`/`M.latency`-вызова, `ctx.ping` и проб в `--@addon` … `--@end`, а в `M.build` оставить в ауре прежнюю строку: `S.latency = (latMs or 0) / 1000 + 0.1` над блоком `--@addon S.latency = M.latency(ctx.ping, latMs) --@end`; сказать в отчёте.

- [ ] **Step 7: Весь набор и коммит.** `docker compose run --rm test busted --exclude-tags=perf` — зелёный.

```bash
git add src/snapshot.lua src/runtime.lua spec/snapshot_spec.lua spec/runtime_spec.lua
git commit -m "Точность: задержка — медиана от нажатия до ответа сервера за сессию вместо GetNetStats + 0.1"
```

---
### Task 3: `S.mods` рейда в формулах — `damage`, `model`, `value`

Что тесты предполагают сейчас: `Sc.state(80)` и `fixtures.state` — цель 83 уровня с полной бронёй 10 643 (`damage.BOSS_ARMOR`), без +13% к заклинаниям, +3% крита, +4% физического; характеристики игрока (4000 AP, 1200 SP, 29% / 21% крита) — это лист персонажа, т. е. баффы рейда на игроке в них уже как бы есть. wowsims гоняет свой APL энха с `FullDebuffs`, т. е. наши случаи сверяют с приоритетом, настроенным под дебаффы, на цели без дебаффов. Эта задача только учит формулы `S.mods`; случаи с дебаффами — задача 9.

**Files:**
- Modify: `src/damage.lua` (`M.spellHit` ~55, `M.spellCritFactor` ~64, `spellDamage` ~85, `M.armorMult` ~104, `M.meleeTable` ~127, `M.ftHit` ~171, `M.dot` ~322, `M.periodic` ~341, `M.action` lavaLash ~369, `M.tableCv2` ~480)
- Modify: `src/model.lua` (`M.cloneState` ~220, `fillState` ~248, заполнение рабочей копии ~1000 — блок «fields the model never changes»)
- Modify: `src/value.lua` (`autoValue` ~288–296)
- Test: `spec/damage_spec.lua` (новый `describe("S.mods (addon)", …)`), `spec/model_spec.lua` (`states()` ~872 и новый тест рядом с «an arena state carries exactly cloneState's fields»), `spec/value_spec.lua` (рядом с «support totems…» ~318)

**Interfaces:**
- Consumes: `S.mods` — поля `armor`, `spellTaken`, `physTaken`, `critTaken`, `spellCritTaken`, `spellHitTaken`, `support` (раздел «Решения»).
- Produces: `damage.spellCrit(S) -> chance` (крит заклинаний против цели, с `S.mods`; его же читает `tableCv2`); `damage.armorMult` — множитель физического урона: броня с `mods.armor` и `mods.physTaken`; копии состояния (`cloneState`, арена, рабочие копии) несут ту же ссылку `S.mods`.

- [ ] **Step 1: Тесты `spec/damage_spec.lua`.** В конце файла:

```lua
describe("S.mods (addon: raid debuffs on the target)", function()
  local NEUTRAL = { armor = 1, spellTaken = 1, physTaken = 1, critTaken = 0, spellCritTaken = 0, spellHitTaken = 0 }
  local function full(o)
    local S = s80(o)
    S.talents = { staticShock = 3, elementalWeapons = 3, concussion = 5, elementalFury = 5 }
    S.buffs.ls = { charges = 3, remains = 600 }
    S.spells.stormstrike = { id = 17364, rank = 1, cd = 0, cost = 351, cast = 0 }
    S.spells.lavaLash = { id = 60103, rank = 1, cd = 0, cost = 176, cast = 0 }
    return S
  end
  local KEYS = { "stormstrike", "lavaLash", "earthShock", "flameShock", "lightningBolt", "chainLightning", "fireNova" }

  it("neutral mods change nothing, bit for bit", function()
    local a, b = full(), full({ mods = NEUTRAL })
    for _, key in ipairs(KEYS) do assert.are.equal(damage.action(a, key), damage.action(b, key), key) end
    for _, src in ipairs(damage.PERIODIC) do assert.are.equal(damage.periodic(a, src), damage.periodic(b, src), src) end
    assert.are.equal(damage.auto(a, "mh"), damage.auto(b, "mh"))
    assert.are.equal(damage.auto(a, "oh"), damage.auto(b, "oh"))
    assert.are.equal(damage.tableCv2(a, "spell"), damage.tableCv2(b, "spell"))
    assert.are.equal((damage.dot(a, "flameShock")), (damage.dot(b, "flameShock")))
  end)

  it("armor: Sunder Armor and Faerie Fire multiply the target's armor", function()
    local S = s80({ mods = { armor = 0.8 * 0.95 } })
    local a = 10643 * 0.8 * 0.95
    assert.are.near(1 - a / (a + 15232.5), damage.armorMult(S), 1e-12)
  end)

  it("physical damage taken (Blood Frenzy) scales every physical hit, not Lava Lash (fire)", function()
    local a, b = full(), full({ mods = { physTaken = 1.04 } })
    assert.are.near(1.04, damage.white(b, "mh") / damage.white(a, "mh"), 1e-12)
    assert.are.near(1.04, damage.periodic(b, "feralSpirit") / damage.periodic(a, "feralSpirit"), 1e-12)
    assert.are.equal(damage.action(a, "lavaLash"), damage.action(b, "lavaLash"))
  end)

  it("spell damage taken (Curse of the Elements) scales shocks, Bolt, totems, Flametongue and Lava Lash", function()
    local a, b = full(), full({ mods = { spellTaken = 1.13 } })
    for _, key in ipairs({ "earthShock", "lightningBolt", "fireNova", "lavaLash" }) do
      assert.are.near(1.13, damage.action(b, key) / damage.action(a, key), 1e-12, key)
    end
    assert.are.near(1.13, damage.ftHit(b, "oh") / damage.ftHit(a, "oh"), 1e-12)
    assert.are.near(1.13, damage.periodic(b, "flameShock") / damage.periodic(a, "flameShock"), 1e-12)
    assert.are.near(1.13, damage.periodic(b, "fireElemental") / damage.periodic(a, "fireElemental"), 1e-12)
    -- Stormstrike: the weapon part is physical, only its Flametongue / Static Shock procs grow
    local ss = damage.action(b, "stormstrike") / damage.action(a, "stormstrike")
    assert.is_true(ss > 1 and ss < 1.13, tostring(ss))
  end)

  it("crit taken (Totem of Wrath) adds to melee and spell crit, spell crit taken (Improved Scorch) to spells only", function()
    local S = s80({ mods = { critTaken = 0.03, spellCritTaken = 0.05 } })
    assert.are.near(0.252 + 0.03, damage.meleeTable(S, true).crit, 1e-9)
    assert.are.near(0.20 + 0.03 + 0.05, damage.spellCrit(S), 1e-12)
    assert.are.near(1 + 0.28 * 0.5, damage.spellCritFactor(S), 1e-12)
  end)

  it("spell hit taken (Misery) closes the spell miss chance", function()
    assert.are.near(0.93, damage.spellHit(s80()), 1e-12)
    assert.are.near(0.96, damage.spellHit(s80({ mods = { spellHitTaken = 0.03 } })), 1e-12)
  end)
end)
```

- [ ] **Step 2: Тесты `spec/model_spec.lua`.** В `states()` (~874) добавить в список состояние с дебаффами — его прогоняют тесты «peekApply and peekWait give exactly what apply and wait give», «peeks of the same state…», «peekApplyOver…»:

```lua
                           { mods = { armor = 0.76, spellTaken = 1.13, physTaken = 1.04, critTaken = 0.03,
                                      spellCritTaken = 0.05, spellHitTaken = 0.03, support = 0.02 } },
```

Рядом с «an arena state carries exactly cloneState's fields» (сам тест-«часовой» поймает `mods`, забытый в `fillState`):

```lua
  it("S.mods (raid debuffs, gear) is one shared table in every copy: new, arena, peeked", function()
    local S = fixtures.state()
    S.mods, S.memo = { spellTaken = 1.13 }, {}
    local mods = S.mods
    assert.are.equal(mods, model.cloneState(S).mods)
    assert.are.equal(mods, (model.apply(S, "stormstrike")).mods)
    assert.are.equal(mods, model.peekApply(S, "stormstrike").mods)
    assert.are.equal(mods, model.peekWait(S, 0.5).mods)
    S.memo = { arena = model.newArena() }
    assert.are.equal(mods, model.clone(S).mods)
    model.release(S.memo.arena)
  end)
```

- [ ] **Step 3: Тест `spec/value_spec.lua`.** После «support totems (the water slot stands for the set)…»:

```lua
  -- the group gives part of what our totems give (raid.lua: Horn of Winter, another Windfury
  -- Totem, Improved Icy Talons): our set is worth only the rest, S.mods.support
  it("support totems the group already covers are worth only S.mods.support", function()
    local function at(remains, mods)
      local S = base({ totems = { fire = { kind = false, remains = 0 }, water = { remains = remains } } })
      S.mods = mods
      return S
    end
    local long = at(200)
    local dps = damage.auto(long, "mh") / long.swing.mh.speed + damage.auto(long, "oh") / long.swing.oh.speed
    local m = { support = 0.02 }
    assert.are.near((value.TAIL - 2) * 0.02 * dps * value.DISCOUNT, value.terminal(at(200, m)) - value.terminal(at(2, m)), 1e-6)
    m = { support = 0 }
    assert.are.near(0, value.terminal(at(200, m)) - value.terminal(at(2, m)), 1e-6)
    -- other mods leave the share alone
    assert.are.equal(value.terminal(at(200)), value.terminal(at(200, { armor = 0.76 })))
  end)
```

Последняя проверка идёт на заглушке `damage` (`stubs.damage`, `S.mods` она не читает) — она проверяет только `value`.

- [ ] **Step 4: Красный прогон.** `docker compose run --rm test busted spec/damage_spec.lua spec/model_spec.lua spec/value_spec.lua` — новые тесты падают (`damage.spellCrit` нет, `mods` не копируется, `support` не читается).

- [ ] **Step 5: Реализация в `src/damage.lua`.** Каждая вставка — блок `--@addon` … `--@end` целыми строками; старое выражение не меняется, множитель — отдельной строкой.

Над `M.spellHit` — комментарий модуля к `S.mods`:

```lua
-- S.mods (addon only, raid.lua / gear.lua via snapshot): raid debuffs on the target and the
-- equipment, read-only and the same in every state of one search, so the memos below stay valid.
-- Every field is optional; without S.mods (the aura, tests) everything is as before, bit for bit.
```

`M.spellHit` — последние строки:

```lua
  local hit = S.player.spellHit or 0
  --@addon
  local mods = S.mods
  if mods and mods.spellHitTaken then hit = hit + mods.spellHitTaken end
  --@end
  return 1 - math.max(0, miss - hit)
```

`M.spellCritFactor` и новая `M.spellCrit`:

```lua
-- spell crit chance against this target: the character's, plus the target's debuffs (S.mods)
function M.spellCrit(S)
  local c = S.player.spellCrit or 0
  --@addon
  local mods = S.mods
  if mods then c = c + (mods.critTaken or 0) + (mods.spellCritTaken or 0) end
  --@end
  return util.clamp(c, 0, 1)
end

function M.spellCritFactor(S)
  local mult = 1.5 + 0.1 * talent(S, "elementalFury")
  return 1 + M.spellCrit(S) * (mult - 1)
end
```

`spellDamage`:

```lua
local function spellDamage(S, key, row)
  if not row then return 0 end
  local base = (row.min + row.max) / 2 + (row.coef or 0) * spellPower(S, SCHOOL[key])
  local v = base * M.spellMult(S, key) * M.spellHit(S) * M.spellCritFactor(S)
  --@addon
  local mods = S.mods
  if mods and mods.spellTaken then v = v * mods.spellTaken end
  --@end
  return v
end
```

`M.armorMult` (комментарий: «physical damage multiplier: armor, and physical damage taken»):

```lua
function M.armorMult(S)
  local armor = S.target.armor or M.targetArmor(S.target.level)
  --@addon
  local mods = S.mods
  if mods and mods.armor then armor = armor * mods.armor end
  --@end
  local L = S.player.level
  local k
  if L >= 60 then k = 400 + 85 * (L + 4.5 * (L - 59)) else k = 400 + 85 * L end
  local m = 1 - armor / (armor + k)
  --@addon
  -- every hit armor applies to is physical (white, Windfury, Stormstrike, wolves): Blood Frenzy too
  if mods and mods.physTaken then m = m * mods.physTaken end
  --@end
  return m
end
```

`M.meleeTable` — строка крита:

```lua
  local mc = S.player.meleeCrit or 0
  --@addon
  local mods = S.mods
  if mods and mods.critTaken then mc = mc + mods.critTaken end
  --@end
  local crit = math.max(0, mc - (d >= 3 and 0.048 or 0.002 * dp))
```

`M.ftHit` — конец:

```lua
  local v = dmg * M.spellHit(S) * M.spellCritFactor(S)
  --@addon
  local mods = S.mods
  if mods and mods.spellTaken then v = v * mods.spellTaken end
  --@end
  return v
```

`M.dot`, ветка `flameShock` — после `local per = …`:

```lua
    --@addon
    local mods = S.mods
    if mods and mods.spellTaken then per = per * mods.spellTaken end
    --@end
```

`M.periodic`, ветка `fireElemental` (стихиаль бьёт в основном огнём; его ближний бой — упрощение):

```lua
  elseif source == "fireElemental" then
    local v = (M.FE_BASE_DPS + M.FE_SP * (S.player.spFire or 0)) * (1 + 0.05 * talent(S, "callOfFlame"))
    --@addon
    local mods = S.mods
    if mods and mods.spellTaken then v = v * mods.spellTaken end
    --@end
    return v
```

`M.action`, ветка `lavaLash` (Lava Lash — огонь: броня не действует, Curse of the Elements — да):

```lua
    local wpn = M.normalized(S, "oh") * bonus * y.factor
    --@addon
    local mods = S.mods
    if mods and mods.spellTaken then wpn = wpn * mods.spellTaken end
    --@end
    return wpn + procsPerHit(S, "oh") * y.landed
```

`M.tableCv2`, ветка `spell`: `local c = M.spellCrit(S)` вместо `util.clamp(S.player.spellCrit or 0, 0, 1)`.

- [ ] **Step 6: Реализация в `src/model.lua`.** `S.mods` — общая ссылка, как `S.enemies`. В `M.cloneState` в конструктор отдельной строкой после строки с `cooldowns = …`:

```lua
    --@addon
    mods = S.mods,
    --@end
```

В `fillState` после `n.cooldowns, n.cdAllowed, n.weaveMin, n.memo = …`:

```lua
  --@addon
  n.mods = S.mods
  --@end
```

В заполнении рабочей копии, в блоке `if not same then` после `n.weaveMin = S.weaveMin`:

```lua
    --@addon
    n.mods = S.mods
    --@end
```

- [ ] **Step 7: Реализация в `src/value.lua`.** В `autoValue`:

```lua
  local water = S.totems and S.totems.water
  if water and (water.remains or 0) > 0 then
    local dps = (amh > 0 and amh / mh.speed or 0) + (aoh > 0 and aoh / oh.speed or 0)
    local left = water.remains > M.TAIL and M.TAIL or water.remains -- lifetime(S, water.remains)
    local ttd = S.target.ttd
    if ttd and ttd < left then left = ttd end
    if left < 0 then left = 0 end
    local support = M.SUPPORT
    --@addon
    -- what the group does not already give (raid.lua: Horn of Winter, another Windfury Totem...)
    local mods = S.mods
    if mods and mods.support then support = mods.support end
    --@end
    v = v + left * support * dps * M.DISCOUNT
  end
```

- [ ] **Step 8: Зелёный прогон.** `docker compose run --rm test busted spec/damage_spec.lua spec/model_spec.lua spec/value_spec.lua` — зелёные. Затем бит в бит без `S.mods`: `docker compose run --rm test busted spec/recorded_spec.lua spec/wowsims_spec.lua spec/leveling_spec.lua spec/search_spec.lua` — зелёные без правок ожиданий; `docker compose run --rm test busted --tags=perf` — в лимитах (числа инструкций и мусора записать в отчёт, сравнить с `main`: не больше чем на 1%).

- [ ] **Step 9: Размер.** `docker compose run --rm test lua tools/build.lua` — до слияния с задачей 1 блоки ещё не вырезаются, строка ауры вырастет; она должна остаться ≤ `B.MAX_IMPORT` (тест в `spec/build_spec.lua`). Записать размер в отчёт.

- [ ] **Step 10: Весь набор и коммит.** `docker compose run --rm test busted --exclude-tags=perf` — зелёный.

```bash
git add src/damage.lua src/model.lua src/value.lua spec/damage_spec.lua spec/model_spec.lua spec/value_spec.lua
git commit -m "Точность: дебаффы рейда на цели в формулах урона (S.mods) — броня, урон заклинаниями и физический, крит, меткость; доля тотемов поддержки"
```

---
### Task 4: Модуль `raid` — дебаффы цели и что группа уже даёт

**Files:**
- Modify: `src/raid.lua` (заготовка задачи 1 → полный модуль)
- Create: `spec/raid_spec.lua`

**Interfaces:**
- Consumes: формат `snapshot.auras` — `key -> { count, remains }`; виды своих тотемов — `{ earth = kind, air = kind }`, `kind` из `M.OWN_TOTEMS`, `"other"` или `nil`; `gearMods` — результат `gear.effects` или `nil`.
- Produces: `raid.DEBUFFS` (id → ключ), `raid.EFFECT` (ключ → `{ категория, величина, макс. стаков | nil }`), `raid.BUFFS` (id → ключ), `raid.OWN_TOTEMS` (id → `"strength"` / `"haste"`), `raid.SUPPORT = { haste = 0.04, strength = 0.02 }`, `raid.effects(found, buffs, own, gearMods) -> mods | nil` (поля — раздел «Решения»; поля `gearMods` копируются как есть).

Id и имена (3.3.5a; сверка в игре — задача 12, пункт «id»). Сверяются по имени: `GetSpellInfo(id)` должно давать имя **ауры на цели / на игроке**.

| Ключ | id | Имя ауры | Категория, величина | Источник |
|---|---|---|---|---|
| `sunder` | 7386 | Sunder Armor | броня, крупная: 4% за стак, до 5 | `SunderArmorAura` |
| `expose` | 8647 | Expose Armor | броня, крупная: 20% | `ExposeArmorAura` |
| `acidSpit` | 55749 | Acid Spit | броня, крупная: 10% за стак, до 2 | `AcidSpitAura` |
| `faerieFire` | 770 | Faerie Fire | броня, малая: 5% | `FaerieFireAura` |
| `faerieFireFeral` | 16857 | Faerie Fire (Feral) | броня, малая: 5% | там же |
| `sting` | 56631 | Sting | броня, малая: 5% | `StingAura` |
| `curseOfWeakness` | 702 | Curse of Weakness | броня, малая: 5% | `CurseOfWeaknessAura` |
| `sporeCloud` | 53598 | Spore Cloud | броня, малая: 3% | `SporeCloudAura` |
| `elements` | 1490 | Curse of the Elements | заклинания: +13% | `CurseOfElementsAura` |
| `ebonPlague` | 51726 | Ebon Plague | заклинания: +13% (3/3) | `EbonPlaguebringerOrCryptFeverAura` |
| `earthAndMoon` | 60431 | Earth and Moon | заклинания: +13% (3/3) | `EarthAndMoonAura` |
| `totemOfWrath` | 30708 | Totem of Wrath | крит: +3% | `TotemOfWrathDebuff` |
| `heartOfTheCrusader` | 21183 | Heart of the Crusader | крит: +3% (3/3) | `HeartOfTheCrusaderDebuff` |
| `masterPoisoner` | 58410 | Master Poisoner | крит: +3% (3/3) | `MasterPoisonerDebuff` |
| `bloodFrenzy` | 30069 | Blood Frenzy | физический: +4% (2/2) | `BloodFrenzyAura` |
| `savageCombat` | 58683 | Savage Combat | физический: +4% (2/2) | `SavageCombatAura` |
| `improvedScorch` | 22959 | Improved Scorch | крит заклинаний: +5% | `ImprovedScorchAura` |
| `wintersChill` | 12579 | Winter's Chill | крит заклинаний: 1% за стак, до 5 | `WintersChillAura` |
| `shadowMastery` | 17800 | Shadow Mastery | крит заклинаний: +5% | `ShadowMasteryAura` |
| `misery` | 33198 | Misery | меткость заклинаний: +3% | `MiseryAura` |

Баффы игрока: `hornOfWinter` 57330 «Horn of Winter», `strengthOfEarth` 8076 «Strength of Earth», `windfuryTotem` 8512 «Windfury Totem», `icyTalons` 55610 «Improved Icy Talons». Свои тотемы (`GetTotemInfo`): 8075 «Strength of Earth Totem» → `strength`, 8512 «Windfury Totem» → `haste`.

- [ ] **Step 1: Тест `spec/raid_spec.lua`.**

```lua
local raid = require("raid")

local function on(count) return { count = count or 0, remains = 20 } end

describe("raid", function()
  it("nothing found: no S.mods (the engine runs as without the addon)", function()
    assert.is_nil(raid.effects(nil, nil, nil, nil))
    assert.is_nil(raid.effects({}, {}, {}, nil))
    assert.is_nil(raid.effects({ unknown = on() }, { other = on() }, { earth = "other", air = "other" }, nil))
  end)

  -- wowsims FullDebuffs (sim/core/test_utils.go), the raid of their enhancement tests
  it("the wowsims full raid", function()
    local m = raid.effects({ sunder = on(5), expose = on(), faerieFire = on(), elements = on(), ebonPlague = on(),
                             earthAndMoon = on(), totemOfWrath = on(), heartOfTheCrusader = on(), bloodFrenzy = on(),
                             improvedScorch = on(), shadowMastery = on(), misery = on() }, {}, {}, nil)
    assert.are.near(0.8 * 0.95, m.armor, 1e-12)
    assert.are.near(1.13, m.spellTaken, 1e-12)
    assert.are.near(1.04, m.physTaken, 1e-12)
    assert.are.near(0.03, m.critTaken, 1e-12)
    assert.are.near(0.05, m.spellCritTaken, 1e-12)
    assert.are.near(0.03, m.spellHitTaken, 1e-12)
    assert.is_nil(m.support)
  end)

  it("Sunder Armor counts per stack up to 5; a debuff without a count is one stack", function()
    assert.are.near(1 - 0.12, raid.effects({ sunder = on(3) }).armor, 1e-12)
    assert.are.near(0.8, raid.effects({ sunder = on(9) }).armor, 1e-12)
    assert.are.near(0.96, raid.effects({ sunder = on(0) }).armor, 1e-12)
    assert.are.near(0.9, raid.effects({ acidSpit = on(1) }).armor, 1e-12)
  end)

  it("within a category the strongest only; categories multiply", function()
    assert.are.near(0.8, raid.effects({ sunder = on(2), expose = on() }).armor, 1e-12)
    assert.are.near(0.95, raid.effects({ sting = on(), faerieFire = on(), sporeCloud = on() }).armor, 1e-12)
    assert.are.near(0.92 * 0.95, raid.effects({ sunder = on(2), curseOfWeakness = on() }).armor, 1e-12)
    assert.are.near(0.03, raid.effects({ wintersChill = on(3) }).spellCritTaken, 1e-12)
    assert.are.near(0.05, raid.effects({ wintersChill = on(3), improvedScorch = on() }).spellCritTaken, 1e-12)
    assert.are.near(1.13, raid.effects({ elements = on(), ebonPlague = on(), earthAndMoon = on() }).spellTaken, 1e-12)
  end)

  it("support: Horn of Winter covers Strength of Earth, Improved Icy Talons covers Windfury Totem", function()
    assert.are.near(raid.SUPPORT.haste, raid.effects({}, { hornOfWinter = on() }, {}).support, 1e-12)
    assert.are.near(raid.SUPPORT.strength, raid.effects({}, { icyTalons = on() }, {}).support, 1e-12)
    assert.are.equal(0, raid.effects({}, { hornOfWinter = on(), icyTalons = on() }, {}).support)
  end)

  -- the buff of our own totem is on us too: someone else's counts only while ours is not the one up
  it("another shaman's totem covers ours only while ours of that element is not up", function()
    assert.is_nil(raid.effects({}, { windfuryTotem = on() }, { air = "haste" }))
    assert.are.near(raid.SUPPORT.strength, raid.effects({}, { windfuryTotem = on() }, { air = "other" }).support, 1e-12)
    assert.are.near(raid.SUPPORT.strength, raid.effects({}, { windfuryTotem = on() }, {}).support, 1e-12)
    assert.is_nil(raid.effects({}, { strengthOfEarth = on() }, { earth = "strength" }))
    assert.are.near(raid.SUPPORT.haste, raid.effects({}, { strengthOfEarth = on() }, { earth = "other" }).support, 1e-12)
  end)

  it("the gear's mods are carried over, alone or with the debuffs", function()
    assert.are.same({ ssFlat = 155 }, raid.effects({}, {}, {}, { ssFlat = 155 }))
    local m = raid.effects({ elements = on() }, {}, {}, { ssFlat = 155 })
    assert.are.equal(155, m.ssFlat)
    assert.are.near(1.13, m.spellTaken, 1e-12)
  end)

  it("every debuff id has an effect and every effect an id; the support split adds up to value.SUPPORT", function()
    local keys = {}
    for id, key in pairs(raid.DEBUFFS) do
      assert.is_number(id)
      assert.is_table(raid.EFFECT[key], key)
      keys[key] = true
    end
    for key in pairs(raid.EFFECT) do assert.is_true(keys[key] == true, key) end
    assert.are.near(require("value").SUPPORT, raid.SUPPORT.haste + raid.SUPPORT.strength, 1e-12)
  end)
end)
```

- [ ] **Step 2: Красный прогон.** `docker compose run --rm test busted spec/raid_spec.lua` — падает (заготовка возвращает `nil`).

- [ ] **Step 3: Реализация `src/raid.lua`.**

```lua
-- Raid debuffs on the target and what the group already gives (WotLK 3.3.5a) -> S.mods.
-- Categories and numbers: wowsims sim/core/debuffs.go. Within one category only the strongest
-- counts (two major armor debuffs do not add up); categories multiply. Matched by name: snapshot
-- turns these ids into the client's names (GetSpellInfo), so an id must give the name of the aura
-- on the unit, not the talent's (Ebon Plaguebringer puts "Ebon Plague" on the target). The talent
-- ranks behind a debuff are not in the aura: a raid takes them maxed, the maximum is assumed.
-- Improved Faerie Fire (+3% spell hit) cannot be told from plain Faerie Fire: armor only.
-- Addon only (tools/build.lua B.ADDON_SRC).
local M = {}

-- target debuffs, any caster: spell id -> key
M.DEBUFFS = {
  [7386] = "sunder", [8647] = "expose", [55749] = "acidSpit",
  [770] = "faerieFire", [16857] = "faerieFireFeral", [56631] = "sting", [702] = "curseOfWeakness",
  [53598] = "sporeCloud",
  [1490] = "elements", [51726] = "ebonPlague", [60431] = "earthAndMoon",
  [30708] = "totemOfWrath", [21183] = "heartOfTheCrusader", [58410] = "masterPoisoner",
  [30069] = "bloodFrenzy", [58683] = "savageCombat",
  [22959] = "improvedScorch", [12579] = "wintersChill", [17800] = "shadowMastery",
  [33198] = "misery",
}
-- key -> { category, amount, stacks: amount per stack up to this many (nil: flat) }
M.EFFECT = {
  sunder = { "armorMajor", 0.04, 5 }, expose = { "armorMajor", 0.20 }, acidSpit = { "armorMajor", 0.10, 2 },
  faerieFire = { "armorMinor", 0.05 }, faerieFireFeral = { "armorMinor", 0.05 }, sting = { "armorMinor", 0.05 },
  curseOfWeakness = { "armorMinor", 0.05 }, sporeCloud = { "armorMinor", 0.03 },
  elements = { "spell", 0.13 }, ebonPlague = { "spell", 0.13 }, earthAndMoon = { "spell", 0.13 },
  totemOfWrath = { "crit", 0.03 }, heartOfTheCrusader = { "crit", 0.03 }, masterPoisoner = { "crit", 0.03 },
  bloodFrenzy = { "phys", 0.04 }, savageCombat = { "phys", 0.04 },
  improvedScorch = { "spellCrit", 0.05 }, wintersChill = { "spellCrit", 0.01, 5 }, shadowMastery = { "spellCrit", 0.05 },
  misery = { "spellHit", 0.03 },
}
-- buffs on the player that do what our own support totems do (any caster)
M.BUFFS = { [57330] = "hornOfWinter", [8076] = "strengthOfEarth", [8512] = "windfuryTotem", [55610] = "icyTalons" }
-- our own earth and air totems (GetTotemInfo names): while ours stands, its buff on us is ours
M.OWN_TOTEMS = { [8075] = "strength", [8512] = "haste" }
-- value.SUPPORT (0.06 of auto-attack damage) split by what each totem gives: Windfury Totem's 20%
-- melee haste is ~16.7% more auto-attack damage, Strength of Earth's 155 strength and agility
-- ~310 AP and ~1.9% crit, about 8-9% at 4000 AP: about 2 : 1
M.SUPPORT = { haste = 0.04, strength = 0.02 }

local function stacks(a, max)
  local n = a.count or 0
  if n < 1 then n = 1 end
  if n > max then n = max end
  return n
end

-- found: the target's debuffs (snapshot.auras: key -> { count, remains }); buffs: the player's;
-- own: { earth = kind, air = kind } of our own totems (M.OWN_TOTEMS kinds, "other" or nil);
-- gearMods: gear.effects, copied in. nil when nothing applies: the engine runs as without it.
function M.effects(found, buffs, own, gearMods)
  local best = {}
  for key, a in pairs(found or {}) do
    local e = M.EFFECT[key]
    if e then
      local v = e[3] and e[2] * stacks(a, e[3]) or e[2]
      if v > (best[e[1]] or 0) then best[e[1]] = v end
    end
  end
  local mods
  local function set(k, v)
    mods = mods or {}
    mods[k] = v
  end
  if best.armorMajor or best.armorMinor then set("armor", (1 - (best.armorMajor or 0)) * (1 - (best.armorMinor or 0))) end
  if best.spell then set("spellTaken", 1 + best.spell) end
  if best.phys then set("physTaken", 1 + best.phys) end
  if best.crit then set("critTaken", best.crit) end
  if best.spellCrit then set("spellCritTaken", best.spellCrit) end
  if best.spellHit then set("spellHitTaken", best.spellHit) end
  buffs, own = buffs or {}, own or {}
  local haste = buffs.icyTalons ~= nil or (buffs.windfuryTotem ~= nil and own.air ~= "haste")
  local strength = buffs.hornOfWinter ~= nil or (buffs.strengthOfEarth ~= nil and own.earth ~= "strength")
  if haste or strength then set("support", (haste and 0 or M.SUPPORT.haste) + (strength and 0 or M.SUPPORT.strength)) end
  for k, v in pairs(gearMods or {}) do set(k, v) end
  return mods
end

return M
```

- [ ] **Step 4: Зелёный прогон.** `docker compose run --rm test busted spec/raid_spec.lua spec/build_spec.lua` — зелёные (модуль только в аддоне: в сборке ауры его нет).

- [ ] **Step 5: Весь набор и коммит.** `docker compose run --rm test busted --exclude-tags=perf` — зелёный.

```bash
git add src/raid.lua spec/raid_spec.lua
git commit -m "Точность: модуль raid — дебаффы рейда на цели по категориям wowsims и тотемы, которые группа уже даёт"
```

---
### Task 5: Данные экипировки — `gear_data` и `gear.effects`

Данные (все — из wowsims/wotlk, скачаны 2026-10-01; в репозитории их нет, генератор не нужен):
- **Комплекты** (`assets/database/db.json`, поле `setName`): «Earthshatter Battlegear» (T7), «Worldbreaker Battlegear» (T8), «Thrall's Battlegear» + «Nobundo's Battlegear» (T9, Орда + Альянс — один комплект), «Frost Witch's Battlegear» (T10); 10- и 25-местные версии, T9/T10 — три уровня предмета.
- **Бонусы** (`sim/shaman/items_wotlk.go` и места, где они считаются): T7 2 — Lightning Shield +10% (`lightning_shield.go`); T8 2 — Stormstrike и Lava Lash +20% (`stormstrike.go`, `lavalash.go`), T8 4 — Maelstrom Weapon 2,4 PPM за ранг вместо 2,0 (`talents.go`); T9 2 — Static Shock +3% (`lightning_shield.go`), T9 4 — шоки +25% (`shocks.go`, складывается с Concussion в один `DamageMultiplier`).
- **Реликвии с постоянной добавкой**: Totem of the Dancing Flame 45169 — +155 к каждому удару Stormstrike (`stormstrike.go`); Totem of Splintering 40710 — Windfury +212 AP, Totem of the Astral Winds 27815 — +80 AP (`weapon_imbues.go`); Venture Co. Flame Slicer 38367 — Lava Lash +25 (`lavalash.go`).
- **Символы** — id заклинания, которое отдаёт `GetGlyphSocketInfo` (`assets/db_inputs/glyph_id_map.json`: предмет → заклинание; эффекты — `proto/shaman.proto` + файлы способностей): Stormstrike 41539 → 55446 (+28% природы вместо +20%), Lava Lash 41540 → 55444 (Flametongue +35% вместо +25%), Lightning Shield 41537 → 55448 (+20%), Lightning Bolt 41536 → 55453 (+4%), Flame Shock 41531 → 55447 (бонус крита +60%), Feral Spirit 45771 → 63271 (волки 61% AP вместо 31%, `spirit_wolves.go`), Windfury Weapon 41542 → 55445 (+2% шанса), Chain Lightning 41518 → 55449 (4 цели), Fire Nova 41530 → 55450 (кулдаун −3 с, `firenova.go`), Shocking 41526 → 55442 (GCD шоков 1 с — в wowsims не реализован, источник — подсказка заклинания 55442 на wotlkdb, сверить в задаче 12).

**Files:**
- Modify: `src/gear_data.lua`, `src/gear.lua` (заготовки задачи 1 → полные)
- Create: `spec/gear_spec.lua`

**Interfaces:**
- Produces: `gear_data.SETS` (`t7`/`t8`/`t9`/`t10` → список id), `gear_data.BONUS` (`{ set, pieces, mod, amount }`), `gear_data.RELICS` (id → `{ mod = amount }`), `gear_data.GLYPHS` (id заклинания символа → `{ mod = amount }`); `gear.effects(items, glyphs) -> mods | nil` — `items` — id надетых предметов (любые слоты), `glyphs` — id заклинаний символов. Все поля — **добавки** к числу без экипировки; одинаковые поля из разных источников складываются. Ключи: `ssFlat`, `llFlat`, `wfAp`, `ssMult`, `llMult`, `lsMult`, `shockMult`, `lbMult`, `staticChance`, `mwPpm`, `ssNature`, `llFt`, `fsCrit`, `wolvesAp`, `wfChance`, `clTargets`, `shockGcd` (> 0: GCD шоков 1 с), `fireNovaCd` (секунды).

- [ ] **Step 1: Тест `spec/gear_spec.lua`.**

```lua
local gear = require("gear")
local data = require("gear_data")

describe("gear", function()
  it("nothing the model knows: no mods", function()
    assert.is_nil(gear.effects({}, {}))
    assert.is_nil(gear.effects(nil, nil))
    assert.is_nil(gear.effects({ 12345, 40322 }, { 99999 })) -- Totem of Dueling: a proc, not a constant (task 10)
  end)

  it("relics with a constant bonus", function()
    assert.are.same({ ssFlat = 155 }, gear.effects({ 45169 }, {}))
    assert.are.same({ wfAp = 212 }, gear.effects({ 40710 }, {}))
    assert.are.same({ wfAp = 80 }, gear.effects({ 27815 }, {}))
    assert.are.same({ llFlat = 25 }, gear.effects({ 38367 }, {}))
  end)

  it("set bonuses count the pieces of one set across its 10 / 25 and item level versions", function()
    assert.is_nil(gear.effects({ 45412 }, {}))
    assert.are.same({ ssMult = 0.20, llMult = 0.20 }, gear.effects({ 45412, 46200 }, {}))
    assert.are.same({ ssMult = 0.20, llMult = 0.20, mwPpm = 0.20 }, gear.effects({ 45412, 45413, 46203, 46205 }, {}))
  end)

  it("T9: Thrall's (Horde) and Nobundo's (Alliance) pieces are one set", function()
    assert.are.same({ staticChance = 0.03 }, gear.effects({ 48356, 48341 }, {}))
    assert.are.same({ staticChance = 0.03, shockMult = 0.25 }, gear.effects({ 48356, 48357, 48342, 48343 }, {}))
  end)

  it("T7 2 and T10 give what the model counts: Lightning Shield +10%; T10 nothing (no wowsims reference)", function()
    assert.are.same({ lsMult = 0.10 }, gear.effects({ 39597, 40520 }, {}))
    assert.is_nil(gear.effects({ 50830, 50831, 51195, 51240 }, {}))
  end)

  it("the same mod from two sources adds up: T7 2 + Glyph of Lightning Shield = +30%", function()
    assert.are.near(0.30, gear.effects({ 39597, 39601 }, { 55448 }).lsMult, 1e-12)
  end)

  it("glyphs by the spell GetGlyphSocketInfo gives", function()
    assert.are.same({ ssNature = 0.08 }, gear.effects({}, { 55446 }))
    assert.are.same({ llFt = 0.10 }, gear.effects({}, { 55444 }))
    assert.are.same({ wolvesAp = 0.30, clTargets = 1 }, gear.effects({}, { 63271, 55449 }))
    assert.are.same({ fireNovaCd = 3 }, gear.effects({}, { 55450 }))
  end)

  it("every set has distinct pieces; every bonus names a known set", function()
    local seen = {}
    for set, ids in pairs(data.SETS) do
      assert.is_true(#ids == 10 or #ids == 15 or #ids == 30, set)
      for _, id in ipairs(ids) do
        assert.is_nil(seen[id], tostring(id))
        seen[id] = set
      end
    end
    for _, b in ipairs(data.BONUS) do assert.is_table(data.SETS[b[1]], b[1]) end
  end)
end)
```

- [ ] **Step 2: Красный прогон.** `docker compose run --rm test busted spec/gear_spec.lua` — падает (заготовка).

- [ ] **Step 3: `src/gear_data.lua`.**

```lua
-- Enhancement equipment the model knows (WotLK 3.3.5a). Item ids: wowsims assets/database/db.json
-- (setName); effects: wowsims sim/shaman/*.go; glyphs by the spell GetGlyphSocketInfo returns
-- (assets/db_inputs/glyph_id_map.json maps the glyph item to it). Every mod is an addition to the
-- number without the item: wowsims adds them into one DamageMultiplier. Stat procs of trinkets and
-- relics are not here: while up they are in the character sheet already. Addon only.
local M = {}

M.SETS = {
  -- Earthshatter Battlegear
  t7 = { 39597, 39601, 39602, 39603, 39604, 40520, 40521, 40522, 40523, 40524 },
  -- Worldbreaker Battlegear
  t8 = { 45412, 45413, 45414, 45415, 45416, 46200, 46203, 46205, 46208, 46212 },
  -- Nobundo's Battlegear (Alliance), Thrall's Battlegear (Horde): one set
  t9 = { 48341, 48342, 48343, 48344, 48345, 48346, 48347, 48348, 48349, 48350, 48351, 48352, 48353, 48354, 48355,
         48356, 48357, 48358, 48359, 48360, 48361, 48362, 48363, 48364, 48365, 48366, 48367, 48368, 48369, 48370 },
  -- Frost Witch's Battlegear: its bonuses are a TODO in wowsims, nothing to check them against
  t10 = { 50830, 50831, 50832, 50833, 50834, 51195, 51196, 51197, 51198, 51199, 51240, 51241, 51242, 51243, 51244 },
}

-- set, pieces, mod, amount
M.BONUS = {
  { "t7", 2, "lsMult", 0.10 },       -- Lightning Shield +10%
  { "t8", 2, "ssMult", 0.20 },       -- Stormstrike +20%
  { "t8", 2, "llMult", 0.20 },       -- Lava Lash +20%
  { "t8", 4, "mwPpm", 0.20 },        -- Maelstrom Weapon 2.4 PPM per rank instead of 2.0
  { "t9", 2, "staticChance", 0.03 }, -- Static Shock +3%
  { "t9", 4, "shockMult", 0.25 },    -- shocks +25%
}

-- ranged slot: relics with a constant bonus
M.RELICS = {
  [45169] = { ssFlat = 155 }, -- Totem of the Dancing Flame: +155 to each Stormstrike hit
  [40710] = { wfAp = 212 },   -- Totem of Splintering: Windfury +212 attack power
  [27815] = { wfAp = 80 },    -- Totem of the Astral Winds
  [38367] = { llFlat = 25 },  -- Venture Co. Flame Slicer: Lava Lash +25
}

-- glyph spell -> mods
M.GLYPHS = {
  [55446] = { ssNature = 0.08 },  -- Stormstrike: +28% nature instead of +20%
  [55444] = { llFt = 0.10 },      -- Lava Lash: +35% with Flametongue instead of +25%
  [55448] = { lsMult = 0.20 },    -- Lightning Shield +20%
  [55453] = { lbMult = 0.04 },    -- Lightning Bolt +4%
  [55447] = { fsCrit = 0.60 },    -- Flame Shock: critical damage bonus +60%
  [63271] = { wolvesAp = 0.30 },  -- Feral Spirit: wolves get 61% of attack power instead of 31%
  [55445] = { wfChance = 0.02 },  -- Windfury Weapon: +2% proc chance
  [55449] = { clTargets = 1 },    -- Chain Lightning: 4 targets
  [55450] = { fireNovaCd = 3 },   -- Fire Nova: cooldown -3 s
  [55442] = { shockGcd = 1 },     -- Shocking: shocks trigger a 1 s GCD (wotlkdb tooltip; not in wowsims)
}

return M
```

- [ ] **Step 4: `src/gear.lua`.**

```lua
-- Equipment and glyphs -> S.mods additions (gear_data). Pure: snapshot reads the item and glyph
-- ids and calls effects once per equipment change (snapshot.scan), not per snapshot. Addon only.
local data = require("gear_data")

local M = {}

-- item id -> set key
local SET_OF = {}
for set, ids in pairs(data.SETS) do
  for _, id in ipairs(ids) do SET_OF[id] = set end
end

local function add(mods, patch)
  for k, v in pairs(patch) do mods[k] = (mods[k] or 0) + v end
end

-- items: equipped item ids (any slots); glyphs: glyph spell ids. nil when nothing is known.
function M.effects(items, glyphs)
  local mods, pieces, any = {}, {}, false
  for _, id in ipairs(items or {}) do
    local relic = data.RELICS[id]
    if relic then add(mods, relic); any = true end
    local set = SET_OF[id]
    if set then pieces[set] = (pieces[set] or 0) + 1 end
  end
  for _, b in ipairs(data.BONUS) do
    if (pieces[b[1]] or 0) >= b[2] then
      mods[b[3]] = (mods[b[3]] or 0) + b[4]
      any = true
    end
  end
  for _, id in ipairs(glyphs or {}) do
    local g = data.GLYPHS[id]
    if g then add(mods, g); any = true end
  end
  return any and mods or nil
end

return M
```

- [ ] **Step 5: Зелёный прогон.** `docker compose run --rm test busted spec/gear_spec.lua spec/build_spec.lua` — зелёные.

- [ ] **Step 6: Весь набор и коммит.** `docker compose run --rm test busted --exclude-tags=perf` — зелёный.

```bash
git add src/gear_data.lua src/gear.lua spec/gear_spec.lua
git commit -m "Точность: данные экипировки — комплекты T7–T10, реликвии и символы энха (по wowsims)"
```

---
### Task 6: Снимок читает дебаффы, баффы группы, свои тотемы, экипировку и символы → `S.mods`

**Files:**
- Modify: `src/snapshot.lua` (требования модулей ~1–6; `M.scan` ~54–83; новые `M.GEAR_SLOTS`, `M.GLYPH_SOCKETS`, `M.scanGear`, `M.mods` над `M.build`; `M.build` после `S.totems` ~478)
- Modify: `src/runtime.lua` (новый `M.REGEAR` под `M.RESCAN` ~29; ветка в `M.onEvent` перед `elseif M.RESCAN[event]` ~340; регистрация ~488)
- Modify: `spec/support/game_mock.lua` (`G.EXTRA_NAMES`; `GetInventoryItemID`, `GetGlyphSocketInfo` в `G.install`; строка `cfg` в комментарии над `G.install`)
- Test: `spec/snapshot_spec.lua` (новый `describe` в конце), `spec/runtime_spec.lua` (рядом с тестами `RESCAN`/регистрации событий ~380)

**Interfaces:**
- Consumes: `raid.DEBUFFS`, `raid.BUFFS`, `raid.OWN_TOTEMS`, `raid.effects(found, buffs, own, gearMods)` (задача 4); `gear.effects(items, glyphs)` (задача 5). В своих тестах — подделки через `package.loaded` (настоящие модули пишутся параллельно).
- Produces: `S.mods` (результат `raid.effects`); `snapshot.GEAR_SLOTS = { 1, 3, 5, 7, 10, 13, 14, 18 }`, `snapshot.GLYPH_SOCKETS = 6`; `snapshot.scanGear(c)` → `c.gearItems`, `c.gearGlyphs`, `c.gearMods`; `snapshot.mods(c, S, now) -> mods | nil`; `runtime.REGEAR` — `UNIT_INVENTORY_CHANGED` (только `"player"`), `GLYPH_ADDED`, `GLYPH_REMOVED`, `GLYPH_UPDATED`, `ACTIVE_TALENT_GROUP_CHANGED`. Мок: `cfg.inventory = { [slot] = itemId }`, `cfg.glyphs = { [socket] = { spellId, glyphType } }`.

- [ ] **Step 1: Мок `spec/support/game_mock.lua`.** В `G.EXTRA_NAMES` — имена id из `raid` (таблица задачи 4) и тотемов:

```lua
  -- raid.lua: target debuffs, the player's buffs, our own earth / air totems
  [7386] = "Sunder Armor", [8647] = "Expose Armor", [55749] = "Acid Spit", [770] = "Faerie Fire",
  [16857] = "Faerie Fire (Feral)", [56631] = "Sting", [702] = "Curse of Weakness", [53598] = "Spore Cloud",
  [1490] = "Curse of the Elements", [51726] = "Ebon Plague", [60431] = "Earth and Moon", [30708] = "Totem of Wrath",
  [21183] = "Heart of the Crusader", [58410] = "Master Poisoner", [30069] = "Blood Frenzy", [58683] = "Savage Combat",
  [22959] = "Improved Scorch", [12579] = "Winter's Chill", [17800] = "Shadow Mastery", [33198] = "Misery",
  [57330] = "Horn of Winter", [8076] = "Strength of Earth", [8512] = "Windfury Totem", [55610] = "Improved Icy Talons",
  [8075] = "Strength of Earth Totem",
```

В `G.install`:

```lua
  _G.GetInventoryItemID = function(_, slot) return ((cfg.inventory or {})[slot]) end
  -- 3.3.5a: enabled, glyphType (1 major, 2 minor), glyphSpell, icon (Blizzard_GlyphUI.lua)
  _G.GetGlyphSocketInfo = function(i)
    local g = (cfg.glyphs or {})[i]
    if not g then return true, i % 2 == 0 and 2 or 1, nil, nil end
    return true, g[2] or 1, g[1], "icon"
  end
```

- [ ] **Step 2: Тесты `spec/snapshot_spec.lua`.** В конце файла:

```lua
-- S.mods: snapshot only reads the client and hands it on; raid.lua and gear.lua have their own
-- specs for the numbers. Here both are fakes that record what they were given.
describe("snapshot: S.mods (addon)", function()
  local snap, got
  local saved = {}
  local NAMES = { "snapshot", "raid", "gear" }
  before_each(function()
    got = {}
    for _, n in ipairs(NAMES) do saved[n] = package.loaded[n]; package.loaded[n] = nil end
    package.loaded.raid = {
      DEBUFFS = { [7386] = "sunder", [1490] = "elements" },
      BUFFS = { [57330] = "hornOfWinter", [8512] = "windfuryTotem" },
      OWN_TOTEMS = { [8075] = "strength", [8512] = "haste" },
      effects = function(found, buffs, own, gearMods)
        got.found, got.buffs, got.own, got.gear = found, buffs, own, gearMods
        return { spellTaken = 1.13 }
      end,
    }
    package.loaded.gear = { effects = function(items, glyphs)
      got.items, got.glyphs = items, glyphs
      return { ssFlat = 155 }
    end }
    snap = require("snapshot")
  end)
  after_each(function()
    for _, n in ipairs(NAMES) do package.loaded[n] = saved[n] end
  end)

  it("reads every caster's debuffs on the target, the player's buffs and our earth and air totems", function()
    install({ auras = {
                target = { HARMFUL = { { name = "Sunder Armor", count = 5, expires = 125, caster = "raid7" },
                                       { name = "Curse of the Elements", expires = 300, caster = "raid2" },
                                       { name = "Flame Shock", expires = 109, caster = "player" } } },
                player = { HELPFUL = { { name = "Horn of Winter", expires = 200, caster = "raid4" },
                                       { name = "Windfury Totem", expires = 0, caster = "player" } } } },
              totems = { [2] = { "Strength of Earth Totem VIII", 90, 300 }, [4] = { "Windfury Totem", 90, 300 } } })
    local S = snap.build(ctx())
    assert.are.same({ spellTaken = 1.13 }, S.mods)
    assert.are.equal(5, got.found.sunder.count)
    assert.is_table(got.found.elements)
    assert.is_nil(got.found.fs)
    assert.is_table(got.buffs.hornOfWinter)
    assert.is_table(got.buffs.windfuryTotem)
    assert.are.same({ earth = "strength", air = "haste" }, got.own)
    assert.are.same({ ssFlat = 155 }, got.gear)
    assert.are.near(9, S.target.fs, 1e-9) -- our own Flame Shock is read as before
  end)

  it("no target: no target debuffs, the group and the gear still count", function()
    install({ target = { exists = false } })
    snap.build(ctx())
    assert.is_nil(got.found)
    assert.are.same({ ssFlat = 155 }, got.gear)
  end)

  it("reads the tier slots, trinkets and relic and the active glyphs once, at scan", function()
    install({ inventory = { [1] = 45412, [3] = 45413, [13] = 50355, [18] = 45169, [16] = 50737 },
              glyphs = { [1] = { 55446, 1 }, [2] = { 58057, 2 } } })
    local c = snap.scan()
    assert.are.same({ 45412, 45413, 50355, 45169 }, c.gearItems) -- the weapons (16, 17) are read elsewhere
    assert.are.same({ 55446, 58057 }, c.gearGlyphs)
    assert.are.same({ ssFlat = 155 }, c.gearMods)
  end)

  -- an elemental shaman's Totem of Wrath outranks our Flametongue Totem: ours is a foreign kind,
  -- worth no damage, and the model drops Searing / Magma over it (spec/wowsims_spec.lua)
  it("our Flametongue Totem is a fire totem of the kind 'other'", function()
    install({ totems = { [1] = { "Flametongue Totem VIII", 90, 300 } } })
    assert.are.equal("other", snap.build(ctx()).totems.fire.kind)
  end)
end)
```

- [ ] **Step 3: Тест `spec/runtime_spec.lua`.** Рядом с тестом регистрации событий (~382):

```lua
  it("recounts the gear when the equipment, glyphs or spec change, not on another unit's inventory", function()
    local snapshot = require("snapshot")
    local real, calls = snapshot.scanGear, 0
    snapshot.scanGear = function() calls = calls + 1 end
    local rt = start()
    calls = 0 -- start scans once (snapshot.scan); only the events count here
    runtime.onEvent(rt, "UNIT_INVENTORY_CHANGED", "party1")
    assert.are.equal(0, calls)
    runtime.onEvent(rt, "UNIT_INVENTORY_CHANGED", "player")
    runtime.onEvent(rt, "GLYPH_UPDATED")
    runtime.onEvent(rt, "ACTIVE_TALENT_GROUP_CHANGED")
    snapshot.scanGear = real
    assert.are.equal(3, calls)
    for e in pairs(runtime.REGEAR) do assert.is_true(rt.frame.events[e], e) end
  end)
```

- [ ] **Step 4: Красный прогон.** `docker compose run --rm test busted spec/snapshot_spec.lua spec/runtime_spec.lua` — новые тесты падают.

- [ ] **Step 5: Реализация в `src/snapshot.lua`.** После `local model = require("model")`:

```lua
--@addon
local raid = require("raid")
local gear = require("gear")
--@end
```

В `M.scan`, перед `c.talents = …`:

```lua
  --@addon
  c.raidDebuffs, c.raidBuffs, c.raidTotems = namesOf(raid.DEBUFFS), namesOf(raid.BUFFS), namesOf(raid.OWN_TOTEMS)
  M.scanGear(c)
  --@end
```

`M.scanGear` — над `M.scan`, `M.mods` — над `M.build`:

```lua
--@addon
-- the slots of the items the model knows: tier (head, shoulders, chest, legs, hands), trinkets, relic
M.GEAR_SLOTS = { 1, 3, 5, 7, 10, 13, 14, 18 }
M.GLYPH_SOCKETS = 6

-- equipped items and active glyphs -> c.gearMods (gear.effects): at scan and when the equipment,
-- glyphs or spec change (runtime.REGEAR), never per snapshot
function M.scanGear(c)
  local items, glyphs = {}, {}
  if GetInventoryItemID then
    for _, slot in ipairs(M.GEAR_SLOTS) do
      local id = GetInventoryItemID("player", slot)
      if id then items[#items + 1] = id end
    end
  end
  if GetGlyphSocketInfo then
    for i = 1, M.GLYPH_SOCKETS do
      local enabled, _, spell = GetGlyphSocketInfo(i)
      if enabled and spell then glyphs[#glyphs + 1] = spell end
    end
  end
  c.gearItems, c.gearGlyphs = items, glyphs
  c.gearMods = gear.effects(items, glyphs)
end
--@end
```

```lua
--@addon
-- S.mods (raid.effects): raid debuffs on the target from every caster, the player's buffs the
-- group gives, which earth and air totems are our own, the equipment. One more pass over the
-- target's auras per snapshot (the search reads the result, never the client).
function M.mods(c, S, now)
  local deb = S.target.exists and M.auras("target", "HARMFUL", c.raidDebuffs, false, now) or nil
  local buffs = M.auras("player", "HELPFUL", c.raidBuffs, false, now)
  local earth = M.totem(M.SLOT.earth, c.raidTotems, now)
  local air = M.totem(M.SLOT.air, c.raidTotems, now)
  return raid.effects(deb, buffs, { earth = earth, air = air }, c.gearMods)
end
--@end
```

В `M.build` после строки `S.totems = { … }`:

```lua
  --@addon
  S.mods = M.mods(c, S, now)
  --@end
```

(до `M.targetTtd`: оценка времени до смерти считает урон тем же `damage`).

- [ ] **Step 6: Реализация в `src/runtime.lua`.** Под `M.RESCAN`:

```lua
--@addon
-- the equipment, glyphs or talent spec changed: recount the gear mods only (snapshot.scanGear)
M.REGEAR = { UNIT_INVENTORY_CHANGED = true, GLYPH_ADDED = true, GLYPH_REMOVED = true, GLYPH_UPDATED = true,
             ACTIVE_TALENT_GROUP_CHANGED = true }
--@end
```

В `M.onEvent` перед `elseif M.RESCAN[event] then`:

```lua
  --@addon
  elseif M.REGEAR[event] then
    -- UNIT_INVENTORY_CHANGED comes for party members too
    if event ~= "UNIT_INVENTORY_CHANGED" or (...) == "player" then
      snapshot.scanGear(ctx.cache)
      M.mark(rt, "aura")
    end
  --@end
```

После `for e in pairs(M.RESCAN) do frame:RegisterEvent(e) end`:

```lua
  --@addon
  for e in pairs(M.REGEAR) do frame:RegisterEvent(e) end
  --@end
```

- [ ] **Step 7: Зелёный прогон.** `docker compose run --rm test busted spec/snapshot_spec.lua spec/runtime_spec.lua spec/build_spec.lua` — зелёные (в сборке ауры этих блоков нет: «the aura gets neither addon-only modules nor addon blocks», строка ауры прежнего размера).

- [ ] **Step 8: Весь набор и коммит.** `docker compose run --rm test busted --exclude-tags=perf` — зелёный.

```bash
git add src/snapshot.lua src/runtime.lua spec/support/game_mock.lua spec/snapshot_spec.lua spec/runtime_spec.lua
git commit -m "Точность: снимок читает дебаффы рейда на цели, баффы группы, свои тотемы, экипировку и символы (S.mods, аддон)"
```

---
### Task 7: Экипировка и символы в формулах урона

Порядок и складывание — как в wowsims: добавки одного заклинания складываются в его `DamageMultiplier` вместе с талантом (шоки: `1 + 0.01 × Concussion + 0.25` у T9 4, не `1.05 × 1.25`; Lightning Shield: `1 + 0.05 × Improved Shields + 0.1 + 0.2`); плоская прибавка — к урону удара до множителей (Stormstrike — к каждому из двух ударов, Lava Lash — к удару левой); бонус крита символа Flame Shock — к «вторичному» модификатору (`ElementalCritMultiplier`): множитель крита `1.5 + 0.1 × Elemental Fury + 0.5 × 0.6`. AP реликвии Windfury прибавляется к AP Windfury до множителя Elemental Weapons — так устроена наша формула сейчас (см. «Открытые вопросы» в контракте: в wowsims Elemental Weapons — множитель урона Windfury, не AP).

**Files:**
- Modify: `src/damage.lua` (`M.CL_FALLOFF` ~18, `M.spellMult` ~69, `M.spellCritFactor` (из задачи 3), `spellDamage`, `M.wf` ~155, `M.staticHit` ~174, `mwChance` ~196, `M.targets` ~310, `M.dot` flameShock, `M.periodic` feralSpirit ~343, `M.action` stormstrike / lavaLash ~362–375)
- Test: `spec/damage_spec.lua` (новый `describe` в конце)

**Interfaces:**
- Consumes: поля `S.mods` экипировки (задача 5): `ssFlat`, `llFlat`, `wfAp`, `ssMult`, `llMult`, `lsMult`, `shockMult`, `lbMult`, `staticChance`, `mwPpm`, `ssNature`, `llFt`, `fsCrit`, `wolvesAp`, `wfChance`, `clTargets`.
- Produces: `damage.spellCritFactor(S, key)` — `key` необязателен (`"flameShock"` — с символом); `damage.CL_FALLOFF[4] = 0.343` (в аддоне).

- [ ] **Step 1: Тесты.** В конце `spec/damage_spec.lua`:

```lua
describe("S.mods (addon: equipment and glyphs)", function()
  local function full(o)
    local S = s80(o)
    S.talents = { staticShock = 3, elementalWeapons = 3, concussion = 5, elementalFury = 5, maelstromWeapon = 5 }
    S.buffs.ls = { charges = 3, remains = 600 }
    S.spells.stormstrike = { id = 17364, rank = 1, cd = 0, cost = 351, cast = 0 }
    S.spells.lavaLash = { id = 60103, rank = 1, cd = 0, cost = 176, cast = 0 }
    return S
  end
  local function diff(key, mods) return damage.action(full({ mods = mods }), key) - damage.action(full(), key) end
  local ZERO = { ssFlat = 0, llFlat = 0, wfAp = 0, ssMult = 0, llMult = 0, lsMult = 0, shockMult = 0, lbMult = 0,
                 staticChance = 0, mwPpm = 0, ssNature = 0, llFt = 0, fsCrit = 0, wolvesAp = 0, wfChance = 0, clTargets = 0 }

  it("gear mods at 0 change nothing, bit for bit", function()
    local a, b = full(), full({ mods = ZERO })
    a.enemies, b.enemies = { melee = 5, nearby = 5 }, { melee = 5, nearby = 5 }
    a.target.ss, b.target.ss = { charges = 2, remains = 10 }, { charges = 2, remains = 10 }
    for _, key in ipairs({ "stormstrike", "lavaLash", "earthShock", "flameShock", "lightningBolt", "chainLightning", "fireNova" }) do
      assert.are.equal(damage.action(a, key), damage.action(b, key), key)
    end
    for _, src in ipairs(damage.PERIODIC) do assert.are.equal(damage.periodic(a, src), damage.periodic(b, src), src) end
    assert.are.equal(damage.auto(a, "mh"), damage.auto(b, "mh"))
    assert.are.equal(damage.mwPerSwing(a, "mh"), damage.mwPerSwing(b, "mh"))
  end)

  it("Totem of the Dancing Flame: +155 on each of Stormstrike's two hits, before crit and armor", function()
    local S = full()
    local y = damage.meleeTable(S, false)
    assert.are.near(2 * 155 * y.factor * damage.armorMult(S), diff("stormstrike", { ssFlat = 155 }), 1e-6)
  end)

  it("T8 2: Stormstrike's weapon part and Lava Lash +20%", function()
    local S = full()
    local y = damage.meleeTable(S, false)
    local w = damage.normalized(S, "mh") + damage.normalized(S, "oh")
    assert.are.near(0.2 * w * y.factor * damage.armorMult(S), diff("stormstrike", { ssMult = 0.2 }), 1e-6)
    assert.are.near(0.2 * damage.normalized(S, "oh") * 1.25 * y.factor, diff("lavaLash", { llMult = 0.2 }), 1e-6)
  end)

  it("Glyph of Lava Lash: +35% with Flametongue on the off hand instead of +25%; Venture Co. Flame Slicer +25", function()
    local S = full()
    local y = damage.meleeTable(S, false)
    assert.are.near(0.10 * damage.normalized(S, "oh") * y.factor, diff("lavaLash", { llFt = 0.10 }), 1e-6)
    assert.are.near(25 * 1.25 * y.factor, diff("lavaLash", { llFlat = 25 }), 1e-6)
  end)

  it("T9 4 and Glyph of Lightning Bolt: one multiplier with Concussion", function()
    local a = damage.action(full(), "earthShock")
    assert.are.near((1.05 + 0.25) / 1.05, damage.action(full({ mods = { shockMult = 0.25 } }), "earthShock") / a, 1e-12)
    local f = damage.periodic(full({ mods = { shockMult = 0.25 } }), "flameShock") / damage.periodic(full(), "flameShock")
    assert.are.near((1.05 + 0.25) / 1.05, f, 1e-12)
    local lb = damage.action(full({ mods = { lbMult = 0.04 } }), "lightningBolt") / damage.action(full(), "lightningBolt")
    assert.are.near((1.05 + 0.04) / 1.05, lb, 1e-12)
    assert.are.equal(damage.action(full(), "chainLightning"), damage.action(full({ mods = { lbMult = 0.04 } }), "chainLightning"))
  end)

  it("Static Shock: T7 2 + Glyph of Lightning Shield +30% damage, T9 2 +3% chance", function()
    local a = damage.staticHit(full())
    assert.are.near(1.3, damage.staticHit(full({ mods = { lsMult = 0.3 } })) / a, 1e-12)
    assert.are.near((0.06 + 0.03) / 0.06, damage.staticHit(full({ mods = { staticChance = 0.03 } })) / a, 1e-12)
  end)

  it("Glyph of Stormstrike: +28% nature under Stormstrike instead of +20%", function()
    local S = full()
    S.target.ss = { charges = 2, remains = 10 }
    local G = full({ mods = { ssNature = 0.08 } })
    G.target.ss = { charges = 2, remains = 10 }
    assert.are.near(1.28 / 1.2, damage.spellMult(G, "earthShock") / damage.spellMult(S, "earthShock"), 1e-12)
  end)

  it("Glyph of Flame Shock: +60% to Flame Shock's crit bonus only", function()
    local S = full({ mods = { fsCrit = 0.6 } })
    assert.are.near(1 + 0.2 * (2.0 + 0.3 - 1), damage.spellCritFactor(S, "flameShock"), 1e-12)
    assert.are.near(1 + 0.2 * (2.0 - 1), damage.spellCritFactor(S, "earthShock"), 1e-12)
  end)

  it("T8 4: Maelstrom Weapon procs 20% more often", function()
    assert.are.near(1.2, damage.mwPerHit(full({ mods = { mwPpm = 0.2 } }), "mh") / damage.mwPerHit(full(), "mh"), 1e-12)
  end)

  it("Windfury: Totem of Splintering +212 AP (before Elemental Weapons), its glyph +2% chance", function()
    local S = full()
    local y = damage.meleeTable(S, false)
    local _, procs = damage.wf(S)
    local extra = procs * 2 * (212 * 1.4 / 14 * 2.6) * y.factor * damage.armorMult(S)
    assert.are.near(extra, damage.wf(full({ mods = { wfAp = 212 } })) - damage.wf(S), 1e-6)
    local _, p2 = damage.wf(full({ mods = { wfChance = 0.02 } }))
    assert.are.near(0.22 / (1 + 0.22 * 1), p2, 1e-12)
  end)

  it("Glyph of Feral Spirit: wolves get 61% of attack power", function()
    local S = full({ mods = { wolvesAp = 0.30 } })
    local want = (120 + 0.61 * 4000 / 14 * 1.5) / (120 + 0.31 * 4000 / 14 * 1.5)
    assert.are.near(want, damage.periodic(S, "feralSpirit") / damage.periodic(full(), "feralSpirit"), 1e-12)
  end)

  it("Glyph of Chain Lightning: a 4th target at 0.7^3", function()
    local a, b = full(), full({ mods = { clTargets = 1 } })
    a.enemies, b.enemies = { melee = 5, nearby = 5 }, { melee = 5, nearby = 5 }
    assert.are.equal(3, damage.targets(a, "chainLightning"))
    assert.are.equal(4, damage.targets(b, "chainLightning"))
    local single = damage.action(full(), "chainLightning")
    assert.are.near(single * 0.343, damage.action(b, "chainLightning") - damage.action(a, "chainLightning"), 1e-6)
  end)
end)
```

(`full()` без `enemies` — одна цель: `damage.action(full(), "chainLightning")` — урон одной цели.)

- [ ] **Step 2: Красный прогон.** `docker compose run --rm test busted spec/damage_spec.lua` — новые тесты падают.

- [ ] **Step 3: Реализация в `src/damage.lua`.** Каждая вставка — в `--@addon` … `--@end`, старые выражения не меняются, только выносятся в локальные переменные в том же порядке операций.

Под `M.CL_FALLOFF`:

```lua
--@addon
M.CL_FALLOFF[4] = 0.7 * 0.7 * 0.7 -- Glyph of Chain Lightning: a 4th target
local SHOCK = { earthShock = true, flameShock = true, frostShock = true }
--@end
```

`M.spellMult`:

```lua
function M.spellMult(S, key)
  local m = 1
  --@addon
  -- the equipment's additions join the talent in one multiplier, as wowsims' DamageMultiplier
  local mods = S.mods
  --@end
  if CONCUSSION[key] then
    local c = 1 + 0.01 * talent(S, "concussion")
    --@addon
    if mods and mods.shockMult and SHOCK[key] then c = c + mods.shockMult end
    if mods and mods.lbMult and key == "lightningBolt" then c = c + mods.lbMult end
    --@end
    m = m * c
  end
  if CALL_OF_FLAME[key] then m = m * (1 + 0.05 * talent(S, "callOfFlame")) end
  if key == "fireNova" then m = m * (1 + 0.1 * talent(S, "improvedFireNova")) end
  if key == "lightningShield" then
    local c = 1 + 0.05 * talent(S, "improvedShields")
    --@addon
    if mods and mods.lsMult then c = c + mods.lsMult end
    --@end
    m = m * c
  end
  local ss = S.target and S.target.ss
  if NATURE_SS[key] and ss and (ss.charges or 0) > 0 then
    local b = 1.2
    --@addon
    if mods and mods.ssNature then b = b + mods.ssNature end
    --@end
    m = m * b
  end
  return m
end
```

`M.spellCritFactor` (версия задачи 3 + ключ):

```lua
function M.spellCritFactor(S, key)
  local mult = 1.5 + 0.1 * talent(S, "elementalFury")
  --@addon
  -- Glyph of Flame Shock: +60% to the crit bonus's secondary modifiers (wowsims ElementalCritMultiplier)
  local mods = S.mods
  if key == "flameShock" and mods and mods.fsCrit then mult = mult + 0.5 * mods.fsCrit end
  --@end
  return 1 + M.spellCrit(S) * (mult - 1)
end
```

В `spellDamage` и в ветке `flameShock` у `M.dot`: `M.spellCritFactor(S, key)` вместо `M.spellCritFactor(S)`.

`M.wf`:

```lua
  local ew = talent(S, "elementalWeapons")
  local ap, chance = byLevel(M.WF_AP, S.player.level), M.WF_CHANCE
  --@addon
  local mods = S.mods
  if mods and mods.wfAp then ap = ap + mods.wfAp end
  if mods and mods.wfChance then chance = chance + mods.wfChance end
  --@end
  local bonus = ap * (1 + (M.EW_WF[ew] or 0))
  local procs = chance / (1 + chance * math.floor(M.WF_ICD / w.speed))
```

`M.staticHit`:

```lua
  local c = 0.02 * r
  --@addon
  local mods = S.mods
  if mods and mods.staticChance then c = c + mods.staticChance end
  --@end
  return c * spellDamage(S, "lightningShield", M.row(S, "lightningShield"))
```

`mwChance`:

```lua
  local ppm = 2 * r
  --@addon
  local mods = S.mods
  if mods and mods.mwPpm then ppm = ppm * (1 + mods.mwPpm) end
  --@end
  return math.min(1, ppm * wspeed(w) / 60)
```

`M.targets`:

```lua
  if key == "chainLightning" then
    local cap = 3
    --@addon
    local mods = S.mods
    if mods and mods.clTargets then cap = cap + mods.clTargets end
    --@end
    return math.min(n, cap)
  end
```

`M.periodic`, ветка `feralSpirit`:

```lua
    local share = M.WOLF_AP
    --@addon
    local mods = S.mods
    if mods and mods.wolvesAp then share = share + mods.wolvesAp end
    --@end
    local perHit = M.WOLF_BASE + share * (S.player.ap or 0) / 14 * M.WOLF_SPEED
```

`M.action`, ветка `stormstrike`:

```lua
    local w = M.normalized(S, "mh") + M.normalized(S, "oh")
    --@addon
    local mods = S.mods
    if mods and mods.ssFlat then w = w + mods.ssFlat * (S.weapons.oh and 2 or 1) end -- on each hit
    if mods and mods.ssMult then w = w * (1 + mods.ssMult) end
    --@end
```

Ветка `lavaLash`:

```lua
    local y = M.meleeTable(S, false)
    local bonus = oh.enchant == "ft" and 1.25 or 1
    local base = M.normalized(S, "oh")
    --@addon
    local mods = S.mods
    if mods then
      if mods.llFt and oh.enchant == "ft" then bonus = bonus + mods.llFt end
      if mods.llFlat then base = base + mods.llFlat end
      if mods.llMult then bonus = bonus * (1 + mods.llMult) end
    end
    --@end
    local wpn = base * bonus * y.factor
    --@addon
    if mods and mods.spellTaken then wpn = wpn * mods.spellTaken end
    --@end
    return wpn + procsPerHit(S, "oh") * y.landed
```

- [ ] **Step 4: Зелёный прогон.** `docker compose run --rm test busted spec/damage_spec.lua` — зелёные; бит в бит: `docker compose run --rm test busted spec/recorded_spec.lua spec/wowsims_spec.lua spec/leveling_spec.lua spec/model_spec.lua` — без правок ожиданий; `docker compose run --rm test busted --tags=perf` — в лимитах (числа — в отчёт).

- [ ] **Step 5: Весь набор и коммит.** `docker compose run --rm test busted --exclude-tags=perf` — зелёный.

```bash
git add src/damage.lua spec/damage_spec.lua
git commit -m "Точность: реликвии, комплекты T7–T9 и символы в формулах урона (S.mods, аддон)"
```

---
### Task 8: Символы, которые меняют GCD и кулдауны — `model`

Glyph of Fire Nova: кулдаун −3 с после Improved Fire Nova (wowsims `firenova.go`: `10 - glyph 3 - 2 × Improved Fire Nova`). Glyph of Shocking: шоки дают GCD 1 с (в wowsims не реализован; подсказка заклинания 55442 на wotlkdb — сверить в задаче 12, пункт «id»; при расхождении текста — поле `shockGcd` из `gear_data` убрать, тест — тоже, сказать в отчёте).

**Files:**
- Modify: `src/model.lua` (`M.cooldownFor` ~391, `M.gcdFor` ~398)
- Test: `spec/model_spec.lua` (новый `describe("glyphs (S.mods)", …)` внутри `describe("model", …)`)

**Interfaces:**
- Consumes: `S.mods.shockGcd` (> 0 — GCD шоков 1 с), `S.mods.fireNovaCd` (секунды).
- Produces: `model.gcdFor(S, key)` и `model.cooldownFor(S, key)` с символами; без `S.mods` — как раньше.

- [ ] **Step 1: Тесты.** В `spec/model_spec.lua`:

```lua
  describe("glyphs (S.mods)", function()
    it("Glyph of Shocking: a shock triggers a 1 s GCD, other spells the hasted one", function()
      local S = fixtures.state({ gcd = 1.4 })
      assert.are.equal(1.4, model.gcdFor(S, "earthShock"))
      S.mods = { shockGcd = 1 }
      assert.are.equal(1.0, model.gcdFor(S, "earthShock"))
      assert.are.equal(1.0, model.gcdFor(S, "flameShock"))
      assert.are.equal(1.4, model.gcdFor(S, "stormstrike"))
    end)

    it("after a shock with Glyph of Shocking the next press waits 1 s", function()
      local S = fixtures.state({ gcd = 1.4 })
      S.mods = { shockGcd = 1 }
      assert.are.near(1.0, model.apply(S, "earthShock").gcdRemains, 1e-9)
    end)

    it("Glyph of Fire Nova: the cooldown 3 s shorter, after Improved Fire Nova", function()
      local S = fixtures.state({ talents = { improvedFireNova = 2 } })
      assert.are.equal(6, model.cooldownFor(S, "fireNova"))
      S.mods = { fireNovaCd = 3 }
      assert.are.equal(3, model.cooldownFor(S, "fireNova"))
    end)
  end)
```

- [ ] **Step 2: Красный прогон.** `docker compose run --rm test busted spec/model_spec.lua` — новые тесты падают.

- [ ] **Step 3: Реализация в `src/model.lua`.**

```lua
function M.cooldownFor(S, key)
  local meta = spells.byKey[key]
  if meta.sharedCd == "shock" then return 6 - 0.2 * talent(S, "reverberation") end
  if key == "fireNova" then
    local cd = 10 - 2 * talent(S, "improvedFireNova")
    --@addon
    local mods = S.mods
    if mods and mods.fireNovaCd then cd = cd - mods.fireNovaCd end -- Glyph of Fire Nova
    --@end
    return cd
  end
  return meta.cd or 0
end

function M.gcdFor(S, key)
  local g = byKey[key].gcd or 0
  if g <= 0 then return 0 end
  if g < 1.5 then return 1.0 end
  --@addon
  local mods = S.mods
  if mods and mods.shockGcd and SHOCK_RANGE[key] then return 1.0 end -- Glyph of Shocking
  --@end
  g = S.gcd or 1.5
  if g < 1.0 then return 1.0 end -- = math.max(1.0, g), inlined (hot)
  return g
end
```

`SHOCK_RANGE` — уже локальная таблица шоков модуля (~65). `value.COOLDOWN` (базовые кулдауны для ценности готовых кнопок) берёт кулдаун Fire Nova из данных заклинаний и символа не знает — так и оставить: это оценка хвоста, не время готовности.

- [ ] **Step 4: Зелёный прогон.** `docker compose run --rm test busted spec/model_spec.lua spec/search_spec.lua` — зелёные; `docker compose run --rm test busted --tags=perf` — в лимитах (`gcdFor` горячая: числа инструкций до и после — в отчёт, рост ≤ 1%).

- [ ] **Step 5: Весь набор и коммит.** `docker compose run --rm test busted --exclude-tags=perf` — зелёный.

```bash
git add src/model.lua spec/model_spec.lua
git commit -m "Точность: символы Shocking и Fire Nova в модели — GCD шоков и кулдаун Fire Nova (S.mods, аддон)"
```

---
### Task 9: Сверка с wowsims и скорость поиска под дебаффами рейда

Сейчас случаи `spec/wowsims_spec.lua` идут на цели без дебаффов, а APL wowsims, с которым они сверяются, настроен и прогоняется с `FullDebuffs`. Задача: те же случаи второй раз — с дебаффами (`Sc.raidMods()`), плюс случай «чужой огненный тотем», плюс проверки «нейтральные `S.mods` — бит в бит» и лимиты perf для состояний с `S.mods`.

**Files:**
- Modify: `spec/support/scenario.lua` (новая `Sc.raidMods`, `Sc.gearMods` после `Sc.cd`)
- Modify: `spec/wowsims_spec.lua` (цикл по вариантам; новый случай; поле `raidAlt`; тест «нейтральные mods»)
- Modify: `spec/perf_spec.lua` (новый тест в `describe("performance #integration #perf", …)`)

**Interfaces:**
- Produces: `Sc.raidMods() -> mods` — дебаффы `FullDebuffs` ровно как их даёт `raid.effects` (`spec/raid_spec.lua` «the wowsims full raid»): `{ armor = 0.8 * 0.95, spellTaken = 1.13, physTaken = 1.04, critTaken = 0.03, spellCritTaken = 0.05, spellHitTaken = 0.03 }`; `Sc.gearMods() -> mods` — типичный ICC-энх для perf: `{ ssFlat = 155, ssMult = 0.2, llMult = 0.2, mwPpm = 0.2, ssNature = 0.08, lsMult = 0.3, wolvesAp = 0.3 }`; у случая wowsims — необязательное поле `raidAlt` (как `alt`, только для варианта с дебаффами, с причиной и числами поиска).

- [ ] **Step 1: `spec/support/scenario.lua`.** После `Sc.cd`:

```lua
-- the target debuffs of the wowsims raid (sim/core/test_utils.go FullDebuffs) as raid.effects
-- gives them (spec/raid_spec.lua "the wowsims full raid"): Sunder Armor / Expose Armor, Faerie
-- Fire, Curse of the Elements, Totem of Wrath, Blood Frenzy, Improved Scorch, Misery
function Sc.raidMods()
  return { armor = 0.8 * 0.95, spellTaken = 1.13, physTaken = 1.04, critTaken = 0.03, spellCritTaken = 0.05,
           spellHitTaken = 0.03 }
end

-- a typical ICC enhancement's equipment as gear.effects gives it: Totem of the Dancing Flame, T8 4,
-- glyphs of Stormstrike, Lightning Shield (+ T7 2) and Feral Spirit
function Sc.gearMods()
  return { ssFlat = 155, ssMult = 0.2, llMult = 0.2, mwPpm = 0.2, ssNature = 0.08, lsMult = 0.3, wolvesAp = 0.3 }
end
```

- [ ] **Step 2: `spec/wowsims_spec.lua`.** В `CASES` после «Magma Totem when no fire totem is down»:

```lua
  -- our Flametongue Totem under an elemental's Totem of Wrath: theirs gives the spell power, ours
  -- is a foreign kind (snapshot: "other") worth no damage, so a damage totem goes over it
  { name = "a foreign fire totem (our Flametongue under an elemental's Totem of Wrath): Magma Totem",
    setup = function(S)
      S.totems.fire = { kind = "other", remains = 100 }; S.target.fs = 9
      Sc.cd(S, { stormstrike = 4, shock = 3, fireNova = 4 })
    end,
    expect = "magmaTotem" },
```

Цикл — по двум вариантам:

```lua
-- every case twice: on a target without debuffs, and under the wowsims raid's (FullDebuffs, the
-- set their enhancement APL runs with). raidAlt: alternatives for the second one only, with a reason
local VARIANTS = { { suffix = "", mods = nil }, { suffix = " (raid debuffs)", mods = Sc.raidMods } }

describe("wowsims APL agreement at level 80 #integration", function()
  for _, var in ipairs(VARIANTS) do
    for _, c in ipairs(CASES) do
      it(c.name .. var.suffix, function()
        local S = base()
        S.mods = var.mods and var.mods() or nil
        c.setup(S)
        local key, at = Sc.first(S)
        local ok = key == c.expect or (c.alt and c.alt[key] ~= nil)
          or (var.mods and c.raidAlt and c.raidAlt[key] ~= nil)
        assert.is_true(ok, ("expected %s, got %s"):format(c.expect, tostring(key)))
        assert.is_true(instant(key, at), ("%s should be pressed now, planned at %s"):format(tostring(key), tostring(at)))
      end)
    end
  end
```

(остальные `it` блока — как были, после цикла). В конце блока:

```lua
  -- the multipliers at 1 and the additions at 0 must give the very same plans: S.mods may only
  -- ever change a result through a field that is set (AGENTS.md "bit for bit")
  it("neutral S.mods: the same plans as without, bit for bit", function()
    local neutral = { armor = 1, spellTaken = 1, physTaken = 1, critTaken = 0, spellCritTaken = 0, spellHitTaken = 0,
                      ssFlat = 0, llFlat = 0, wfAp = 0, ssMult = 0, llMult = 0, lsMult = 0, shockMult = 0, lbMult = 0,
                      staticChance = 0, mwPpm = 0, ssNature = 0, llFt = 0, fsCrit = 0, wolvesAp = 0, wfChance = 0,
                      clTargets = 0, fireNovaCd = 0 }
    for i, S in ipairs(Sc.randomStates(30, 11)) do
      local plain = Sc.best(S)
      S.mods = neutral
      local with = Sc.best(S)
      assert.are.equal(plain.value, with.value, "state " .. i)
      assert.are.equal(plain.nodes, with.nodes, "state " .. i)
      assert.are.equal(#plain.steps, #with.steps, "state " .. i)
      for k, st in ipairs(plain.steps) do
        assert.are.equal(st.key, with.steps[k].key, "state " .. i)
        assert.are.equal(st.at, with.steps[k].at, "state " .. i)
      end
    end
  end)
```

(`shockGcd` в нейтральный набор не входит: любое значение > 0 включает символ.)

- [ ] **Step 3: Прогон и разбор.** `docker compose run --rm test busted spec/wowsims_spec.lua`. Для каждого случая «(raid debuffs)», где первая кнопка другая:
  1. Сначала искать ошибку в `damage`/`model`/`value`/`search` (двойной учёт, `S.mods` не дошёл до копии, `spellTaken` не там) — если нашлась, это задача 3 или 7: написать в отчёте, что и где, не чинить чужие файлы.
  2. Если механика верна — посчитать, почему: `search.evaluate(S, steps)` для плана с ожидаемой кнопкой первой и для найденного (как в существующих `alt`), и записать в случай `raidAlt = { <key> = "<причина и числа: X против Y>" }`. Подгонять `src/` под случай нельзя.
  В отчёте — таблица: случай, без дебаффов, с дебаффами, `raidAlt` (если появился) и числа.

- [ ] **Step 4: `spec/perf_spec.lua`.** В конце блока:

```lua
  -- the raid's debuffs and the equipment (S.mods) are read only under the damage memo: a search
  -- with them does the same work, within the same limits
  it("with raid debuffs and equipment the work and the garbage stay under their limits", function()
    local modded = Sc.randomStates(150)
    for _, S in ipairs(modded) do
      local m = Sc.raidMods()
      for k, v in pairs(Sc.gearMods()) do m[k] = v end
      S.mods = m
    end
    for i = 1, 5 do search.best(modded[i]) end
    local n = 0
    debug.sethook(function() n = n + 1 end, "", 1000)
    for _, S in ipairs(modded) do search.best(S) end
    debug.sethook()
    local k = n / #modded
    collectgarbage("collect")
    collectgarbage("stop")
    local kb0 = collectgarbage("count")
    for _, S in ipairs(modded) do search.best(S) end
    local kb = (collectgarbage("count") - kb0) / #modded
    collectgarbage("restart")
    local info = ("with S.mods: %.0f thousand Lua instructions, %.0f KB per search"):format(k, kb)
    print("\nperf: " .. info)
    assert.is_true(k <= 600, info)
    assert.is_true(kb <= 300, info)
  end)
```

- [ ] **Step 5: Прогон perf.** `docker compose run --rm test busted --tags=perf` — зелёный; в отчёт: инструкции и мусор без `S.mods` (старые тесты) и с ними (новый) — разница ≤ 3%.

- [ ] **Step 6: Весь набор и коммит.** `docker compose run --rm test busted --exclude-tags=perf` — зелёный.

```bash
git add spec/support/scenario.lua spec/wowsims_spec.lua spec/perf_spec.lua
git commit -m "Точность: сверка с wowsims и скорость поиска под дебаффами рейда и с экипировкой"
```

---
### Task 10: Реликвии с проком от кнопки

Такие реликвии меняют ротацию в ICC: стаки Totem of the Avalanche держатся только Stormstrike, бафф Totem of Quaking Earth — Lava Lash. Пока прок висит, его характеристики уже в листе персонажа (снимок их видит), поэтому урон в горизонте не пересчитывается: модель ведёт бафф прока как состояние (`S.buffs.relic = { stacks, remains }`, как Maelstrom — ожидаемым значением) и `value.terminal` ценит время баффа, оставшееся после плана (как тотемы и волков, до `TAIL`), по цене характеристики в уроне в секунду (`value.statDps`). Так нажатие нужной кнопки ценнее ровно на то, что оно продлевает.

Данные (wowsims: `items_wotlk.go`, `items.go`, `stormstrike.go`, `lavalash.go`):

| id | Реликвия | Кнопка | Характеристика | Стаки | Длит., с | Шанс | ICD, с | Бафф (id) |
|---|---|---|---|---|---|---|---|---|
| 40322 | Totem of Dueling | Stormstrike | 60 скорости | 1 | 6 | 1 | 0 | 60766 |
| 50463 | Totem of the Avalanche | Stormstrike | 146 AP | 3 | 15 | 1 | 0 | 71216 |
| 42607 / 42608 / 42609 / 51507 | Gladiator's Totem of Indomitability (Deadly / Furious / Relentless / Wrathful) | Lava Lash | 120 / 144 / 172 / 204 AP | 1 | 10 | 1 | 0 | 60549 / 60551 / 60553 / 60555 |
| 47667 | Totem of Quaking Earth | Lava Lash | 400 AP | 1 | 18 | 0,8 | 9 | 67391 |
| 47666 | Totem of Electrifying Wind | Lightning Bolt | 200 скорости | 1 | 12 | 0,7 | 6 | 67385 |
| 40708 | Totem of the Elemental Plane | Lightning Bolt | 196 скорости | 1 | 10 | 0,15 | 30 | 60771 |
| 33507 | Stonebreaker's Totem | любой шок | 110 AP | 1 | 10 | 0,5 | 10 | 43749 |

Не входят: Bizuri's Totem of Shattered Ice (прок от тиков Flame Shock, не от нажатия), Skycall Totem (только скорость заклинаний).

**Files:**
- Modify: `src/gear_data.lua` (`M.PROCS`), `src/gear.lua` (`mods.proc`)
- Modify: `src/snapshot.lua` (`M.scanGear` — `c.procNames`; `M.build` — `S.buffs.relic`)
- Modify: `src/model.lua` (`M.cloneState` buffs, `fillState`, заполнение рабочей копии ~1069 (рядом с `flurry`), отсчёт баффов в `advance` ~907, нажатие в `applyOn`)
- Modify: `src/value.lua` (`M.HASTE_RATING`, `M.statDps`, `relicValue`, `M.terminal`)
- Test: `spec/gear_spec.lua`, `spec/snapshot_spec.lua`, `spec/model_spec.lua` (`states()` и новый `describe`), `spec/value_spec.lua`, `spec/perf_spec.lua`

**Interfaces:**
- Produces: `gear_data.PROCS[id] = { key, stat, amount, stacks, duration, chance, icd, aura }` (`key` — ключ кнопки или `"shock"`; `stat` — `"ap"` | `"haste"`); `S.mods.proc` — запись `PROCS` надетой реликвии (таблица, не складывается); `S.buffs.relic = { stacks, remains }` — есть, только когда есть `S.mods.proc`; `value.HASTE_RATING = 32.79`; `value.statDps(S, stat) -> урон в секунду на единицу` (кэш на поиск в `S.memo`).

- [ ] **Step 1: Тесты.** `spec/gear_spec.lua`:

```lua
  it("a relic with a proc on a button gives S.mods.proc, its gear_data.PROCS entry as it is", function()
    local m = gear.effects({ 50463 }, { 55446 })
    assert.are.equal(data.PROCS[50463], m.proc)
    assert.are.equal(0.08, m.ssNature)
  end)
```

`spec/snapshot_spec.lua` (отдельный `describe` с настоящими `raid`/`gear`):

```lua
describe("snapshot: a relic's proc buff (addon)", function()
  it("reads the proc's stacks and time left into S.buffs.relic, only with such a relic", function()
    install({ inventory = { [18] = 50463 }, spellNames = { [71216] = "Enraged" },
              auras = { player = { HELPFUL = { { name = "Enraged", count = 2, expires = 110 } } } } })
    local S = snapshot.build(ctx())
    assert.are.same({ stacks = 2, remains = 10 }, S.buffs.relic)
    install({ inventory = { [18] = 45169 } })
    assert.is_nil(snapshot.build(ctx()).buffs.relic)
  end)
end)
```

`spec/model_spec.lua` — в `states()`:

```lua
                           { mods = { proc = { key = "stormstrike", stat = "ap", amount = 146, stacks = 3, duration = 15,
                                               chance = 1, icd = 0, aura = 71216 } },
                             buffs = { relic = { stacks = 1, remains = 5 } } },
```

и новый блок:

```lua
  describe("relic procs (S.mods.proc)", function()
    local AVALANCHE = { key = "stormstrike", stat = "ap", amount = 146, stacks = 3, duration = 15, chance = 1, icd = 0, aura = 71216 }
    local QUAKING = { key = "lavaLash", stat = "ap", amount = 400, stacks = 1, duration = 18, chance = 0.8, icd = 9, aura = 67391 }
    local STONEBREAKER = { key = "shock", stat = "ap", amount = 110, stacks = 1, duration = 10, chance = 0.5, icd = 10, aura = 43749 }
    local function withProc(p, stacks, remains)
      local S = fixtures.state()
      S.mods = { proc = p }
      S.buffs.relic = { stacks = stacks, remains = remains }
      return S
    end

    it("Stormstrike adds a stack of Totem of the Avalanche and refreshes it, up to 3; other buttons do not", function()
      local r = model.apply(withProc(AVALANCHE, 1, 4), "stormstrike").buffs.relic
      assert.are.equal(2, r.stacks)
      assert.are.near(15, r.remains, 1e-9)
      assert.are.equal(3, model.apply(withProc(AVALANCHE, 3, 4), "stormstrike").buffs.relic.stacks)
      r = model.apply(withProc(AVALANCHE, 1, 4), "earthShock").buffs.relic
      assert.are.same({ stacks = 1, remains = 4 }, r)
    end)

    it("a chance below 1 adds that share of a stack and of the refresh; nothing while the internal cooldown runs", function()
      local r = model.apply(withProc(QUAKING, 0, 0), "lavaLash").buffs.relic
      assert.are.near(0.8, r.stacks, 1e-12)
      assert.are.near(0.8 * 18, r.remains, 1e-12)
      r = model.apply(withProc(QUAKING, 1, 15), "lavaLash").buffs.relic -- procced 3 s ago, 9 s cooldown
      assert.are.same({ stacks = 1, remains = 15 }, r)
    end)

    it("Stonebreaker's Totem: every shock is its button", function()
      assert.are.near(0.5, model.apply(withProc(STONEBREAKER, 0, 0), "flameShock").buffs.relic.stacks, 1e-12)
      assert.are.near(0.5, model.apply(withProc(STONEBREAKER, 0, 0), "earthShock").buffs.relic.stacks, 1e-12)
    end)

    it("the buff runs out while waiting", function()
      assert.are.same({ stacks = 0, remains = 0 }, model.wait(withProc(AVALANCHE, 2, 3), 4).buffs.relic)
      assert.are.near(3, model.wait(withProc(AVALANCHE, 2, 5), 2).buffs.relic.remains, 1e-9)
    end)

    it("the parent state's buff is never changed by a press or a wait", function()
      local S = withProc(AVALANCHE, 1, 4)
      model.apply(S, "stormstrike")
      model.peekApply(S, "stormstrike")
      model.wait(S, 2)
      assert.are.same({ stacks = 1, remains = 4 }, S.buffs.relic)
    end)
  end)
```

`spec/value_spec.lua` (заглушка `damage`, `base` — как у соседних тестов `terminal`):

```lua
  it("statDps: attack power by each hand's weapon share, haste rating at 1% of auto attacks per 32.79", function()
    local S = base({})
    local w = S.weapons
    local dmh = damage.auto(S, "mh") / S.swing.mh.speed
    local doh = damage.auto(S, "oh") / S.swing.oh.speed
    local ap = (dmh * (w.mh.base or w.mh.speed) / 14 / ((w.mh.min + w.mh.max) / 2)
              + doh * (w.oh.base or w.oh.speed) * 0.5 / 14 / ((w.oh.min + w.oh.max) / 2)) * value.MELEE_SHARE
    assert.are.near(ap, value.statDps(S, "ap"), 1e-12)
    assert.are.near((dmh + doh) / (value.HASTE_RATING * 100), value.statDps(S, "haste"), 1e-12)
  end)

  it("a relic's proc still up at the end is worth its stat for the time left, up to TAIL", function()
    local P = { key = "stormstrike", stat = "ap", amount = 146, stacks = 3, duration = 15, chance = 1, icd = 0, aura = 71216 }
    local function at(stacks, remains)
      local S = base({})
      S.mods = { proc = P }
      S.buffs.relic = { stacks = stacks, remains = remains }
      return S
    end
    local per = value.statDps(at(0, 0), "ap")
    assert.is_true(per > 0)
    local none = value.terminal(at(0, 0))
    assert.are.near(math.min(15, value.TAIL) * 3 * 146 * per * value.DISCOUNT, value.terminal(at(3, 15)) - none, 1e-6)
    assert.are.near(4 * 2 * 146 * per * value.DISCOUNT, value.terminal(at(2, 4)) - none, 1e-6)
  end)
```

`spec/perf_spec.lua` — в тесте «with raid debuffs and equipment…» (задача 9) к `m` добавить `m.proc = require("gear_data").PROCS[50463]` и `S.buffs.relic = { stacks = 2, remains = 8 }`.

- [ ] **Step 2: Красный прогон.** `docker compose run --rm test busted spec/gear_spec.lua spec/snapshot_spec.lua spec/model_spec.lua spec/value_spec.lua` — новые тесты падают.

- [ ] **Step 3: `src/gear_data.lua`, `src/gear.lua`.** В `gear_data`:

```lua
-- relics whose proc a button triggers (wowsims items_wotlk.go, items.go, stormstrike.go,
-- lavalash.go): key = the button ("shock": any shock); stat = "ap" | "haste" (rating, melee and
-- spell) per stack; chance per press; icd in s; aura = the proc's buff on the player. Bizuri's
-- Totem of Shattered Ice procs from Flame Shock's ticks, Skycall Totem gives spell haste only.
M.PROCS = {
  [40322] = { key = "stormstrike", stat = "haste", amount = 60, stacks = 1, duration = 6, chance = 1, icd = 0, aura = 60766 },
  [50463] = { key = "stormstrike", stat = "ap", amount = 146, stacks = 3, duration = 15, chance = 1, icd = 0, aura = 71216 },
  [42607] = { key = "lavaLash", stat = "ap", amount = 120, stacks = 1, duration = 10, chance = 1, icd = 0, aura = 60549 },
  [42608] = { key = "lavaLash", stat = "ap", amount = 144, stacks = 1, duration = 10, chance = 1, icd = 0, aura = 60551 },
  [42609] = { key = "lavaLash", stat = "ap", amount = 172, stacks = 1, duration = 10, chance = 1, icd = 0, aura = 60553 },
  [51507] = { key = "lavaLash", stat = "ap", amount = 204, stacks = 1, duration = 10, chance = 1, icd = 0, aura = 60555 },
  [47667] = { key = "lavaLash", stat = "ap", amount = 400, stacks = 1, duration = 18, chance = 0.8, icd = 9, aura = 67391 },
  [47666] = { key = "lightningBolt", stat = "haste", amount = 200, stacks = 1, duration = 12, chance = 0.7, icd = 6, aura = 67385 },
  [40708] = { key = "lightningBolt", stat = "haste", amount = 196, stacks = 1, duration = 10, chance = 0.15, icd = 30, aura = 60771 },
  [33507] = { key = "shock", stat = "ap", amount = 110, stacks = 1, duration = 10, chance = 0.5, icd = 10, aura = 43749 },
}
```

В `gear.effects`, в цикле по `items`:

```lua
    local proc = data.PROCS[id]
    if proc then mods.proc = proc; any = true end -- a table, not an addition
```

- [ ] **Step 4: `src/snapshot.lua`.** В конце `M.scanGear`:

```lua
  local proc = c.gearMods and c.gearMods.proc
  c.procNames = proc and namesOf({ [proc.aura] = "proc" }) or nil
```

В `M.build`, после `S.mods = M.mods(c, S, now)` (тот же блок `--@addon`):

```lua
  -- the relic's proc buff (gear_data.PROCS): the model counts it on along the plan
  if c.procNames then
    local a = M.auras("player", "HELPFUL", c.procNames, false, now).proc
    S.buffs.relic = { stacks = a and math.max(1, a.count) or 0, remains = a and a.remains or 0 }
  end
```

- [ ] **Step 5: `src/model.lua`.** Таблица `buffs.relic` — своя в каждой копии (её меняют `applyOn` и `advance` на месте), как `ls`. Все вставки — в `--@addon` … `--@end`.

`M.cloneState`, в конструкторе `buffs` после строки `flurry = …`:

```lua
              --@addon
              relic = b.relic and { stacks = b.relic.stacks, remains = b.relic.remains },
              --@end
```

`fillState` после `nb.flurry = …`:

```lua
  --@addon
  local rl = b.relic
  if rl then
    local pr = pool.relic
    if not pr then pr = {}; pool.relic = pr end -- once per arena table
    nb.relic = fillPair(pr, rl, "stacks", "remains")
  elseif nb.relic ~= nil then
    nb.relic = nil -- never a nil set on a missing key (Lua 5.1 would add it)
  end
  --@end
```

Заполнение рабочей копии — рядом с `flurry` (~1069), тем же образцом через запасную таблицу `spare.relic` (создать один раз, если её нет). Отсчёт в `advance` после строк `flurry`:

```lua
  --@addon
  local rl = b.relic
  if rl then
    x = (rl.remains or 0) - dt
    if x > 0 then rl.remains = x else rl.remains = 0; rl.stacks = 0 end
  end
  --@end
```

Над `applyOn`:

```lua
--@addon
-- A relic's proc on its button (gear_data.PROCS), an expected value like Maelstrom's stacks: a
-- chance below 1 adds that share of a stack and of the refresh. While its internal cooldown runs
-- (the buff younger than icd) a press procs nothing.
local function procRelic(r, p)
  if not r then return end
  if p.icd > 0 and r.remains > 0 and p.duration - r.remains < p.icd then return end
  local c, s = p.chance, r.stacks
  local top = s + 1 < p.stacks and s + 1 or p.stacks
  r.stacks = s + c * (top - s)
  r.remains = r.remains + c * (p.duration - r.remains)
end
--@end
```

В `applyOn`, там, где применяются эффекты нажатой кнопки (перед цепочкой `if key == …`):

```lua
  --@addon
  local proc = n.mods and n.mods.proc
  if proc and (proc.key == key or (proc.key == "shock" and SHOCK_RANGE[key])) then procRelic(n.buffs.relic, proc) end
  --@end
```

- [ ] **Step 6: `src/value.lua`.** Над `M.terminal`:

```lua
--@addon
-- A relic's proc buff still up at the end of the plan (gear_data.PROCS): its stat for the time
-- left, up to TAIL, at the stat's worth in damage per second. The horizon itself is counted at the
-- snapshot's stats (a proc up now is in them already), so a press of its button is worth the buff
-- time it keeps up after the plan.
M.HASTE_RATING = 32.79 -- haste rating per 1% at level 80 (3.3.5a combat ratings)

-- damage per second of one point of `stat` ("ap" | "haste"), once per search (S.memo): attack
-- power by each hand's share of its weapon damage (UnitDamage holds AP / 14 x speed, the off hand
-- half of it), times MELEE_SHARE; haste rating as 1% of the auto attacks per HASTE_RATING
function M.statDps(S, stat)
  local m = S.memo
  local slot = stat == "ap" and "statDpsAp" or "statDpsHaste"
  local v = m and m[slot]
  if v then return v end
  local damage = D()
  local sw, w = S.swing, S.weapons
  v = 0
  for i = 1, 2 do
    local hand = i == 1 and "mh" or "oh"
    local s, wp = sw and sw[hand], w and w[hand]
    if s and wp and (s.speed or 0) > 0 then
      local dps = damage.auto(S, hand) / s.speed
      if stat == "ap" then
        local avgW = (wp.min + wp.max) / 2
        if avgW > 0 then v = v + dps * (wp.base or wp.speed) * (hand == "oh" and 0.5 or 1) / 14 / avgW end
      else
        v = v + dps / (M.HASTE_RATING * 100)
      end
    end
  end
  if stat == "ap" then v = v * M.MELEE_SHARE end
  if m then m[slot] = v end
  return v
end

local function relicValue(S)
  local p = S.mods and S.mods.proc
  local r = S.buffs.relic
  if not (p and r and r.stacks > 0 and r.remains > 0) then return 0 end
  local left = r.remains < M.TAIL and r.remains or M.TAIL
  local ttd = S.target.ttd
  if ttd and ttd < left then left = ttd end
  return left * r.stacks * p.amount * M.statDps(S, p.stat) * M.DISCOUNT
end
--@end
```

В `M.terminal` к сумме частей (последней строкой перед `return`):

```lua
  --@addon
  v = v + relicValue(S)
  --@end
```

(имя суммирующей переменной — как в `M.terminal`).

- [ ] **Step 7: Зелёный прогон.** `docker compose run --rm test busted spec/gear_spec.lua spec/snapshot_spec.lua spec/model_spec.lua spec/value_spec.lua spec/build_spec.lua` — зелёные, включая «an arena state carries exactly cloneState's fields» и «peekApply and peekWait give exactly what apply and wait give» с состоянием-реликвией. Бит в бит без реликвии: `docker compose run --rm test busted spec/recorded_spec.lua spec/wowsims_spec.lua spec/leveling_spec.lua`. Perf: `docker compose run --rm test busted --tags=perf` — в лимитах, числа — в отчёт.

- [ ] **Step 8: Весь набор и коммит.** `docker compose run --rm test busted --exclude-tags=perf` — зелёный.

```bash
git add src/gear_data.lua src/gear.lua src/snapshot.lua src/model.lua src/value.lua spec/gear_spec.lua spec/snapshot_spec.lua spec/model_spec.lua spec/value_spec.lua spec/perf_spec.lua
git commit -m "Точность: реликвии с проком от кнопки — бафф прока в модели и его ценность после плана (аддон)"
```

---
### Task 11: Документация

**Files:**
- Modify: `AGENTS.md` (Конвенции; «Поиск и скорость»), `.claude/rules/ARCHITECTURE.md` (таблица модулей `src/`), `README.md` (раздел про аддон)

- [ ] **Step 1: `AGENTS.md`.** В «Конвенции» — пункт:

```markdown
- Код только для аддона: строки между `--@addon` и `--@end` (каждый маркер — отдельная строка) и модули `src/` из `tools/build.lua` `B.ADDON_SRC` сборка ауры вырезает (пустые строки на месте — номера строк те же). Без них движок обязан считать как раньше: блок только добавляет к старому выражению отдельной строкой. Тесты гоняют `src/` целиком (поведение аддона); ауру проверяет `spec/build_spec.lua` на вырезанной сборке.
- `S.mods` — эффекты рейда, группы и экипировки на снимок (`raid.effects` + `gear.effects`, только в аддоне), только чтение, одна ссылка во всех копиях состояния. Нет поля — нейтрально; нет эффектов — `S.mods = nil`. В `S.mods` — только то, чего нет в характеристиках игрока: дебаффы цели и модификаторы способностей; баффы на игроке уже в листе персонажа.
```

В «Поиск и скорость» — пункт:

```markdown
- `S.mods` читается только под `memoize` / `memoizeFlags` (или в их вызовах): в одном поиске она не меняется. Лимиты perf — и для состояний с `S.mods` (`spec/perf_spec.lua` «with raid debuffs and equipment…»).
```

В «Сверка с wowsims…» — дописать: «Случаи `spec/wowsims_spec.lua` идут дважды: без дебаффов и с дебаффами рейда wowsims (`Sc.raidMods`, `FullDebuffs`); `raidAlt` — альтернативы только для второго варианта, тоже с причиной.»

- [ ] **Step 2: `.claude/rules/ARCHITECTURE.md`.** В таблицу модулей `src/` после `talents`:

```markdown
| `raid` | дебаффы рейда на цели и баффы группы → `S.mods` (только аддон) | — |
| `gear_data` | комплекты T7–T10, реликвии, символы, проки реликвий (только аддон) | — |
| `gear` | экипировка и символы → добавки `S.mods` (только аддон) | — |
```

Под таблицей строку: «Модули с пометкой «только аддон» (`tools/build.lua` `B.ADDON_SRC`) и блоки `--@addon` в сборку ауры не входят». Карта — ≤ ~150 строк.

- [ ] **Step 3: `README.md`.** В раздел про аддон — абзац «Что аддон знает сверх ауры»: дебаффы рейда на цели (броня, +13% к заклинаниям, крит, физический урон), тотемы, которые группа уже даёт (Horn of Winter, чужой Windfury Totem), реликвию, комплекты T7–T9, символы, проки реликвий от кнопок; задержку меряет по своим нажатиям (и аура, если влезло по задаче 2). Тексты по-русски, нейтрально, без дублирования карты.

- [ ] **Step 4: Коммит.**

```bash
git add AGENTS.md .claude/rules/ARCHITECTURE.md README.md
git commit -m "Точность: документация — код только для аддона, S.mods, модули raid и gear"
```

---

### Task 12: Интеграция и проверка в игре

**Files:**
- Test: `spec/build_spec.lua` (новый сквозной тест в блоке аддона), `spec/raid_spec.lua` (сверка с `Sc.raidMods`)

- [ ] **Step 1: Слияние.** Ветки волн 1–3 — в `feat/accuracy` по порядку волн; конфликтов быть не должно (владение файлами строгое); если есть — разбирать по контракту, не переписывая чужое.

- [ ] **Step 2: Сквозные тесты.** В `spec/raid_spec.lua`:

```lua
  it("Sc.raidMods (the wowsims raid in the verification specs) is what raid.effects gives for FullDebuffs", function()
    local m = raid.effects({ sunder = on(5), expose = on(), faerieFire = on(), curseOfWeakness = on(), elements = on(),
                             ebonPlague = on(), earthAndMoon = on(), totemOfWrath = on(), heartOfTheCrusader = on(),
                             bloodFrenzy = on(), improvedScorch = on(), shadowMastery = on(), misery = on() }, {}, {}, nil)
    local want = require("scenario").raidMods()
    for k, v in pairs(want) do assert.are.near(v, m[k], 1e-12, k) end
    for k in pairs(m) do assert.is_not_nil(want[k], k) end
  end)
```

В `spec/build_spec.lua`, после «runs as an addon without WeakAuras and draws a plan»:

```lua
  -- the same client as above, a raid boss with the raid's debuffs, the relic and a glyph: the
  -- addon's snapshot carries them (S.mods), the aura's bundle has nothing of it
  it("the addon reads the raid's debuffs and the equipment into S.mods; the aura does not #integration", function()
    local G = require("game_mock")
    local spells = require("spells")
    local runtime = require("runtime")
    local known = {}
    for _, meta in ipairs(spells.CATALOG) do known[meta.ranks[#meta.ranks]] = true end
    G.install({ now = 100, known = known, noLibs = true, castMs = { ["Lightning Bolt"] = 2500 },
                target = { level = -1, hp = 1e7, hpMax = 1e7, guid = "Creature-9", classification = "worldboss" },
                inRange = { Stormstrike = 1 }, enchants = { mh = true, oh = true },
                tooltip = { [16] = { "Windfury 8" }, [17] = { "Flametongue 10" } },
                inventory = { [18] = 45169 }, glyphs = { [1] = { 55446, 1 } },
                auras = { player = { HELPFUL = { { name = "Lightning Shield", count = 3, expires = 700 } } },
                          target = { HARMFUL = { { name = "Sunder Armor", count = 5, expires = 125, caster = "raid7" },
                                                 { name = "Curse of the Elements", expires = 300, caster = "raid2" } } } } })
    require("panel_mock").install()
    _G.WeakAuras = nil
    local chunk = assert(loadstring(build.addonCode("src")))
    local genv = clientEnv({})
    setfenv(chunk, genv)
    chunk()
    DoubtMyRotationLoader.scripts.OnEvent(DoubtMyRotationLoader, "ADDON_LOADED", "DoubtMyRotation")
    DoubtMyRotationLoader.scripts.OnEvent(DoubtMyRotationLoader, "PLAYER_LOGIN")
    local rt = genv.DoubtMyRotationAddon.rt
    EnhRotEngineFrame.scripts.OnUpdate(EnhRotEngineFrame, 0.3)
    for _ = 1, 20 do
      if #rt.plan.steps > 0 then break end
      EnhRotEngineFrame.scripts.OnUpdate(EnhRotEngineFrame, 0.016)
    end
    assert.is_true(runtime.validPlan(rt.plan))
    local m = rt.S.mods
    assert.are.near(0.8, m.armor, 1e-12)
    assert.are.near(1.13, m.spellTaken, 1e-12)
    assert.are.equal(155, m.ssFlat)
    assert.are.equal(0.08, m.ssNature)
    assert.is_nil(build.initCode("src"):find("S.mods", 1, true))
    assert.is_not_nil(build.addonCode("src"):find("mods", 1, true))
  end)
```

Аура на записанной фикстуре — те же планы, что до этапа 2: `docker compose run --rm test lua tools/report.lua spec/fixtures/recorded.lua --baseline feat/addon` — расхождений нет.

- [ ] **Step 3: Весь набор, perf, сборка.** `docker compose run --rm test busted` (вместе с perf) — зелёный; `docker compose run --rm test lua tools/build.lua` — строка ауры ≤ 63 000 (размер — в описание PR вместе с размером до этапа: 62 152), папка аддона собрана.

- [ ] **Step 4: Проверка в игре** (3.3.5a, аддон; перед PR, результаты — в описание PR):
  1. **id** — для каждого id из таблиц задач 4, 5, 10: `/run print(GetSpellInfo(<id>))` даёт имя, как в таблице (особенно Ebon Plague 51726, Earth and Moon 60431, Master Poisoner 58410, Misery 33198, Acid Spit 55749, Savage Combat 58683, Windfury Totem 8512 как имя баффа, Strength of Earth 8076, баффы проков 71216, 60766, 67391, 67385, 60771, 43749, 60549–60555). Не совпало — поправить id в `src/raid.lua` / `src/gear_data.lua` и мок.
  2. **Символы:** `/run for i=1,6 do print(i, GetGlyphSocketInfo(i)) end` — третье значение равно id из `gear_data.GLYPHS` для надетых символов; подсказка Glyph of Shocking (55442) — «global cooldown … 1 sec» (иначе убрать `shockGcd`, задача 8).
  3. **Чужой тотем:** в группе с другим шаманом — `/dump UnitAura("player", i)` для баффа Windfury Totem: что отдаёт `unitCaster` (записать в PR: если это хозяин тотема, `raid.effects` можно упростить по `caster`).
  4. **Пинг:** `/dmr export` после боя → `tools/report.lua` — `S.latency` в снимках (медиана), сравнить с `GetNetStats` в том же бою.
  5. **Рейд:** на манекене или боссе с Sunder / Faerie Fire / Curse of the Elements — `S.mods` в снимке экспорта; первая кнопка как в случаях «(raid debuffs)».

- [ ] **Step 5: Ревью и PR.** Независимое ревью ветки по Review Focus; PR `feat/accuracy` → `main` (после этапа 0), `[minor]` в сообщении мерж-коммита. Описание PR — по-русски, без упоминаний ИИ.
