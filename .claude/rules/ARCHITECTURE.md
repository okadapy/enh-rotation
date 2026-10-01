# ARCHITECTURE — DoubtMyRotation (EnhRot)

Подсказчик ротации энх-шамана для WotLK 3.3.5a: WeakAura (WeakAuras 5.22 backport) и аддон.
Движок — `src/`; `tools/build.lua` собирает из него строку импорта WeakAuras и папку аддона
(`src/` + `addon/` + `vendor/` в один `DoubtMyRotation.lua`).

## Стек

- Lua 5.1 — движок (песочница WeakAuras, клиент 3.3.5a) и аддон (`addon/`, Interface 30300); ограничения — в `AGENTS.md`.
- Тесты: busted 2.2.0-1 (`Dockerfile`), конфиг `.busted` (`ROOT = spec`, `lpath` — `src`, `addon`, `spec/support`, `tools`, `vendor`).
- Образ тестов: `nickblah/lua:5.1-luarocks-alpine` + `build-base unzip curl git python3` (`Dockerfile`).
- Сжатие и сериализация: `vendor/LibDeflate.lua`, `vendor/LibSerialize.lua` — строка импорта (инструменты) и экспорт снимков в аддоне (входят в его сборку).
- Python 3 — только генератор данных рангов `tools/spelldata.py`.
- CI: GitHub Actions — `release.yml` (релиз на каждый мерж в `main`: `DoubtMyRotation.txt` + `DoubtMyRotation-addon.zip`), `perf.yml` (скорость поиска), `claude.yml` (Claude по `@claude`).

## Команды

Всё — в контейнере `test` (`docker-compose.yml`, репозиторий смонтирован в `/work`):

- Все тесты: `docker compose run --rm test busted`
- Один файл: `docker compose run --rm test busted spec/<name>_spec.lua`
- Без скорости поиска: `docker compose run --rm test busted --exclude-tags=perf`
- Сборка: `docker compose run --rm test lua tools/build.lua` → `dist/DoubtMyRotation.txt` (аура), `dist/DoubtMyRotation/` (аддон)
- Разбор отчёта игрока: `docker compose run --rm test lua tools/report.lua <строка экспорта | WeakAuras.lua> [--baseline <git-ref>]`

Остальные команды (decode, import-snapshots, presses, spelldata) — в `AGENTS.md`.

## Дерево

```
src/            движок (общий для ауры и аддона), модули из tools/build.lua B.MODULES
addon/          вход аддона, настройки, окно, помощники (tools/build.lua B.ADDON_MODULES)
spec/           тесты busted (*_spec.lua)
  support/      моки клиента, заглушки модулей, сценарии, фикстуры состояний
  fixtures/     recorded.lua — снимки из игры
tools/          build.lua (сборка ауры и аддона), report.lua (разбор отчётов),
                aura.lua (описание ауры, опции), encode.lua, spelldata.py
vendor/         LibDeflate, LibSerialize (входят в аддон)
docs/           development.md, wago.md, superpowers/{specs,plans} (дизайн и планы)
data/           Spell.dbc клиента (*.dbc не в git)
dist/           результат сборки: DoubtMyRotation.txt, DoubtMyRotation/ (не в git)
.github/workflows/  release.yml, perf.yml, claude.yml
README.md       инструкция игроку (аура и аддон)
AGENTS.md       вход для агентов (.claude/CLAUDE.md — симлинк)
```

## Модули (`src/`)

Подробных описаний в `.claude/docs/modules/` пока нет — строки-заглушки.

| Модуль | Роль | Док |
|---|---|---|
| `util` | общие помощники | — |
| `spells_data` | ранги заклинаний, сгенерирован `tools/spelldata.py` (руками не править) | — |
| `spells` | статичные факты заклинаний, которых нет в данных клиента | — |
| `talents` | таланты, влияющие на урон, цены и кулдауны | — |
| `raid` | дебаффы рейда на цели и баффы группы → `S.mods` (только аддон) | — |
| `gear_data` | комплекты T7–T10, реликвии (постоянные и с проком), символы (только аддон) | — |
| `gear` | экипировка и символы → добавки `S.mods` (только аддон) | — |
| `swing` | учёт автоатак (таймер ударов) | — |
| `enemies` | счёт врагов в мили и рядом по боевому логу | — |
| `ttd` | время до смерти цели (регрессия + начальная оценка) | — |
| `damage` | ожидаемый урон действий по одной цели | — |
| `model` | модель переходов состояния: нажатие / ожидание | — |
| `value` | оценка цепочки действий: урон, цена маны, конечное состояние | — |
| `search` | поиск плана (луч), подписи под иконкой | — |
| `planner` | смена показанного плана с гистерезисом | — |
| `snapshot` | снимок состояния `S` из API игры | — |
| `timeline` | лента времени и часы ударов, режим одной кнопки (`compact`) | — |
| `recorder` | запись снимков для отчёта об ошибке | — |
| `version` | версия аддона (подставляет сборка) | — |
| `runtime` | события, алерты, связка модулей в игре | — |

API игры читают только `snapshot`, `runtime`, `timeline`; `raid`, `gear`, `gear_data` — чистые модули, их вызывает `snapshot`.

Модули с пометкой «только аддон» (`tools/build.lua` `B.ADDON_SRC`) и блоки `--@addon` … `--@end` в сборку ауры не входят: аура — тот же движок без них (правила — в `AGENTS.md`). Поток: `snapshot` читает дебаффы цели, баффы игрока, свои тотемы земли и воздуха → `raid.effects`; экипировку и символы — при входе и по событиям `runtime.REGEAR` → `gear.effects`; итог — `S.mods`, его читают `damage`, `model`, `value`.

## Аддон (`addon/`)

Хозяин движка вместо WeakAuras: рамка (`env.region`), SavedVariables `DoubtMyRotationDB` (аккаунт: `config` прежней версии, `profiles`, `ui`, `wizardOff`) и `DoubtMyRotationCharDB` (персонаж: выбранный профиль, правила автовыбора, место ленты, мастер, карточки), `env.show`, `env.libs`.

| Модуль | Роль | Док |
|---|---|---|
| `settings` | чистые функции: значения по умолчанию, слияние с сохранёнными, разбор `/dmr` | — |
| `panel` | окно настроек в Interface → AddOns: страницы General / Combat / Advanced | — |
| `update` | «вышла новая версия» по сообщениям аддона от других игроков | — |
| `actionbars` | кнопки панелей (`SOURCES`: Blizzard, LibActionButton/ElvUI) → заклинание и клавиша; только чтение | — |
| `highlight` | рамка-подсветка над нужной кнопкой и её клавиша на крупной иконке | — |
| `explain` | подсказка при наведении на крупную иконку: почему и второе место (`planner.alts`) | — |
| `ready` | окно «всё ли готово» (`/dmr check`) и строка про новые ранги | — |
| `helpers` | опции помощников и их запуск из `core` на своих рамках | — |
| `profiles` | профили и их выбор (переход со старой версии, автовыбор по месту и уровню); чистые функции | — |
| `profilepage` | страница Profiles под окном настроек | — |
| `guide` | очередь сообщений: одно окно за раз, только вне боя | — |
| `wizard` | мастер первого запуска (4 экрана) | — |
| `cards` | карточки «что нового» на 10–80 уровнях, числа — из данных заклинаний | — |
| `coach` | когда показывать мастер и карточки | — |
| `minimap` | кнопка у миникарты | — |
| `skin` | стиль ElvUI для своих окон (если ElvUI стоит) | — |
| `core` | вход: события загрузки, рамка, SavedVariables `DoubtMyRotationDB` (аккаунт) и `DoubtMyRotationCharDB` (персонаж), `/dmr`, запуск `runtime.start`, помощников и окон | — |

Новые окна получают от `core` таблицу-хост (свои функции), а не глобальные переменные. Помощники читают движок только через `core.view()` (план, `S`, кэш, планировщик, крупная иконка; одна таблица, перезаполняется при каждом вызове).

### Базовый образ

Отсутствует — проект не использует пред-собранный base image для кэша зависимостей.

### Первичные ключи

Не применимо — в проекте нет базы данных.
