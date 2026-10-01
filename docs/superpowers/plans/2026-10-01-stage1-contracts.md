# Этап 1: контракты исполнителей

Работа по плану `docs/superpowers/plans/2026-10-01-stage1-focus.md` разбита на исполнителей. Каждый работает в своей копии репозитория (git worktree) и своей ветке от `feat/stage1-focus` и сдаёт работу по этому контракту. Код и тесты в плане — образец; отклонения допустимы, только если интерфейс из раздела «Выдаёт» остаётся как в контракте, и о каждом отклонении сказано в отчёте.

**Вне объёма:** Разбор после боя — отдельная работа, файлы recorder/report и `/dmr last` не трогать (`src/recorder.lua`, `tools/report.lua`, `spec/recorder_spec.lua`, `spec/report_spec.lua`, файлы `addon/` про разбор боя, команда `/dmr last` и её опция).

## Общий контракт (для всех)

1. **Только свои файлы.** Менять можно только файлы из раздела «Владеет». Нужна правка чужого файла — не делать, написать в отчёте, что и зачем.
2. **Интерфейс точно как в контракте.** Имена, параметры, возвращаемые значения, ключи опций, имена глобальных рамок из раздела «Выдаёт» — без изменений, на них опираются другие исполнители.
3. **Сначала тест.** Тест пишется до кода и сначала падает по правильной причине; после кода — зелёный.
4. **Тесты в стиле соседних** файлов `spec/`; мок клиента — `spec/support/game_mock.lua`, панели — `spec/support/bars_mock.lua` (задача 1), окно настроек — `spec/support/panel_mock.lua`. Соседние модули, которых ещё нет или которые пишет другой исполнитель, подменяются в своём спеке через `package.loaded.<модуль> = …` до `require`.
5. **Команды только в Docker:** `docker compose run --rm test busted spec/<file>_spec.lua`; в конце — весь набор `docker compose run --rm test busted --exclude-tags=perf`, он должен быть зелёным; исполнитель B — ещё `docker compose run --rm test busted --tags=perf`. На хосте Lua нет.
6. **Конвенции `AGENTS.md`:** Lua 5.1; в `src/` нельзя `pcall`, `loadstring`, `setfenv`, `getfenv`, `_G`, `SlashCmdList`, `package`, `io`, `debug` (даже в комментариях); тексты в игре — на английском; `src/spells_data.lua` руками не править; строка импорта ≤ `B.MAX_IMPORT`; правила «Поиск и скорость» (`src/search.lua` не трогать).
7. **Только API 3.3.5a** и **никаких записей в чужие кнопки** (Global Constraints плана): у кнопок Blizzard/ElvUI/LAB — только чтение, свои рамки — только поверх; своя рамка над лентой не берёт мышь. Сомнение в функции клиента — сверить с FrameXML 3.3.5a (`curl -s -m 30 https://raw.githubusercontent.com/wowgaming/3.3.5-interface-files/main/<файл>`) или кодом ElvUI (`/home/okada/whitemane/FrostmourneRebuffed/Interface/AddOns/ElvUI`, только читать), в отчёте — откуда.
8. **Комментарии в коде — по-английски**, плотность как в соседнем коде; объясняют «почему», а не «что».
9. **Коммит** — один или несколько в своей ветке, сообщение по-русски в стиле `git log` (`Аддон: …`), без номеров задач, без `Co-Authored-By`, «Generated with» и любых упоминаний ИИ. Не пушить, PR не открывать — ветки сводит интегратор.
10. **Git в копии репозитория:** если обёртка `rtk` отказывается работать в worktree — вызывать `/usr/bin/git` напрямую.
11. **Отчёт** (по-русски, кратко): ветка и коммиты; что сделано по пунктам «Выдаёт»; тесты — какие добавлены, итог прогона своих спеков и всего набора (числа); отклонения от плана и почему; что нужно проверить в игре; что не сделано.

**Общие файлы, возможны конфликты с параллельной работой** (разбор после боя идёт рядом): `addon/core.lua`, `addon/settings.lua`, `addon/panel.lua`, `tools/build.lua` (`B.ADDON_MODULES`), `spec/support/game_mock.lua`, `spec/addon_core_spec.lua`, `spec/addon_settings_spec.lua`, `spec/addon_panel_spec.lua`, `spec/build_spec.lua`, `README.md`, `.claude/rules/ARCHITECTURE.md`, `AGENTS.md`. Их меняет **только исполнитель E** (волна 2), правки — минимальные и перечислены в задаче 5 плана; волна 1 их не трогает. E идёт после слияния волны 1: `core` требует `helpers`, а он — все модули помощников, иначе сквозной тест сборки аддона красный.

## Волна 1 — параллельно, от `feat/stage1-focus`

### A. Кнопки панелей и подсветка (задачи 1 и 4 плана, по порядку)

- **Владеет:** `addon/actionbars.lua`, `spec/addon_actionbars_spec.lua`, новый `spec/support/bars_mock.lua`, `addon/highlight.lua`, `spec/addon_highlight_spec.lua`.
- **Опирается на:** `spec/support/game_mock.lua` (только использует); `cache.keyByName` движка — в тестах своя таблица имён.
- **Выдаёт:**
  - `actionbars.short(binding) -> string | nil` (`SHIFT-` → `S-`, `CTRL-` → `C-`, `ALT-` → `A-`, `MOUSEWHEELUP`/`DOWN` → `MwU`/`MwD`, `BUTTON<n>` → `M<n>`, `NUMPAD` → `N`, `PAGEUP`/`DOWN` → `PgU`/`PgD`, `SPACE` → `Spc`; `nil`/`""` → `nil`);
  - `actionbars.spellOfSlot(slot) -> name | nil` — `"spell"`: `GetSpellInfo(4-й ответ)`, без него `GetSpellName(id, "spell")`; `"macro"`: `GetMacroSpell(id)`; иначе `nil`; без `GetActionInfo` — `nil`;
  - источники `actionbars.blizzard` (`ActionButton`, `MultiBarBottomLeftButton`, `MultiBarBottomRightButton`, `MultiBarRightButton`, `MultiBarLeftButton` × 12; слот — поле `action`, иначе `ActionButton_GetPagedID`; привязка — `<buttonType или ACTIONBUTTON/MULTIACTIONBAR1..4BUTTON><i>`, иначе `CLICK <имя>:LeftButton`) и `actionbars.lab` (реестры `buttonRegistry` у `LibStub("LibActionButton-1.0", true)` и `LibStub("LibActionButton-1.0-ElvUI", true)`, без повторов, по имени кнопки; `_state_type`/`_state_action`, иначе `button:GetAction()`; привязка — `config.keyBoundTarget`, иначе `CLICK <имя>:LeftButton`) — оба `{ name, buttons(out) }`, только `IsVisible()` кнопки, запись `{ frame, name, spell, binding }`;
  - `actionbars.SOURCES = { actionbars.blizzard, actionbars.lab }`;
  - `actionbars.scan(keyByName, sources?) -> { [key] = { buttons = { entry… }, hotkey = short(первая найденная привязка) | nil } }`; без `LibStub` и без кнопок — `{}` без ошибок;
  - `bars_mock.install(cfg)`, `bars_mock.blizzard(name, slot, shown?)`, `bars_mock.elvui(bar, i, kind, action, bindTarget?)`, `bars_mock.labs` и `bars_mock.cfg` — как в задаче 1 плана; у кнопок мока `SetParent` ставит `parentSet = true`; рамки мока умеют `GetName`, `SetFrameLevel`/`GetFrameLevel`, `SetFrameStrata`/`GetFrameStrata`, `GetEffectiveScale` (поле `effScale`, по умолчанию 1), `IsMouseOver` (поле `mouseOver`);
  - подсветка (задача 4) — `view` в форме `core.view()` (`plan`, `S`, `at`, `cache.keyByName`, `frame`, `icon`, `active`), в тестах своя таблица; `actionbars.scan` в модульных тестах подменяется через `deps.scan`, в `#integration` — настоящий:
  - `highlight.OPTIONS` — `{ type = "toggle", key = "highlightButtons", name = "Light up the button to press on your action bars", default = true }`, `{ type = "toggle", key = "showKeybind", name = "Show its key on the big icon", default = true }`;
  - `highlight.due(view, now) -> key | nil` — первая кнопка плана из `spells.byKey`, до неё ≤ `highlight.AT = 0.3` с, цель — враг;
  - `highlight.new(deps)` (`deps = { view, config, now, scan? }`), `h:start(frame)` (события `highlight.EVENTS`, `OnUpdate`), `h:tick(dt)`, `h:hotkey(key) -> text | nil`, `h.overlays` (`{ [button] = frame }`, одна на кнопку на всю сессию), `h.keyText` (фонтстринг клавиши у нижнего края крупной иконки, `NumberFontNormal`);
  - пересканирование панелей — при событии и не чаще раза в `highlight.RESCAN = 1` с; у кнопок — только чтение (`GetWidth`, `GetFrameLevel`, `GetFrameStrata`, `GetEffectiveScale`), рамки-подсветки — на `UIParent`, `SetPoint("CENTER", button, "CENTER", 0, 0)`, уровень кнопки + 10, без мыши.
- **Принимается, если:** все тесты задач 1 и 4 зелёные; `actionbars` у кнопки только читает (`grep -n ":Set\|:Hook\|:Create" addon/actionbars.lua` пуст); в задаче 4 зелёные проверка «кнопка не тронута» и `#integration` с кнопкой ElvUI.

### B. Второе место и подсказка при наведении (задача 2 плана)

- **Владеет:** `src/planner.lua` (только две строки в `P:finish`), `spec/planner_spec.lua` (один новый тест), `addon/explain.lua`, `spec/addon_explain_spec.lua`.
- **Опирается на:** `search.evaluate`, `search.firstKey`, `search.HORIZON` (не менять `search`); `view` в форме `core.view()` (задача 5) — в тестах своя таблица; `spec/support/scenario.lua` (`Sc.state`, `Sc.randomStates`).
- **Выдаёт:**
  - `planner.alts` (= `result.byFirst` последнего законченного поиска) и `planner.altsNow` (= `S.now` этого поиска) — и при принятом новом плане, и при удержанном старом;
  - `explain.OPTION = { type = "toggle", key = "hoverTips", name = "Explain the big icon on mouse-over (Shift in combat)", default = true }`;
  - `explain.rivals(view, evaluate?, firstKey?)` → `nil` (нет первой кнопки, снимка, планировщика или план не переигрывается) | `{ value, horizon, second = nil | { key, afterSwing, value, loss, pct } }` — все цепочки `alts` других первых кнопок (не больше `explain.MAX_RIVALS = 12`, по имени ключа), сдвинутые на `S.now - altsNow`, на `planner:prepare(S)`; `pct = loss / |horizon| × 100`;
  - `explain.lines(view, elapsed, hotkey, rivals)` → `nil` | список `{ text, r, g, b }`: `"<Name> [<key>]"`, `"Press now"` / `"Press in 1.2 s"`, `"Why: <reason>"`, `"Then: A, B, C"`, `"Runner-up: <Name>[ after the swing] - N% worse over the next 6 s"` / `"… - about as good"` (меньше 1%) / `"No other first button comes close"`;
  - `explain.new(deps)` (`deps = { view, enabled, hotkey, now, inCombat, shift, tooltip, over?, evaluate?, firstKey? }`), `e:start(frame)`, `e:tick(dt)`, `e.hover`: опрос раз в `explain.POLL = 0.1` с; подсказка — вне боя по наведению, в бою — только с Shift; пересчёт — раз в `explain.REFRESH = 1` с или при смене первой кнопки; чужую подсказку не прячет (`tooltip:IsOwned`); у `e.hover` никогда не вызывается `EnableMouse`.
- **Принимается, если:** тесты задачи 2 зелёные, включая `#integration` и `#perf` («quick enough… ≤ 3 мс × `ENHROT_PERF_FACTOR`»); `spec/recorded_spec.lua`, `spec/stability_spec.lua`, `spec/leveling_spec.lua`, `spec/wowsims_spec.lua` и `--tags=perf` зелёные без правок ожиданий; `git diff src/search.lua` пуст; размер строки импорта — тест `build_spec` зелёный.

### C. «Всё ли готово» и ранги (задача 3 плана)

- **Владеет:** `addon/ready.lua`, `spec/addon_ready_spec.lua`.
- **Опирается на:** `src/spells.lua` (`KEYS`, `byKey`), `src/spells_data.lua` (`level`), `talents.spent`; `view` в форме `core.view()` (`S`, `cache.known`, `cache.names`, `cache.talents`) — в тестах своя таблица; клиентские `HasAction`, `GetMultiCastBarOffset`, `NUM_ACTIONBAR_PAGES` — в своём спеке через `_G`.
- **Выдаёт:**
  - `ready.OPTIONS` — `{ type = "toggle", key = "readyCheck", name = "Show the checklist on first login", default = true }`, `{ type = "toggle", key = "rankWarning", name = "Tell me when the trainer has new ranks", default = true }`;
  - `ready.ranks(level, known, names?)`, `ready.rankLine(list)` (`"the trainer has new ranks: Lightning Bolt 12, Earth Shock (new), +2 more - /dmr check"`, не больше `MAX_NAMES = 4` имён), `ready.items(info)` (ключи пунктов `mh`, `oh`, `shield`, `totems`, `talents`, `ranks`; тексты — как в тестах задачи 3), `ready.gather(view)` (Call of the Elements — слоты `(NUM_ACTIONBAR_PAGES + GetMultiCastBarOffset() - 1) × 12 + 1..4`, т. е. 133–136), `ready.window(items)` (рамка `DoubtMyRotationReady`, строки `w.rows[i] = { icon, label, hint }`), `ready.TALENT`, `ready.DELAY = 3`, `ready.ICON_OK`, `ready.ICON_NO`;
  - `ready.new(deps)` (`deps = { view, config, db, say, now, inCombat? }`), `checker:start(frame)` (события `PLAYER_LEVEL_UP`, `PLAYER_REGEN_ENABLED`, `OnUpdate`), `checker:onEvent(event, ...)`, `checker:tick()`, `checker:open()`: окно само — один раз (`db.readySeen`); при следующих входах, если хоть один пункт красный, — одна строка в чат `something is not ready yet - /dmr check` (раз за сессию, вне боя, под той же опцией `readyCheck`; тест на это обязателен), через `DELAY` после входа, не в бою (иначе — после `PLAYER_REGEN_ENABLED`), если `readyCheck ~= false`; строка про ранги — при входе и новом уровне (уровень — из аргумента события), одна и та же — раз за сессию, если `rankWarning ~= false`; открытое окно обновляется раз в `REFRESH = 1` с; нет снимка — повтор через 1 с, `open()` говорит `"no data yet - try again in a moment"`.
- **Принимается, если:** все тесты задачи 3 зелёные; окно не трогает `UISpecialFrames` и чужие рамки.

## Волна 2 — от `feat/stage1-focus` после слияния волны 1

### E. Связка и общие файлы (задача 5 плана)

- **Владеет:** `addon/helpers.lua`, `spec/addon_helpers_spec.lua`; из общих — только правки задачи 5: `addon/core.lua` (`withUpdate` + опции помощников, `M.view`, `M.helpers` в `login`, `check` в `handle`), `addon/settings.lua` (`ACTIONS.check`, строка `HELP`), `addon/panel.lua` (ключи в `M.SECTIONS`), `tools/build.lua` (пять модулей в `B.ADDON_MODULES` перед `core`), `spec/support/game_mock.lua` (имена `Highlight`, `Explain`, `Checks`, `Ready` в списке сброса), новые тесты в `spec/addon_core_spec.lua`, `spec/addon_settings_spec.lua`, `spec/addon_panel_spec.lua`, `spec/build_spec.lua` (блок `describe("addon build", …)`), `README.md`, `.claude/rules/ARCHITECTURE.md`, `AGENTS.md`.
- **Опирается на:** `highlight.OPTIONS/new/:start/:hotkey` (A), `explain.OPTION/new/:start` (B), `ready.OPTIONS/new/:start/:open` (C) — уже слиты; в `spec/addon_helpers_spec.lua` и `spec/addon_core_spec.lua` подменяются через `package.loaded`, сквозной тест сборки — с настоящими.
- **Выдаёт:**
  - `helpers.options()` — `highlightButtons`, `showKeybind`, `hoverTips`, `readyCheck`, `rankWarning` (в этом порядке);
  - `helpers.start(core, say) -> { highlight, explain, ready, check() }`, рамки `DoubtMyRotationHighlight`, `DoubtMyRotationExplain`, `DoubtMyRotationChecks` (берутся из `_G`, если уже есть);
  - `core.view() -> nil | { plan, S, at, cache, planner, frame, icon, active }` — одна таблица, перезаполняемая из `core.rt` при каждом вызове (`icon = rt.tl.icons[1]`, `at = rt.tl.at`, `active = not (sleeping or stopped or inactive)`);
  - `core.helpers` — создаётся один раз в `login` шамана после проверки обновлений; не шаману — нет; `/dmr check` → `core.helpers.check()`;
  - список опций аддона = опции сборки + `update.OPTION` + `helpers.options()`, без повторов по ключу, исходный список не меняется;
  - `settings.ACTIONS.check`, строка помощи `/dmr check - is everything ready (imbues, shield, totems, ranks)`;
  - `panel.SECTIONS`: General + `highlightButtons`, `showKeybind`, `hoverTips`; Advanced + `readyCheck`, `rankWarning`; новых страниц нет;
  - README (как пользоваться подсветкой, подсказкой с Shift, `/dmr check`, где выключить), карта (модули аддона, `core.view()`), `AGENTS.md` (конвенция «чужие кнопки — только чтение», «новый источник кнопок — `actionbars.SOURCES`»).
- **Принимается, если:** тесты задачи 5 зелёные; сквозной тест сборки аддона «runs as an addon without WeakAuras and draws a plan» с новыми проверками (рамки помощников есть, их `OnUpdate` проходит без ошибок в окружении без панелей) зелёный с настоящими модулями A, B, C; `lua tools/build.lua` даёт оба артефакта; карта ≤ ~150 строк; тексты документации — по-русски, нейтрально.

## Волна 3 — интегратор

Слить ветки волн в `feat/stage1-focus` (конфликты в общих файлах — сохраняя правки параллельной работы по разбору боя), весь набор `docker compose run --rm test busted` (с `perf`), сборка, проверка в игре по шагу 3 задачи 6 плана (результаты — в описание PR; расхождение мока с клиентом — исправить с тестом в спеке модуля), независимое ревью по Review Focus плана, PR в `main` с `[minor]` в сообщении мерж-коммита.
