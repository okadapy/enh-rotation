# EnhRot

WeakAura-подсказчик для энх-шамана под WotLK 3.3.5a (WeakAuras 5.22 backport): мини-симулятор боя на 6 с вперёд, лента времени, часы ударов.

- Тесты: `docker compose run --rm test busted`
- Один файл: `docker compose run --rm test busted spec/<name>_spec.lua`
- Сборка строки импорта: `docker compose run --rm test lua tools/build.lua` → `dist/EnhRot.txt`
- Декодировать чужую строку: `docker compose run --rm test lua tools/build.lua decode path/to/file.txt`
- Перегенерировать данные рангов: `docker compose run --rm test python3 tools/spelldata.py data/Spell.dbc src/spells_data.lua`
  (`data/Spell.dbc` — из `rebuffed.mpq` клиента, в git не хранится)
- Дизайн: `docs/superpowers/specs/2026-09-30-enh-rotation-design.md`
- План: `docs/superpowers/plans/2026-09-30-enh-rotation.md`

Конвенции:
- Lua 5.1.
- В `src/` нельзя `pcall`, `loadstring`, `setfenv`, `getfenv`, `_G` (песочница WeakAuras).
- API игры читают только `snapshot`, `runtime`, `timeline`; остальные модули — чистая логика.
- Тексты в игре — на английском.
- `src/spells_data.lua` не править руками.
- Общие помощники — `src/util.lua` (`copy`, `merge`, `clamp`); заглушки соседних модулей для тестов — `spec/support/stubs.lua`.
