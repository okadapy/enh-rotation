# Этап 3: контракты исполнителей

Работа по плану `docs/superpowers/plans/2026-10-01-stage3-comfort.md` разбита на исполнителей. Каждый работает в своей копии репозитория (git worktree) и своей ветке и сдаёт работу по этому контракту. Код и тесты в плане — образец; отклонения допустимы, только если интерфейс из раздела «Выдаёт» остаётся как в контракте, и о каждом отклонении сказано в отчёте.

Предусловие: этап 1 (`docs/superpowers/plans/2026-10-01-stage1-focus.md`) слит в `feat/comfort`. Волна 1 без S может идти и раньше (только новые файлы и `src/timeline.lua`); S и волна 2 — только после этапа 1.

## Состояние на старте (интегратор, 2026-10-01)

- Ветка `feat/comfort` растёт от `feat/accuracy` (PR #34): в ней уже этап 1 (`main`, PR #33) и этап 2. Предусловие «этап 1 слит» выполнено — S и волна 2 идут по обычному порядку волн.
- «Всё ли готово» этапа 1 — `addon/ready.lua`: `ready.items(info) -> { { key, ok, label, hint }, … }`, `ready.gather(view) -> info | nil`, `checker:open()`; в `core` — `M.helpers.ready` и `M.helpers.check()`, `core.view()`. Адаптер `core.checklist = { items = function() local i = ready.gather(core.view()) return i and ready.items(i) or {} end, open = function() core.helpers.check() end }` (C, волна 2). Сверь поля записи с фактическим `addon/ready.lua`.
- Строка ауры — 62 657 байт, до `B.MAX_IMPORT` **343 байта**. Опция `compact` (T) у ауры не нужна — её код в `src/timeline.lua`/`src/runtime.lua` кладётся в блоки `--@addon` … `--@end` (механизм этапа 2, `AGENTS.md`).
- Параллельно идёт ускорение поиска (этап 2, `src/damage|model|value|search|snapshot.lua`) — этих файлов этап 3 не трогает.
- Docker: при «all predefined address pools have been fully subnetted» — `docker compose -p enh-rotation run --rm test …`.

## Общий контракт (для всех)

1. **Только свои файлы.** Менять можно только файлы из раздела «Владеет». Нужна правка чужого файла — не делать, написать в отчёте, что и зачем.
2. **Интерфейс точно как в контракте.** Имена модулей, функций, полей, параметров, возвращаемых значений, глобальных переменных и рамок из раздела «Выдаёт» — без изменений, на них опираются другие исполнители.
3. **Сначала тест.** Тест пишется до кода и сначала падает по правильной причине; после кода — зелёный.
4. **Тесты в стиле соседних** файлов `spec/`; мок клиента — `spec/support/game_mock.lua`, элементы окон — `spec/support/panel_mock.lua`. Модуль соседа, которого ещё нет, — подмена через `package.loaded.<имя>` до `require` своего модуля (как `panel` и `update` в `spec/addon_core_spec.lua`). Мок по умолчанию считает игрока «в бою» (`UnitAffectingCombat`) — где окно должно открыться, `inCombat = false`.
5. **Команды только в Docker:** `docker compose run --rm test busted spec/<file>_spec.lua`; в конце — весь набор `docker compose run --rm test busted --exclude-tags=perf`, он должен быть зелёным. На хосте Lua нет.
6. **Конвенции `AGENTS.md`:** Lua 5.1; в `src/` нельзя `pcall`, `loadstring`, `setfenv`, `getfenv`, `_G`, `SlashCmdList`, `package`, `io`, `debug` (даже в комментариях); в `addon/` нет `io`, `package`, `debug`, `require` клиента (только `require` сборки); тексты в игре — на английском, перевода нет; API только 3.3.5a (нет `SetShown`, `C_Timer`); `src/spells_data.lua` руками не править; строка импорта ≤ `B.MAX_IMPORT`.
7. **Бой и taint:** окно, которое объясняет или учит, в бою не открывается; защищённые и чужие рамки не трогать (только наши рамки, `Minimap` — лишь как родитель кнопки).
8. **Комментарии в коде — по-английски**, плотность как в соседнем коде; объясняют «почему», а не «что».
9. **Коммит** — один или несколько в своей ветке, сообщение по-русски в стиле `git log` (`Аддон: …`), без номеров задач, без `Co-Authored-By`, «Generated with» и любых упоминаний ИИ. Не пушить, PR не открывать — ветки сводит интегратор.
10. **Git в копии репозитория:** если обёртка `rtk` отказывается работать в worktree — вызывать `/usr/bin/git` напрямую.
11. **Отчёт** (по-русски, кратко): ветка и коммиты; что сделано по пунктам «Выдаёт»; тесты — какие добавлены, итог прогона своих спеков и всего набора (числа); отклонения от плана и почему; что не сделано.

## Волна 0 — интегратор

### I0. Моки клиента (задача 0 плана)

- **Владеет:** `spec/support/game_mock.lua`.
- **Выдаёт:** всё из «Interfaces» задачи 0: методы регионов и рамок (`SetFrameLevel`/`GetFrameLevel`, `SetJustifyV`, `GetChildren`, `GetCenter`, `GetEffectiveScale`, `RegisterForClicks`, `SetNormalTexture`/`SetHighlightTexture`/`SetPushedTexture`, `ClearFocus`, `SetToplevel`, `Enable`/`Disable`/`IsEnabled`), метатаблица `G.FRAME`, функции клиента `InCombatLockdown` (`cfg.lockdown`), `IsInInstance`/`GetInstanceInfo` (`cfg.instance`), `GetCursorPosition` (`cfg.cursor`), `GetMinimapShape` (`cfg.minimapShape`), рамка `Minimap` (`cfg.minimapCenter`), `UISpecialFrames`; сброс новых глобальных `DoubtMyRotation*`.
- **Принимается, если:** весь набор зелёный без других правок; коммит прямо в `feat/comfort` до запуска волны 1.

## Волна 1 — параллельно, от `feat/comfort` после волны 0

### T. Режим «одна кнопка» (задача 1)

- **Владеет:** `src/timeline.lua`, `spec/timeline_spec.lua`; в `src/runtime.lua` — только `M.timelineOptions`; в `spec/runtime_spec.lua` — один новый тест.
- **Выдаёт:** опция ленты `compact`: `timeline.options` → `icons = 1`, `width = 2 * nowX`; `timeline.layout` → `L.compact`, одна иконка с `x = nowX`, без ударов, окна Bolt и GCD; `TL:tick` прячет дорожку, черту и точки; `runtime.timelineOptions(config).compact == (config.compact == true)`.
- **Принимается, если:** тесты задачи 1 зелёные; «бит в бит» не тронут (`spec/search_spec.lua`, `spec/recorded_spec.lua` зелёные); строка импорта ≤ `B.MAX_IMPORT`, новый размер `dist/DoubtMyRotation.txt` — в отчёте (было 62 152).

### S. Опции аддона, окно настроек, toc (задача 2) — после слияния этапа 1

- **Владеет:** `addon/settings.lua`, `addon/panel.lua`, `spec/addon_settings_spec.lua`, `spec/addon_panel_spec.lua`; в `tools/build.lua` — только `B.addonToc`; в `spec/build_spec.lua` — только тест toc.
- **Выдаёт:** `settings.ADDON_OPTIONS` (`compact`, `minimap`, `levelCards`, `elvui` — точно как в задаче 2), `settings.withExtra(options, extra)`, `settings.ACTIONS.guide`, строка помощи `/dmr guide - the first-run guide again`; `panel.ACTIONS = { "lock", "export", "hide", "guide" }`, `panel.PER_ROW = 3`, `panel.SECTIONS` (General + `compact, minimap, levelCards`; Advanced + `elvui`), `kind = "button"` у кнопок действий, `main.widgets`, `panel.reload(main)`; в `.toc` — `## SavedVariablesPerCharacter: DoubtMyRotationCharDB` и `## OptionalDeps: ElvUI`. Опции и кнопки этапа 1 остаются на своих местах.
- **Принимается, если:** тесты задачи 2 зелёные, существующие тесты окна настроек и настроек — зелёные.

### P. Профили (задача 3)

- **Владеет:** `addon/profiles.lua`, `addon/profilepage.lua`, `spec/addon_profiles_spec.lua`, `spec/addon_profilepage_spec.lua`.
- **Опирается на:** `settings.merge` (есть).
- **Выдаёт:** `profiles.DEFAULT`, `MAX_LEVEL`, `NAME_MAX`, `ACCOUNT`, `RULES`, `RULE_NAMES`, `migrate(db, char)`, `names(db)`, `pick(db, char, where, level) -> name, why`, `view(options, db, name)`, `store(options, db, name, config)`, `create(db, name, from)`, `delete(db, char, name)`, `reset(db, name)`; `profilepage.new(host) -> page` (`DoubtMyRotationPanelProfiles`, `name = "Profiles"`, `parent = "DoubtMyRotation"`, `controls`, `widgets` с `kind`, `status`, `refresh`), хост страницы — как в задаче 3.
- **Принимается, если:** тесты задачи 3 зелёные, в том числе: старый `db.config` → Default без потерь и сам остаётся; повторный `migrate` ничего не меняет; удалённый на другом персонаже профиль → Default; порядок правил pvp → raid → party → leveling → выбранный; удаление — со второго нажатия, Default не удаляется.

### K. Карточки (задача 4)

- **Владеет:** `addon/cards.lua`, `spec/addon_cards_spec.lua`.
- **Опирается на:** `src/spells_data.lua`, `src/spells.lua`, `src/talents.lua` (только читать).
- **Выдаёт:** `cards.CARDS` (8 штук, 10–80), `FIELDS`, `HAND_LEVELS`, `TALENT_SPELLS`, `text(s)`, `talentLevel(key)`, `learned(key)`, `newSince(from, to)`, `previous(level)`, `due(level, seen)`, `firstRun(level, seen)`, `window(host) -> w` (`DoubtMyRotationCard`, `w:open(card, close)`, `w:hide()`, `kind`/`widgets`).
- **Принимается, если:** тесты задачи 4 зелёные; ни одного числа в текстах карточек руками (только подстановки `{поле:ключ}`); тест «no spell or talent in a card before its level» зелёный без правки данных; тексты — по механике 3.3.5a, без выдумок (сомнение — убрать фразу, а не угадывать; в отчёте — список фактов, взятых не из данных репозитория: сейчас это только `HAND_LEVELS` и механика Stormstrike / Maelstrom Weapon / Bloodlust).

### W. Очередь, мастер, расписание (задача 5)

- **Владеет:** `addon/guide.lua`, `addon/wizard.lua`, `addon/coach.lua`, `spec/addon_guide_spec.lua`, `spec/addon_wizard_spec.lua`, `spec/addon_coach_spec.lua`.
- **Опирается на:** `cards.due`, `cards.firstRun` и окно карточки `{ open(card, close), hide() }` (K) — **подменяется в своих тестах** через `package.loaded.cards` до `require("coach")`.
- **Выдаёт:** `guide.new(deps)`, `q:push/pump/finish/combat/start`, `q.current`, `q.items`; `wizard.PAGES`, `wizard.new(host) -> w` (`DoubtMyRotationWizard`, `open(close)`, `page(n)`, `hide()`, кнопки `back`, `skip`, `never`, `next`, `check`, галочка `compact`, `kind`/`widgets`); `coach.new(deps)`, `c:login()`, `c:levelUp(level)`, `c:openGuide()`, `c:start(frame)` — точно как в задаче 5.
- **Принимается, если:** тесты задачи 5 зелёные: одно окно за раз; в бою ничего не открывается, бой прячет открытое и возвращает его после на той же странице; `close` ровно один раз (OK/Done, Skip, Escape); мастер не повторяется после «Done» на персонаже и после «Don't show again» на аккаунте; уровень берётся из аргумента `PLAYER_LEVEL_UP`.

### N. Кнопка у миникарты (задача 6)

- **Владеет:** `addon/minimap.lua`, `spec/addon_minimap_spec.lua`.
- **Выдаёт:** `minimap.NAME`, `RADIUS`, `ANGLE`, `TIP`, `offset(angle, shape, radius)`, `angle(cx, cy, px, py)`, `new(host) -> button` (`DoubtMyRotationMinimapButton`, родитель `Minimap`, `kind = "minimap"`, `icon`, `border`, `place(angle)`); хост `{ open, toggle, angle, save }`.
- **Принимается, если:** тесты задачи 6 зелёные; `OnUpdate` стоит только во время перетаскивания; на чужих рамках (`Minimap`) ни `SetScript`, ни `HookScript`.

### X. Оформление ElvUI (задача 7)

- **Владеет:** `addon/skin.lua`, `spec/support/elvui_mock.lua`, `spec/addon_skin_spec.lua`.
- **Опирается на:** поле `kind` у виджетов и `f.widgets` у окон (S, P, K, W, N — по контракту, в своих тестах виджеты создаются сами); окно экспорта `EnhRotExportFrame` из `src/timeline.lua` (есть).
- **Выдаёт:** `skin.CALLBACK`, `skin.HANDLE`, `skin.new(deps) -> sk`, `sk:frame(f)`, `sk:refresh()`, `sk:export(w)`; мок `X.install(cfg)`, `X.initialize()`, `X.remove()`, `X.S`, `X.E`, `X.HANDLERS`.
- **Принимается, если:** тесты задачи 7 зелёные, по одному на каждый путь: ElvUI нет; ElvUI инициализирован раньше; позже (один `AddCallback` на все окна); опция выключена и включена; функция ElvUI падает (одна строка, без ошибки Lua); окно экспорта; подложка ленты (и с упавшим `SetTemplate` — прежняя); кнопка у миникарты. Вызовы ElvUI — только те, что перечислены в «Решениях» плана (сверено по `ElvUI/Modules/Skins/Skins.lua` Rebuffed 6.10).

## Волна 2 — параллельно, от `feat/comfort` после слияния волны 1

### C. Связка (задача 8)

- **Владеет:** `addon/core.lua`, `spec/addon_core_spec.lua`; в `tools/build.lua` — только `B.ADDON_MODULES`; в `spec/build_spec.lua` — тесты «names its folder and its modules» и «runs as an addon without WeakAuras and draws a plan #integration».
- **Опирается на:** всё из волны 1 (настоящие модули); в своих тестах `panel`, `profilepage`, `wizard`, `cards` подменены (`package.loaded`), остальное — настоящее. Этап 1 — его части в `core.lua` сохранить; для последней страницы мастера — адаптер `core.checklist = { items, open }` к модулю «всё ли готово» этапа 1 (до 15 строк), если его интерфейс другой.
- **Выдаёт:** `DoubtMyRotationCharDB` (`profile`, `auto`, `point`, `hidden`, `minimap`, `wizard`, `cards`), `DoubtMyRotationDB.profiles` / `ui` / `wizardOff` (`config` прежний не трогается); `core.config`, `core.profile`, `core.why`, `core.char`, `core.choose`, `core.switch`, `core.changed`, `core.move`, `core.open`, `core.host` (+ `label("guide")`), `core.profileHost`, `core.wizardHost`, `core.cardHost`, `core.miniHost`, `core.checklist`; рамки `DoubtMyRotationEvents`, `DoubtMyRotationGuide`, `DoubtMyRotationCoach`; новый `B.ADDON_MODULES` (порядок — как в задаче 8, модули этапа 1 — перед `core`).
- **Принимается, если:** все тесты задачи 8 зелёные (старые — с правкой под профили, новые блоки «profiles», «first-run guide and level cards», «minimap button, combat and ElvUI»); сквозной тест сборки видит страницу Profiles, кнопку у миникарты, мастер у нового персонажа вне боя; весь набор зелёный; `lua tools/build.lua` пишет оба артефакта.

### D. Документация (задача 9)

- **Владеет:** `README.md`, `AGENTS.md`, `.claude/rules/ARCHITECTURE.md`, `docs/superpowers/specs/2026-10-01-addon-roadmap.md`.
- **Опирается на:** интерфейсы этого контракта и плана (не на код C — работа параллельная).
- **Выдаёт:** всё из задачи 9: README — шесть подразделов и «перезапустите игру после обновления», `/dmr guide`; `AGENTS.md` — одна строка про `ADDON_OPTIONS` и две SavedVariables (правило про английские тексты не трогать); карта — 8 новых модулей аддона, `compact` у `timeline`; дорожная карта — ссылка на план, «Русский клиент» → «Потом» одной строкой, ещё две строки «Потом».
- **Принимается, если:** README и карта не дублируют друг друга; карта ≤ ~150 строк; тексты по-русски, нейтрально; ни одной инструкции, противоречащей плану.

## Волна 3 — интегратор

Слить ветки волны 2 в `feat/comfort`; весь набор `docker compose run --rm test busted --exclude-tags=perf` и `--tags=perf` (поиск не должен измениться); сборка `lua tools/build.lua` (оба артефакта, размер строки ауры ≤ `B.MAX_IMPORT`); DocsKeeper (`MODE: incremental`) — `.claude/docs/` по итогам этапа (в тот же коммит); независимое ревью ветки по «Review Focus» плана; проверка в игре по разделу «Проверка в игре» плана (руками, пользователь); PR в `main` с `[minor]` в сообщении мерж-коммита.
