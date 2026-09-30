# EnhRot

WeakAura-подсказчик для энх-шамана под WotLK 3.3.5a (WeakAuras 5.22 backport): мини-симулятор боя на 6 с вперёд, лента времени, часы ударов. Инструкция для игрока — `README.md`.

- Тесты: `docker compose run --rm test busted`
- Один файл: `docker compose run --rm test busted spec/<name>_spec.lua`
- Без интеграционных (настоящие соседние модули): `docker compose run --rm test busted --exclude-tags=integration`
- Сборка строки импорта: `docker compose run --rm test lua tools/build.lua` → `dist/EnhRot.txt` (`dist/` не в git)
- Декодировать строку: `docker compose run --rm test lua tools/build.lua decode <file>`
- Снимки из игры в тесты: `docker compose run --rm test lua tools/build.lua import-snapshots <WeakAuras.lua>` → `spec/fixtures/recorded.lua`
- Сводка журнала нажатий из отчёта: `docker compose run --rm test lua tools/build.lua presses <файл>` (строка экспорта или `WeakAuras.lua`)
- Версия в сборке: `RELEASE_TAG`, иначе `git describe --tags`, иначе `dev` (подставляется вместо `src/version.lua`)
- Разбор отчёта об ошибке: `docker compose run --rm test lua tools/report.lua <строка экспорта | WeakAuras.lua | фикстура> [--baseline <git-ref | фикстура>] [--save <файл>]` — по строке на снимок (план из игры и `search.best` сейчас) и сводка: расхождения, дрожание у умирающих мобов, подсказки, мана по мобам, нажатия. Логика — чистые функции `report.analyze` / `report.format` (`spec/report_spec.lua`)
- Перегенерировать данные рангов: `docker compose run --rm test python3 tools/spelldata.py data/Spell.dbc src/spells_data.lua`
  (`data/Spell.dbc` — из `rebuffed.mpq` клиента, в git не хранится)
- Claude в GitHub: `.github/workflows/claude.yml` — `@claude` в issue/комментарии/ревью (владелец и участники); там нет Lua локально, тесты — через `docker compose`.
- Дизайн: `docs/superpowers/specs/2026-09-30-enh-rotation-design.md`; план: `docs/superpowers/plans/2026-09-30-enh-rotation.md`

Конвенции:
- Lua 5.1. В `src/` нельзя `pcall`, `loadstring`, `setfenv`, `getfenv`, `_G`, `SlashCmdList` — песочница WeakAuras; и `package`, `io`, `debug` — их нет в клиенте (проверяет `spec/build_spec.lua`, даже в комментариях). Интеграционный тест сборки запускает её без этих библиотек.
- API игры читают только `snapshot`, `runtime`, `timeline`; остальные модули — чистые функции над `S`.
- Тексты в игре — на английском. Новый модуль в `src/` — добавить в `tools/build.lua` `B.MODULES`.
- `src/spells_data.lua` не править руками.
- Git и GitHub: без подписи ИИ — никаких `Co-Authored-By`, «Generated with …», ссылок на сессию в коммитах, PR и комментариях. Ветки — `fix/<что чиним>` или `feat/<что добавляем>`, латиницей через дефис, одна задача на ветку.
- Общие помощники — `src/util.lua`; заглушки соседних модулей — `spec/support/stubs.lua`; сценарии по уровню для проверочных спеков — `spec/support/scenario.lua`; мок API клиента — `spec/support/game_mock.lua`.

Поиск и скорость (`spec/perf_spec.lua`, `--tags=perf`: на 150 реалистичных состояниях 80 уровня поиск в среднем ≤ 6 мс = 3 кадра × 2 мс, сейчас ~5,0 мс и ~142/150 в 3 кадра; работа ≤ 600 тыс. инструкций Lua на поиск, сейчас ~460; мусор ≤ 300 КБ на поиск, сейчас ~170):
- CI: `.github/workflows/perf.yml` (PR и `main`, отдельно от релиза). Инструкции и мусор от машины не зависят — шаг падает; время (тест `#timing`) — с `ENHROT_PERF_FACTOR=2` (лимиты мс и кадр `BUDGET_MS` × 2), при сбое только предупреждение. Release гоняет тесты с `--exclude-tags=perf`.
- Поиск не обрезается по времени: он останавливается только по `search.NODE_CAP` (число кандидатов), поэтому результат не зависит от скорости компьютера. В игре он идёт кусками по `BUDGET_MS` за кадр (`search.start` → `job:run(ms)`, сопрограмма); `planner` меняет показанный план только когда поиск закончен. `search.best` — тот же поиск целиком (тесты).
- Паузы (`check()`) — только там, где не держится временное состояние `model.peek*`.
- В каждом слое луча, кроме `BEAM` лучших, остаётся лучшая цепочка каждой первой кнопки (если она не хуже лучшей больше чем на `DIVERSITY`).
- После луча `fillIdle` пробует готовые кнопки в паузах плана ≥ `IDLE_MIN` — для лучших цепочек всех первых кнопок в пределах `FILL_MARGIN`, не больше `FILL_REPLAYS` повторов; побеждает лучшая после заполнения.
- «Ждать удар, потом каст» строится только для каста со временем произнесения (мгновенный на 5 стаках ничего не сбивает).
- Кандидаты считаются на рабочих копиях без выделения памяти: `model.peekApply` / `model.peekWait` (два буфера, результат живёт до следующего вызова; `model.peekApplyOver` — нажатие после паузы прямо в буфере паузы), настоящие состояния (`model.apply` / `wait`) строятся только для узлов луча и узла паузы в `fillIdle` (повторы плана в `replay` без `gapFrom` — тоже на рабочих копиях). Обе дороги должны давать одинаковые числа (тест в `spec/model_spec.lua`). Узлы поиска не меняются никогда: на этом держится быстрое повторное заполнение буфера из того же узла (`fillScratch` копирует только кулдауны и записи, которые переключил `setCd`).
- Арена: настоящие состояния поиска, их записи заклинаний (`tickSpells`/`setCd`) и таблицы `player` (`setMana`) берутся из списков свободных (`S.memo.arena`, `model.newArena`), а в конце поиска (`search` → `run`) возвращаются `model.release`. Результат поиска их не держит; поиск, поставленный на паузу, и другой поиск между его кусками друг другу не мешают (у каждого своя арена). `fillState` заполняет таблицу арены ровно как `cloneState` — поле, добавленное в `cloneState`, добавить и туда (тест с «часовым» в `spec/model_spec.lua` это ловит). Свои таблицы у копии (`buffs.ls`, `target.ss`, `totems.fire`, `pets`) `applyOn` меняет на месте, недостающие берёт из запасных (`spareOf`). Без арены (`search.evaluate`, тесты, прямые вызовы) всё выделяется как раньше. Записи кандидатов в пул не вынесены: в Lua 5.1 это медленнее (присваивание `nil` отсутствующему ключу вставляет ключ).
- Рабочие копии не держат заклинаний «в полёте» (`inflight`): в поиске их никто не читает. `model.waitKeepsMana` — хвост до горизонта не меняет ману (нет Shamanistic Rage): `scoreFrom` не считает `manaPrice`. `peekApply`/`peekApplyOver` принимают готовое время каста (`candidate` уже посчитал его для горизонта).
- Ускорения — только с тем же результатом бит в бит (`value`, `nodes`, шаги) на `spec/fixtures/recorded.lua`, 150 состояниях perf и сценариях 10–80 уровней: порядок операций с плавающей точкой не менять.
- `search.best` кладёт в корень `S.memo`: кэш урона на один поиск (`damage` — `memoize`, `rates`, `swingStats`, `actionTable`). Всё, что в поиске не меняется (характеристики, оружие, таланты, уровень цели), можно кэшировать; зависимость от зарядов Lightning Shield / Stormstrike — через «флаги».
- Действие у края горизонта двигает время только до горизонта; каст должен закончиться внутри горизонта.

Сверка с wowsims (`spec/wowsims_spec.lua`) и прокачка (`spec/leveling_spec.lua`): при расхождении сначала искать ошибку в `damage`/`model`/`value`/`search`; менять ожидание можно только через `alt` с конкретной причиной (механика или формула). Подгонять под отдельные тестовые состояния в `src/` нельзя.
