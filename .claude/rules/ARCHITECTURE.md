# ARCHITECTURE — DoubtMyRotation (EnhRot)

WeakAura-подсказчик ротации энх-шамана для WotLK 3.3.5a (WeakAuras 5.22 backport). Код ауры —
`src/`, собирается в одну строку импорта WeakAuras (`tools/build.lua`).

## Стек

- Lua 5.1 — код ауры (песочница WeakAuras, клиент 3.3.5a); ограничения — в `AGENTS.md`.
- Тесты: busted 2.2.0-1 (`Dockerfile`), конфиг `.busted` (`ROOT = spec`, `lpath` — `src`, `spec/support`, `tools`, `vendor`).
- Образ тестов: `nickblah/lua:5.1-luarocks-alpine` + `build-base unzip curl git python3` (`Dockerfile`).
- Сжатие и сериализация строки импорта: `vendor/LibDeflate.lua`, `vendor/LibSerialize.lua`.
- Python 3 — только генератор данных рангов `tools/spelldata.py`.
- CI: GitHub Actions — `release.yml` (релиз на каждый мерж в `main`), `perf.yml` (скорость поиска), `claude.yml` (Claude по `@claude`).

## Команды

Всё — в контейнере `test` (`docker-compose.yml`, репозиторий смонтирован в `/work`):

- Все тесты: `docker compose run --rm test busted`
- Один файл: `docker compose run --rm test busted spec/<name>_spec.lua`
- Без скорости поиска: `docker compose run --rm test busted --exclude-tags=perf`
- Сборка: `docker compose run --rm test lua tools/build.lua` → `dist/DoubtMyRotation.txt`
- Разбор отчёта игрока: `docker compose run --rm test lua tools/report.lua <строка экспорта | WeakAuras.lua> [--baseline <git-ref>]`

Остальные команды (decode, import-snapshots, presses, spelldata) — в `AGENTS.md`.

## Дерево

```
src/            код ауры, модули из tools/build.lua B.MODULES
spec/           тесты busted (*_spec.lua)
  support/      моки клиента, заглушки модулей, сценарии, фикстуры состояний
  fixtures/     recorded.lua — снимки из игры
tools/          build.lua (сборка), report.lua (разбор отчётов), aura.lua (описание ауры),
                encode.lua, spelldata.py
vendor/         LibDeflate, LibSerialize
docs/           wago.md (описание для wago), superpowers/{specs,plans} (дизайн и план)
data/           Spell.dbc клиента (*.dbc не в git)
dist/           результат сборки (не в git)
.github/workflows/  release.yml, perf.yml, claude.yml
README.md       инструкция игроку
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
| `swing` | учёт автоатак (таймер ударов) | — |
| `enemies` | счёт врагов в мили и рядом по боевому логу | — |
| `ttd` | время до смерти цели (регрессия + начальная оценка) | — |
| `damage` | ожидаемый урон действий по одной цели | — |
| `model` | модель переходов состояния: нажатие / ожидание | — |
| `value` | оценка цепочки действий: урон, цена маны, конечное состояние | — |
| `search` | поиск плана (луч), подписи под иконкой | — |
| `planner` | смена показанного плана с гистерезисом | — |
| `snapshot` | снимок состояния `S` из API игры | — |
| `timeline` | лента времени и часы ударов | — |
| `recorder` | запись снимков для отчёта об ошибке | — |
| `version` | версия аддона (подставляет сборка) | — |
| `runtime` | события, алерты, связка модулей в игре | — |

API игры читают только `snapshot`, `runtime`, `timeline`.

### Базовый образ

Отсутствует — проект не использует пред-собранный base image для кэша зависимостей.

### Первичные ключи

Не применимо — в проекте нет базы данных.
