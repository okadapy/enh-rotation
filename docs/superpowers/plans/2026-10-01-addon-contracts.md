# Аддон: контракты исполнителей

Работа по плану `docs/superpowers/plans/2026-10-01-addon.md` разбита на исполнителей. Каждый работает в своей копии репозитория (git worktree) и своей ветке и сдаёт работу по этому контракту. Код и тесты в плане — образец; отклонения от него допустимы, только если интерфейс из раздела «Выдаёт» остаётся как в контракте, и о каждом отклонении сказано в отчёте.

## Общий контракт (для всех)

1. **Только свои файлы.** Менять можно только файлы из раздела «Владеет». Нужна правка чужого файла — не делать, написать в отчёте, что и зачем.
2. **Интерфейс точно как в контракте.** Имена, параметры, возвращаемые значения, имена глобальных переменных и рамок из раздела «Выдаёт» — без изменений, на них опираются другие исполнители.
3. **Сначала тест.** Тест пишется до кода и сначала падает по правильной причине; после кода — зелёный.
4. **Тесты в стиле соседних** файлов `spec/`, мок клиента — `spec/support/game_mock.lua`.
5. **Команды только в Docker:** `docker compose run --rm test busted spec/<file>_spec.lua`; в конце — весь набор `docker compose run --rm test busted --exclude-tags=perf`, он должен быть зелёным. На хосте Lua нет.
6. **Конвенции `AGENTS.md`:** Lua 5.1; в `src/` нельзя `pcall`, `loadstring`, `setfenv`, `getfenv`, `_G`, `SlashCmdList`, `package`, `io`, `debug` (даже в комментариях); тексты в игре — на английском; `src/spells_data.lua` руками не править; строка импорта ≤ `B.MAX_IMPORT`.
7. **Комментарии в коде — по-английски**, плотность как в соседнем коде; объясняют «почему», а не «что».
8. **Коммит** — один или несколько в своей ветке, сообщение по-русски в стиле `git log` (`Аддон: …`), без номеров задач, без `Co-Authored-By`, «Generated with» и любых упоминаний ИИ. Не пушить, PR не открывать — ветки сводит интегратор.
9. **Git в копии репозитория:** если обёртка `rtk` отказывается работать в worktree — вызывать `/usr/bin/git` напрямую.
10. **Отчёт** (по-русски, кратко): ветка и коммиты; что сделано по пунктам «Выдаёт»; тесты — какие добавлены, итог прогона своих спеков и всего набора (числа); отклонения от плана и почему; что не сделано.

## Волна 1 — параллельно, от `feat/addon`

### A. Хозяин движка (задача 1 плана)

- **Владеет:** `src/runtime.lua`, `spec/runtime_spec.lua`, функция `B.initCode` в `tools/build.lua` (и только она), тесты `B.initCode` в `spec/build_spec.lua` (блок `describe("build #integration", …)`: существующие тесты ауры и новый тест защиты).
- **Выдаёт:**
  - движок не обращается к `WeakAuras` нигде в `src/`, кроме комментариев: сигнал «покажи хозяина» — `env.show` (`function()` или `nil`), вызывается там, где раньше был `WeakAuras.ScanEvents("ENHROT_SHOW")`;
  - `runtime.exportLibs(env) -> { serialize, deflate } | nil` — сначала `env.libs`, потом LibStub; `runtime.showExport(env)` передаёт `env`;
  - `B.initCode(srcDir, version)` — первая строка `if DoubtMyRotationAddon then print('DoubtMyRotation: the addon is installed, this aura stays idle') return end`, затем `B.bundle(...)`, затем `aura_env.show = function() WeakAuras.ScanEvents('ENHROT_SHOW') end`, затем запуск `runtime.start`.
- **Принимается, если:** тесты задачи 1 плана («without env.show (the addon) it never calls WeakAuras», «export uses env.libs …») и тест «the aura stays idle when the addon is installed» из задачи 5 плана зелёные; «runs as a WeakAuras init action and draws a plan» и «round-trips the import string» по-прежнему зелёные; `grep -n "WeakAuras\." src/*.lua` пуст.

### B. Настройки (задача 2 плана + `snap` и `help` из задачи 4)

- **Владеет:** `addon/settings.lua`, `spec/addon_settings_spec.lua`, `.busted` (только `lpath`: добавить `addon/?.lua`).
- **Выдаёт:** `settings.defaults(options)`, `settings.valid(o, v)`, `settings.merge(options, saved)`, `settings.coerce(o, text)`, `settings.snap(o, v)`, `settings.command(options, config, msg)`, `settings.HELP`, `settings.ACTIONS` — как в плане, с одним уточнением из задачи 4: **пустая строка в `settings.command` — помощь не печатает**, а возвращает `{ lines = {}, changed = false, action = "open" }` (окно настроек открывает вход аддона); помощь — по `help` и по неизвестной команде.
- **Принимается, если:** все тесты задачи 2 плана (с поправкой: «an empty line is help» → «an empty line asks to open the window, help prints help») и тест `snap` из задачи 4 зелёные.

### D. Сборка аддона (задача 5 плана, без защиты ауры и без сквозного теста)

- **Владеет:** в `tools/build.lua` — `B.ADDON`, `B.ADDON_DIR`, `B.ADDON_MODULES`, `B.addonOptions`, `B.addonCode`, `B.addonToc`, запись аддона в `B.main` (не трогать `B.initCode`); новые тесты в `spec/build_spec.lua` — отдельным блоком `describe("addon build", …)` в конце файла.
- **Выдаёт:**
  - `B.ADDON = "DoubtMyRotation"`, `B.ADDON_DIR = "dist/DoubtMyRotation"`;
  - `B.ADDON_MODULES = { {"LibSerialize","vendor/LibSerialize.lua"}, {"LibDeflate","vendor/LibDeflate.lua"}, {"settings","addon/settings.lua"}, {"panel","addon/panel.lua"}, {"core","addon/core.lua"} }`;
  - `B.addonOptions() -> { list, width, height }` (опции `tools/aura.lua` без `export`);
  - `B.addonCode(srcDir, version, modules) -> string` — `modules` по умолчанию `B.ADDON_MODULES`; в конце вызывает `__require('core').boot({ options = …, width = …, height = …, libs = { serialize = __require('LibSerialize'), deflate = __require('LibDeflate') } })`;
  - `B.addonToc(version) -> string` — как в плане;
  - `lua tools/build.lua` пишет `dist/DoubtMyRotation.txt` и `dist/DoubtMyRotation/DoubtMyRotation.{toc,lua}`; если файлов `addon/*.lua` ещё нет — сборка аддона пропускается с одной строкой в выводе, строка ауры собирается как раньше.
- **Принимается, если:** тесты toc и `addonOptions` из задачи 5 плана зелёные; новый тест: `B.addonCode("src", "v0", { {"LibSerialize", …}, {"LibDeflate", …} })` проходит `loadstring` (проверка лимитов Lua 5.1 на переменные и upvalues обёрнутых библиотек), а выполненный в окружении клиента без `LibStub` чанк отдаёт рабочие `LibSerialize`/`LibDeflate` (сериализовать и сжать таблицу, развернуть обратно); `core.boot` в этом тесте подменить: модуль `core` из фикстуры-строки `return { boot = function(o) BOOTED = o end }` через параметр `modules` (файл фикстуры — `spec/fixtures/addon_core_stub.lua`, тоже во владении D). Если обёртка библиотек не проходит `loadstring` — перейти на запасной вариант плана (библиотеки отдельными файлами в `.toc`) и подробно описать это в отчёте.

### E. Релиз и документация (задача 6 плана)

- **Владеет:** `.github/workflows/release.yml`, `README.md`, `AGENTS.md`, `.claude/rules/ARCHITECTURE.md`.
- **Выдаёт:** релиз собирает и выкладывает `DoubtMyRotation.txt` и `DoubtMyRotation-addon.zip` одной версии (проверка `## Version: $RELEASE_TAG` в `.toc`); в описании релиза — установка аддоном; README — второй способ установки, окно настроек (General / Combat / Advanced), таблица команд `/dmr` (`/dmr` — окно, `help`, `list`, `set`, `reset`, `export`, `lock`/`unlock`, `show`/`hide`), «аура и аддон вместе — работает аддон»; `AGENTS.md` — команда сборки с двумя артефактами и конвенция про `addon/`; карта — `addon/` в дереве, таблица модулей аддона (`settings`, `panel`, `core`), `lpath` в стеке.
- **Принимается, если:** `docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:latest .github/workflows/release.yml` не даёт новых замечаний (старые SC2129/SC2016 — не наши); README и карта не дублируют друг друга; карта ≤ ~150 строк; тексты по-русски, нейтрально.

## Волна 2 — параллельно, от `feat/addon` после слияния волны 1

### C1. Вход аддона (задача 3 плана + `core`-часть задачи 4)

- **Владеет:** `addon/core.lua`, `spec/addon_core_spec.lua`, `spec/support/game_mock.lua` (только добавления для аддона: `UnitClass`, `SlashCmdList`, сброс глобальных `DoubtMyRotation*`, `GetPoint`, `ClearAllPoints`, `SetHeight`, `StartMoving`, `IsMouseEnabled`, `IsShown`, `InterfaceOptionsFrame_OpenToCategory` → `G.opened`).
- **Опирается на:** `runtime.start/showExport` (A), `settings.*` (B); `panel.new(o, host) -> frame` — **подменяется в своих тестах** через `package.loaded.panel = { new = function(o, host) … return CreateFrame("Frame", "DoubtMyRotationPanel") end }` до `require("core")`.
- **Выдаёт:** `core.boot(o)`, `core.load(o)`, `core.login(o)`, `core.handle(o, msg)`, `core.apply(delay)`, `core.host(o)`; глобальные `DoubtMyRotationAddon`, `DoubtMyRotationDB`, `SLASH_DOUBTMYROTATION1 = "/dmr"`, `SlashCmdList.DOUBTMYROTATION`; рамки `DoubtMyRotationLoader`, `DoubtMyRotationFrame`, `DoubtMyRotationTimer`; хост окна — `{ config, set, replace, action, label }` как в плане; `action = "open"` из `settings.command` открывает окно (`InterfaceOptionsFrame_OpenToCategory` дважды).
- **Принимается, если:** все тесты задачи 3 плана и тесты core из задачи 4 («/dmr alone opens the settings window», «many changes in a row restart the engine once, after the pause») зелёные.

### C2. Окно настроек (`panel`-часть задачи 4)

- **Владеет:** `addon/panel.lua`, `spec/addon_panel_spec.lua`, новый `spec/support/panel_mock.lua` (ползунки, галочки, кнопки с `SetText`, выпадающие списки, `InterfaceOptions_AddCategory` → `G.categories`, `G.menu(frame)`) — ставится из своего спека после `G.install`; `game_mock.lua` не трогать.
- **Опирается на:** `settings.defaults`, `settings.snap` (B); хост `{ config, set, replace, action, label }` (тесты дают свой).
- **Выдаёт:** `panel.SECTIONS`, `panel.new(o, host) -> main frame` с `main.pages`, `main.controls`, `main.buttons`; страницы `DoubtMyRotationPanel` (`name = "DoubtMyRotation"`), `DoubtMyRotationPanelCombat`, `DoubtMyRotationPanelAdvanced` (`parent = "DoubtMyRotation"`); `refresh`/`okay`/`cancel`/`default` на каждой странице с общим состоянием; `host.quiet`, выставленный окном.
- **Принимается, если:** все тесты окна из задачи 4 плана зелёные, включая «three pages …», «an option of no section goes to Advanced», «the real options all have a section», «cancel puts back …»; шаблоны — только существующие в 3.3.5a (`OptionsSliderTemplate`, `InterfaceOptionsCheckButtonTemplate`, `UIDropDownMenuTemplate`, `UIPanelButtonTemplate`).

## Волна 3 — интегратор

Слить ветки волн в `feat/addon`, сквозной тест задачи 5 «runs as an addon without WeakAuras and draws a plan», весь набор тестов, сборка (`lua tools/build.lua` → оба артефакта), независимое ревью ветки, PR в `main` с `[minor]` в сообщении мерж-коммита.
