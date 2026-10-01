# Этап 2 (точнее расчёт): контракты исполнителей

Работа по плану `docs/superpowers/plans/2026-10-01-stage2-accuracy.md` разбита на исполнителей. Каждый работает в своей копии репозитория (git worktree) и своей ветке от `feat/accuracy` (её создаёт интегратор от `feat/addon`) и сдаёт работу по этому контракту. Код и тесты в плане — образец; отклонения допустимы, только если интерфейс из «Выдаёт» остаётся как в контракте, и о каждом отклонении сказано в отчёте.

## Общий контракт (для всех)

1. **Только свои файлы.** Менять можно только файлы из «Владеет». Нужна правка чужого файла — не делать, написать в отчёте, что и зачем.
2. **Интерфейс точно как в контракте.** Имена, параметры, возвращаемые значения, поля `S.mods`, id заклинаний и предметов из «Выдаёт» — без изменений, на них опираются другие исполнители.
3. **Сначала тест.** Тест пишется до кода и сначала падает по правильной причине; после кода — зелёный.
4. **Тесты в стиле соседних** файлов `spec/`; мок клиента — `spec/support/game_mock.lua`, сценарии — `spec/support/scenario.lua`, состояния — `spec/support/fixtures.lua`, заглушки — `spec/support/stubs.lua`.
5. **Команды только в Docker:** `docker compose run --rm test busted spec/<file>_spec.lua`; в конце — весь набор `docker compose run --rm test busted --exclude-tags=perf`, он должен быть зелёным. Кто трогает `src/damage.lua`, `src/model.lua`, `src/value.lua`, `src/search.lua` — ещё `docker compose run --rm test busted --tags=perf` (числа инструкций и мусора до и после — в отчёт). На хосте Lua нет.
6. **Конвенции `AGENTS.md`:** Lua 5.1; в `src/` нельзя `pcall`, `loadstring`, `setfenv`, `getfenv`, `_G`, `SlashCmdList`, `package`, `io`, `debug` (даже в комментариях); API игры — только в `snapshot`, `runtime`, `timeline`; тексты в игре — на английском; `src/spells_data.lua` руками не править.
7. **Только в аддоне.** Всё новое в `src/`, кроме пинга (B), — в блоках `--@addon` … `--@end` (маркер — отдельная строка) или в модулях `B.ADDON_SRC` (`raid`, `gear_data`, `gear`). Блок только добавляет к старому выражению отдельной строкой: без него код верен и считает как раньше.
8. **Бит в бит.** Без `S.mods` — те же `value`, `nodes`, шаги на `spec/fixtures/recorded.lua`, perf-состояниях и сценариях 10–80 уровней: `spec/recorded_spec.lua`, `spec/wowsims_spec.lua`, `spec/leveling_spec.lua`, `spec/search_spec.lua`, `spec/perf_spec.lua` зелёные без правки ожиданий. Порядок операций с плавающей точкой в старых выражениях не менять.
9. **Сверка с wowsims:** ожидание меняется только через `alt` / `raidAlt` с причиной и числами поиска; `src/` под отдельный случай не подгоняется.
10. **Строка ауры** ≤ `B.MAX_IMPORT`: тест «keeps the import string short enough to paste into the client» зелёный; размер из `docker compose run --rm test lua tools/build.lua` — в отчёт.
11. **Комментарии в коде — по-английски**, плотность как в соседнем коде; объясняют «почему».
12. **Коммит** — один или несколько в своей ветке, по-русски в стиле `git log` (`Точность: …`), без номеров задач, без `Co-Authored-By`, «Generated with» и любых упоминаний ИИ. Не пушить, PR не открывать — ветки сводит интегратор.
13. **Git в копии репозитория:** если обёртка `rtk` отказывается работать в worktree — вызывать `/usr/bin/git` напрямую.
14. **Отчёт** (по-русски, кратко): ветка и коммиты; что сделано по пунктам «Выдаёт»; тесты — какие добавлены, итог прогона своих спеков и всего набора (числа); perf и размер ауры (если касается); отклонения от плана и почему; что не сделано.

### Поля `S.mods` (общие для всех волн)

Одна таблица на снимок, только чтение, одна ссылка во всех копиях состояния; нет поля — нейтрально; нет эффектов — `S.mods = nil`.

| Поле | Кто кладёт | Смысл | Кто читает |
|---|---|---|---|
| `armor` | `raid` | множитель брони цели (крупная × малая категория) | `damage.armorMult` |
| `spellTaken` | `raid` | × урон природой, огнём, льдом (и Lava Lash) | `damage` |
| `physTaken` | `raid` | × физический урон (через `damage.armorMult`) | `damage` |
| `critTaken` | `raid` | + шанс крита, ближний бой и заклинания | `damage.meleeTable`, `damage.spellCrit` |
| `spellCritTaken` | `raid` | + крит заклинаний | `damage.spellCrit` |
| `spellHitTaken` | `raid` | + меткость заклинаний | `damage.spellHit` |
| `support` | `raid` | доля урона автоатак за свои тотемы поддержки вместо `value.SUPPORT` | `value` (`autoValue`) |
| `ssFlat`, `llFlat`, `wfAp`, `ssMult`, `llMult`, `lsMult`, `shockMult`, `lbMult`, `staticChance`, `mwPpm`, `ssNature`, `llFt`, `fsCrit`, `wolvesAp`, `wfChance`, `clTargets` | `gear` | добавки к числу без экипировки (смысл — задача 5 плана) | `damage` |
| `shockGcd`, `fireNovaCd` | `gear` | символы Shocking (> 0: GCD шоков 1 с), Fire Nova (−с) | `model` |
| `proc` | `gear` (волна 3) | запись `gear_data.PROCS` надетой реликвии (таблица) | `model`, `value` |

## Ответы пользователя (2026-10-01)

- Вопрос 1: дебаффы, группа и экипировка — **только в аддоне**, ауре ничего не даём.
- Вопросы 2 и 3: Elemental Weapons и Lava Lash чинятся **отдельной задачей до волны 1** — исполнитель Z ниже.
- Остальные вопросы — по умолчанию плана (максимальные ранги талантов, доли 0.04/0.02 как оценка, пинг без запаса, состав «не входит» как в вопросе 6); пункты 4 и 8 проверяются в игре в задаче 12.

## Волна 0 — один исполнитель, от `feat/accuracy` (до волны 1)

### Z. Формулы Windfury (Elemental Weapons) и Lava Lash по механике 3.3.5a

- **Владеет:** `src/damage.lua` (только `M.wf`, ветка Lava Lash в `M.action`/`M.normalized` и константы `EW_WF`), `spec/damage_spec.lua`, ожидания в `spec/wowsims_spec.lua` и `spec/leveling_spec.lua` — меняются только как следствие исправления, каждое изменение с комментарием-причиной; `alt` — только по правилу `AGENTS.md`.
- **Задача:** (1) Elemental Weapons по подсказке 3.3.5a увеличивает **урон удара** Windfury на 13/27/40%, а не AP: `damage.wf` сейчас умножает `bonus` AP — исправить на множитель урона двух дополнительных ударов; источник — подсказка таланта (wotlkdb) и `sim/shaman` wowsims (`weapon_imbues.go`, `talents.go`), со ссылкой в комментарии. (2) Lava Lash: у нас `normalized(S, "oh")`, в wowsims `OHWeaponDamage` (без нормализации). Установить по источникам 3.3.5a (подсказка 60103: «100% of that weapon's damage», wowsims `lavalash.go`), нормализуется ли; если нет — считать от ненормализованного урона левой руки (AP по скорости оружия `w.base`), с тестом; если источники расходятся — оставить как есть и описать расхождение в отчёте, не гадать.
- **Принимается, если:** тесты на каждое исправление (сначала красные) зелёные; весь набор `--exclude-tags=perf` зелёный; каждое изменённое ожидание wowsims/leveling — с причиной в комментарии и в отчёте; `perf` (`--tags=perf`) — инструкции не выросли больше чем на 1%; строка ауры ≤ `B.MAX_IMPORT`; в отчёте — до/после для 80 уровня (wowsims-кейсы) и для прокачки (какие первые кнопки поменялись на `tmp/paste.txt` и `tmp/scholo.txt` через `tools/report.lua --baseline feat/stage1-focus`).

## Волна 1 — параллельно, от `feat/accuracy` после слияния Z

### A. Сборка «только в аддоне» (задача 1 плана)

- **Владеет:** `tools/build.lua`, `spec/build_spec.lua`; создаёт заготовки `src/raid.lua`, `src/gear_data.lua`, `src/gear.lua` (во волне 2 их владельцы — D и F).
- **Выдаёт:** `B.ADDON_OPEN = "--@addon"`, `B.ADDON_CLOSE = "--@end"`, `B.ADDON_SRC = { raid = true, gear_data = true, gear = true }`, `B.strip(code)` (пустые строки на месте блока, маркеры включительно; ошибка при незакрытом, вложенном, лишнем маркере), `B.bundle(srcDir, version, addon)` (аура: без `B.ADDON_SRC` и с `B.strip`), `B.addonCode` — с `addon = true`; `B.MODULES` = `util, spells_data, spells, talents, raid, gear_data, gear, swing, enemies, ttd, damage, model, value, search, planner, snapshot, timeline, recorder, version, runtime`; заготовки: `raid.DEBUFFS = {}`, `raid.BUFFS = {}`, `raid.OWN_TOTEMS = {}`, `raid.SUPPORT = { haste = 0.04, strength = 0.02 }`, `raid.effects(...) -> nil`; `gear_data = { SETS = {}, BONUS = {}, RELICS = {}, GLYPHS = {} }`; `gear.effects(...) -> nil`.
- **Принимается, если:** все тесты задачи 1 зелёные, включая обновлённые «lists modules in the load order», «lists every source module and bundles code that compiles», «uses nothing the WeakAuras sandbox blocks»; «runs as a WeakAuras init action and draws a plan» и «runs as an addon without WeakAuras and draws a plan» по-прежнему зелёные; размер строки ауры не изменился (±10 байт).

### B. Пинг (задача 2 плана)

- **Владеет:** `src/snapshot.lua`, `src/runtime.lua`, `spec/snapshot_spec.lua`, `spec/runtime_spec.lua`.
- **Выдаёт:** `snapshot.PING_N = 15`, `snapshot.PING_MIN = 3`, `snapshot.addPing(ping, dt)`, `snapshot.latency(ping, netMs)`; `ctx.ping = { n = 0, i = 0 }` в `runtime.start`; проба — в `runtime.onCast` на подтверждённом `START` / `SUCCEEDED` (`now - rt.sent.at`), одна на нажатие.
- **Принимается, если:** тесты задачи 2 зелёные; старый «reads the current cast, latency and player stats» не тронут и зелёный (без проб — 0,18); код пинга — общий (без `--@addon`), если после слияния волны 1 аура ≤ `B.MAX_IMPORT`; иначе — запасной вариант шага 6 (в ауре прежняя строка), сказано в отчёте.

### C. `S.mods` рейда в формулах (задача 3 плана)

- **Владеет:** `src/damage.lua`, `src/model.lua`, `src/value.lua`, `spec/damage_spec.lua`, `spec/model_spec.lua`, `spec/value_spec.lua`.
- **Опирается на:** поля `S.mods` из таблицы выше (`armor`, `spellTaken`, `physTaken`, `critTaken`, `spellCritTaken`, `spellHitTaken`, `support`); маркеры `--@addon` / `--@end` (до слияния с A это просто комментарии — строка ауры в своей ветке вырастет; она должна остаться ≤ `B.MAX_IMPORT`).
- **Выдаёт:** `damage.spellCrit(S)`; `damage.armorMult` с `mods.armor` и `mods.physTaken`; `spellTaken` — во всём уроне природой / огнём / льдом (`spellDamage`, `ftHit`, тики Flame Shock, Fire Elemental, оружейная часть Lava Lash); `critTaken` — в `meleeTable` и `spellCrit`; `spellHitTaken` — в `spellHit`; `S.mods` — одна ссылка в `cloneState`, `fillState`, рабочих копиях; `value` — `mods.support` вместо `M.SUPPORT`.
- **Принимается, если:** тесты задачи 3 зелёные, включая «neutral mods change nothing, bit for bit», состояние с `mods` в `states()` model_spec и «часового»; бит в бит по п. 8 общего контракта; perf: инструкции и мусор не выросли больше чем на 1%.

## Волна 2 — параллельно, от `feat/accuracy` после слияния волны 1

Уточнения после волны 1 (интегратор, коммит `7ea2735`):
- Строка ауры — **62 537 байт**, до `B.MAX_IMPORT` (63 000) **463 байта**. Всё новое, что не обязано быть в ауре, — в модулях `B.ADDON_SRC` (`raid`, `gear_data`, `gear`) или в блоках `--@addon` … `--@end` (маркер — один на строке, внутри только целые строки, без вложенности; `B.strip` уже в сборке). Каждый исполнитель в отчёте пишет размер строки ауры до/после.
- Код пинга (B) — общий для ауры и аддона, без блоков `--@addon`.
- C: в `damage.lua` уже есть `damage.spellCrit(S)`, `S.mods` в `armorMult`, `spellDamage`, `ftHit`, `dot`, `periodic`, Lava Lash (`local wpn`), `meleeTable`, `spellHit`; в `model` — `mods` одной ссылкой в копиях; в `value.autoValue` — `mods.support`. Смотри фактический код перед правкой.
- Docker: если `docker compose run …` падает с «all predefined address pools have been fully subnetted» — `docker compose -p enh-rotation run --rm test …` (файлы не менять).

### D. Модуль `raid` (задача 4 плана)

- **Владеет:** `src/raid.lua`, `spec/raid_spec.lua`.
- **Опирается на:** формат `snapshot.auras` (`key -> { count, remains }`), `value.SUPPORT = 0.06`.
- **Выдаёт:** `raid.DEBUFFS`, `raid.EFFECT`, `raid.BUFFS`, `raid.OWN_TOTEMS`, `raid.SUPPORT`, `raid.effects(found, buffs, own, gearMods) -> mods | nil` — id, ключи и величины **ровно как в таблице задачи 4** (по ним S пишет мок, V — `Sc.raidMods`); набор `FullDebuffs` даёт `{ armor = 0.8 × 0.95, spellTaken = 1.13, physTaken = 1.04, critTaken = 0.03, spellCritTaken = 0.05, spellHitTaken = 0.03 }`.
- **Принимается, если:** все тесты задачи 4 зелёные; `spec/build_spec.lua` зелёный (модуль не попадает в ауру).

### F. Данные экипировки (задача 5 плана)

- **Владеет:** `src/gear_data.lua`, `src/gear.lua`, `spec/gear_spec.lua`.
- **Выдаёт:** `gear_data.SETS` / `BONUS` / `RELICS` / `GLYPHS` и `gear.effects(items, glyphs) -> mods | nil` — id и поля **ровно как в задаче 5**; все поля — добавки, одинаковые складываются.
- **Принимается, если:** все тесты задачи 5 зелёные; списки id комплектов совпадают с выписанными из `db.json` wowsims (T7, T8 — по 10, T9 — 30, T10 — 15, без повторов).

### S. Снимок читает рейд и экипировку (задача 6 плана)

- **Владеет:** `src/snapshot.lua`, `src/runtime.lua`, `spec/support/game_mock.lua` (только добавления: имена id задачи 4 в `G.EXTRA_NAMES`, `GetInventoryItemID`, `GetGlyphSocketInfo`, строка `cfg` в комментарии), `spec/snapshot_spec.lua`, `spec/runtime_spec.lua`.
- **Опирается на:** интерфейсы D и F (настоящие пишутся параллельно — в своих тестах подделки через `package.loaded`, как в плане); `snapshot.auras`, `snapshot.totem`, `namesOf`.
- **Выдаёт:** `S.mods = snapshot.mods(c, S, now)` (в `--@addon`); `snapshot.GEAR_SLOTS = { 1, 3, 5, 7, 10, 13, 14, 18 }`, `snapshot.GLYPH_SOCKETS = 6`, `snapshot.scanGear(c)` → `c.gearItems`, `c.gearGlyphs`, `c.gearMods` (в `M.scan` и по `runtime.REGEAR`); `runtime.REGEAR` (`UNIT_INVENTORY_CHANGED` только для `"player"`, `GLYPH_ADDED`, `GLYPH_REMOVED`, `GLYPH_UPDATED`, `ACTIVE_TALENT_GROUP_CHANGED`), зарегистрированы на рамке движка; мок: `cfg.inventory = { [slot] = itemId }`, `cfg.glyphs = { [socket] = { spellId, glyphType } }`.
- **Принимается, если:** тесты задачи 6 зелёные; старые тесты `snapshot_spec`/`runtime_spec` не тронуты и зелёные; `PLAYER_EQUIPMENT_CHANGED` не используется (его нет в FrameXML 3.3.5a); строка ауры прежнего размера.

### E. Экипировка в формулах урона (задача 7 плана)

- **Владеет:** `src/damage.lua`, `spec/damage_spec.lua`.
- **Опирается на:** поля `gear` из таблицы `S.mods`; `damage.spellCrit` и блоки C.
- **Выдаёт:** все поля `gear` урона из таблицы — как в задаче 7 (добавки шоков и Lightning Bolt — к Concussion в одном множителе, Lightning Shield — к Improved Shields; плоские — до множителей; `fsCrit` — `+0.5 × fsCrit` к множителю крита Flame Shock); `damage.spellCritFactor(S, key)`; `damage.CL_FALLOFF[4] = 0.343`.
- **Принимается, если:** тесты задачи 7 зелёные, включая «gear mods at 0 change nothing, bit for bit»; бит в бит по п. 8; perf в лимитах.

### M. Символы в модели (задача 8 плана)

- **Владеет:** `src/model.lua`, `spec/model_spec.lua`.
- **Опирается на:** `S.mods.shockGcd`, `S.mods.fireNovaCd`.
- **Выдаёт:** `model.gcdFor` — 1 с для шоков при `shockGcd`; `model.cooldownFor("fireNova")` — минус `fireNovaCd`.
- **Принимается, если:** тесты задачи 8 зелёные; perf: инструкции не выросли больше чем на 1% (`gcdFor` горячая).

### V. Сверка wowsims и скорость под рейдом (задача 9 плана)

- **Владеет:** `spec/support/scenario.lua`, `spec/wowsims_spec.lua`, `spec/perf_spec.lua`.
- **Опирается на:** C (формулы с `S.mods`); числа D для `FullDebuffs` (из контракта D, не из кода — модуль пишется параллельно); поля E и M — в нейтральном тесте (до слияния с E/M они просто не читаются).
- **Выдаёт:** `Sc.raidMods()`, `Sc.gearMods()`; случаи wowsims в двух вариантах (`raidAlt` — только с причиной и числами); случай «a foreign fire totem…: Magma Totem»; «neutral S.mods: the same plans as without, bit for bit»; perf «with raid debuffs and equipment the work and the garbage stay under their limits».
- **Принимается, если:** тесты задачи 9 зелёные; в отчёте — таблица случаев, где первая кнопка с дебаффами другая (без, с, `raidAlt` и числа) или «таких нет»; найденная ошибка в чужом коде — описана (что, где), не исправлена; perf — числа без и с `S.mods`.

## Волна 3 — параллельно, от `feat/accuracy` после слияния волны 2

### H. Реликвии с проком от кнопки (задача 10 плана)

- **Владеет:** `src/gear_data.lua`, `src/gear.lua`, `src/snapshot.lua`, `src/model.lua`, `src/value.lua`, `spec/gear_spec.lua`, `spec/snapshot_spec.lua`, `spec/model_spec.lua`, `spec/value_spec.lua`, `spec/perf_spec.lua`.
- **Выдаёт:** `gear_data.PROCS` (таблица задачи 10), `S.mods.proc`, `S.buffs.relic = { stacks, remains }` (только при `proc`; своя таблица в каждой копии: `cloneState`, арена, рабочие копии, `advance`, `applyOn`), `value.HASTE_RATING = 32.79`, `value.statDps(S, stat)`, ценность баффа в `value.terminal`.
- **Принимается, если:** тесты задачи 10 зелёные, включая «часового», «peekApply and peekWait give exactly…» с состоянием-реликвией и «the parent state's buff is never changed»; бит в бит без реликвии; perf с `proc` — в лимитах.

### W. Документация (задача 11 плана)

- **Владеет:** `AGENTS.md`, `.claude/rules/ARCHITECTURE.md`, `README.md`.
- **Выдаёт:** конвенции «код только для аддона» и `S.mods`; пункт в «Поиск и скорость»; два варианта сверки wowsims; модули `raid`, `gear_data`, `gear` в карте; абзац «что аддон знает сверх ауры» в README.
- **Принимается, если:** карта ≤ ~150 строк, факты не дублируются между README, `AGENTS.md` и картой; тексты по-русски, нейтрально.

## Волна 4 — интегратор (задача 12 плана)

Слить ветки по волнам (между волнами — слить, весь набор, размер ауры, уточнения в начало следующей волны этого файла); сквозные тесты задачи 12; весь набор вместе с perf; сборка (оба артефакта, размер ауры в PR); `tools/report.lua` на фикстуре против `feat/addon` — без расхождений; проверка в игре по шагу 4 задачи 12; независимое ревью по Review Focus; PR `feat/accuracy` → `main` после этапа 0, `[minor]` в сообщении мерж-коммита.

## Открытые вопросы (решает пользователь до начала или по ходу)

1. **Аура и рейд.** Строке ауры осталось 848 байт, поэтому дебаффы, группа и экипировка — только в аддоне. Нужно ли ауре хоть что-то (например, только Sunder / Curse of the Elements без данных экипировки), и чем за это платить (что вырезать из ауры)?
2. **Elemental Weapons и Windfury.** У нас талант умножает AP Windfury (`damage.wf`: `bonus × (1 + EW)`), в wowsims и в подсказке 3.3.5a («increases the damage caused by your Windfury Weapon effect by 13/27/40%») — урон удара. Это ошибка формулы до этапа 2: исправление меняет числа везде и требует перепроверки wowsims и прокачки. Делать отдельной задачей?
3. **Lava Lash — нормализованное оружие?** У нас `damage.normalized(S, "oh")`, в wowsims `OHWeaponDamage` (без нормализации). Сверить по wotlkdb / записи из игры; если wowsims прав — отдельная правка формулы.
4. **Id, которых нет в репозитории и в wowsims как имён аур.** Ebon Plague 51726, Earth and Moon 60431, Master Poisoner 58410, Misery 33198, Acid Spit 55749, Savage Combat 58683, баффы Windfury Totem 8512 / Strength of Earth 8076 и баффы проков реликвий — проверить в игре (`GetSpellInfo`), шаг 4 задачи 12. Glyph of Shocking (55442) в wowsims не реализован — проверить подсказку.
5. **Ранги талантов за дебаффами** берутся максимальными (рейд). Для 5-местных групп (Heart of the Crusader 1/3 у ретрика в прокачке) это завышает; читать подсказку ауры (`GameTooltip:SetUnitDebuff`) — зависит от языка клиента. Оставить максимум?
6. **Не входит:** тринкеты (проки статов уже в листе персонажа, пока висят; on-use — отдельная строка дорожной карты), T10 2/4 (в wowsims `TODO`, сверять не с чем), T7 4 (Flurry модель не считает), Bizuri's Totem, Armor Penetration рейтинг (`GetCombatRatingBonus(25)` — дёшево добавить в `armorMult`, но это уже характеристика игрока). Что-то из этого нужно в этом этапе?
7. **Доля тотемов поддержки** `0.04 / 0.02` — оценка из величин баффов, не замер. Проверить на симуляции боя (`spec/support/fight.lua`) или оставить?
8. **Пинг без +0,1.** Медиана `SENT → START` уже включает обработку на сервере, поэтому запаса сверху нет. Если в игре после этого чаще срезаются удары кастом — вернуть небольшой запас (`+0.03`)?
