# Состояние архитектуры

Справочник для проверки «есть ли это уже»: что реализовано, что частично, какие долги и куда развивать архитектуру. Решения владельца и открытые игровые вопросы — в [DECISIONS.md](../DECISIONS.md). Контракты реализованных подсистем описаны в тематических документах; история отдельных задач и их проверок — в `git log`.

При изменении архитектурного контракта обновлять строки таблиц и списков этого файла, а не дописывать журнал задачи.

## Реализовано

### Ядро боя

| Возможность | Основные классы | Контракт |
| --- | --- | --- |
| Независимое ядро | `BattleEngine`, `BattleState`, команды и события без сцены | [README.md](README.md), [BATTLE.md](BATTLE.md) |
| Атомарное создание боя | `BattleSetupFactory`, `BattleSessionFactory` | BATTLE.md «Граница запуска» |
| Read-only граница | `UnitSnapshot`, копия `HexGrid`, глубокая копия setup | BATTLE.md «Владение состоянием» |
| Общий путь игрока и ИИ | `BattleCommand` → `BattleSession.step()` | BATTLE.md «Команды и результат шага» |
| Порядок границ хода | `BattleEngine._end_turn()`, `TurnEndedEvent.was_skipped` | BATTLE.md «Порядок границ хода» |
| Аварийная остановка | `BattleResolution.terminal_error`, однократные `battle_failed`/`battle_finished`, восстановление отображения | BATTLE.md «Уточнения после регрессионной проверки» |
| Произвольная карта | `BattleMapDefinition`, `HexGrid`: отверстия, острова, отрицательные координаты | BATTLE.md «Карта» |
| Изменяемая карта | `MapMutationService`: атомарные пакеты add/remove/change/set traversal, ревизии | BATTLE.md «Изменение карты» |
| Препятствия местности | `BattleObstacleDefinition`, `ObstacleService`, `AttackObstacleCommand` | BATTLE.md, EDITOR.md «Препятствия местности» |
| Статусы и состояния гексов | 8 статусов с уровнями, 12 состояний гексов, матрица, распространение, срок 3 раунда | [HEX_AND_UNIT_STATES.md](HEX_AND_UNIT_STATES.md) |
| Типы урона и формула | physical/electric/water/fire/acid/plasma; `UnitDamagedEvent.damage_modifiers` | BATTLE.md «Боевой лог», HEX_AND_UNIT_STATES.md |
| Завершение хода действием, КД, призыв | `UnitState.ability_cooldowns`, `core:summon`, `UnitSummonedEvent` | BATTLE.md «Завершение действий, кулдауны и призыв» |
| Способности | `AbilityDefinition`, `TargetMode`, `AbilityExecutor`, effect handlers, `ModAPI` | BATTLE.md «Способности» |
| Умения копья и ответный удар | `core:spear_throw/sweep/pin`, `core:melee_retaliation`, `pending_spear_return` | BATTLE.md «Копьё и ответный удар» |
| Пассивы | `PassiveAbilityCatalog` и авторские `passive_definitions` | BATTLE.md «Юниты», [CONTENT_AND_MODS.md](CONTENT_AND_MODS.md) |
| Трупы в состоянии боя | `BattleState.get_corpses_at()` | BATTLE.md «Смерть и трупы» |
| ИИ | `EnemyBrain`, `MovementImpactForecast`, `AILastActionPlanner`, атака мешающих препятствий | BATTLE.md «Команды и результат шага» |

### Контент

| Возможность | Основные классы | Контракт |
| --- | --- | --- |
| Пакеты контента | `ContentPackage`, manifests, зависимости, `ContentLoader`, `ContentSnapshot`, `ContentLock` | CONTENT_AND_MODS.md |
| Изоляция snapshot | Копии определений и setup, замороженный реестр `ModAPI` | CONTENT_AND_MODS.md «Изоляция и проверка ссылок» |
| Авторский контент проекта | `content/authored/`, `UnitLibrary`, `SkillLibrary`, `ProjectBattleLoader`, `content/game_content.tres` | CONTENT_AND_MODS.md, [EDITOR.md](EDITOR.md) |
| Разделение логики и визуала | `presentation_id` у юнитов и способностей, `UnitPresentationDefinition`, `AbilityPresentationDefinition`, fallback | BATTLE.md «Юниты», «Способности» |

### Графический бой

| Возможность | Основные классы | Контракт |
| --- | --- | --- |
| Адаптер боя | `BattleScreen`, `BattleController`, `BattlePresentationQueue`, `BattleUnitViewRegistry` | BATTLE.md «Представление» |
| Анимации | `UnitMovementAnimator`, `UnitCombatAnimator`, `UnitDeathAnimator`, доставка способностей из данных | BATTLE.md |
| Масштаб фигур и погибшие пары | `texture_scale()`, `unit_visual_profiles.json`, `content/authored/assets/corpses/` по basename | BATTLE.md «Масштаб фигур», [../tools/UNITS.md](../tools/UNITS.md) |
| HP юнитов и раскрытие по Alt | `battle_health_display_controller.gd`, `user://battle_ui_settings.cfg` | BATTLE.md «Представление» |
| Подсветки | Радиус дальней атаки, маркеры непроходимости/поверхности/стоимости | BATTLE.md |
| Боевой лог | `BattleLogFormatter`, панель HUD | BATTLE.md «Боевой лог» |
| Варианты HUD | `UILayoutDocument`, `UILayoutStore`, `UILayoutPresenter` | BATTLE.md «Сохраняемые варианты HUD» |
| Фоны и высота поля | `BattleBackdrops`, `HexStateArt`, `grid_offset_y`, `battle_grid_layout.cfg` | BATTLE.md, EDITOR.md |
| Скорость показа | `BattlePlaybackSettings`, активные Tween | [SIMULATION_AND_PLAYBACK.md](SIMULATION_AND_PLAYBACK.md) |
| Файловая диагностика | `features/battle/diagnostics/`, JSONL за флагом `feature_flags/battle_file_logging` (в коде по умолчанию выключен, в `project.godot` сейчас включён) | BATTLE.md, [../tools/BATTLE_FILE_LOGGING.md](../tools/BATTLE_FILE_LOGGING.md) |

### Без графики и инструменты

| Возможность | Основные классы | Контракт |
| --- | --- | --- |
| Headless-бой | `SimulationRunner` с лимитами и cancellation token | SIMULATION_AND_PLAYBACK.md |
| Кампания из боёв | `CampaignSession`, `CampaignSimulationRunner`, проверка замкнутого графа сценариев | SIMULATION_AND_PLAYBACK.md, CONTENT_AND_MODS.md |
| Редактор поля | `BattleEditorShell`, `BattleEditorInspector`, `EditCommand`, undo/redo, JSON, именованные поля, пробный бой | EDITOR.md, [../tools/BATTLES.md](../tools/BATTLES.md) |
| Редактор юнитов | `tools/units/`, `UnitLibrary` | EDITOR.md, ../tools/UNITS.md |
| Редактор навыков | `tools/skills/`, `SkillLibrary` | EDITOR.md, [../tools/SKILLS.md](../tools/SKILLS.md) |
| Редактор UI боя | `tools/battle_ui/` | EDITOR.md, [../tools/BATTLE_UI.md](../tools/BATTLE_UI.md) |
| Общий интерфейс инструментов | `tools/common/editor_ui.gd` | EDITOR.md «Интерфейс инструментов» |
| Игровая сборка | Профиль `Windows Game` в `export_presets.cfg` без tools, docs и тестов | [../tools/README.md](../tools/README.md) |
| Автотесты | `tools/tests/run_tests.py`: battle smoke, editor smoke, regression | `AGENTS.md` «Проверка изменений» |

## Реализовано частично

| Область | Что есть | Чего ещё нет |
| --- | --- | --- |
| Моды | Внутренние Resource-пакеты, зависимости, замороженный `ModAPI` | Установка и загрузка внешнего JSON/ZIP/PCK-пакета, отдельный data-only путь |
| Экспорт редактора | `manifest.json` и `battle_document.json` в `content/authored/exports/` | Обратный импорт через `ContentLoader`; экспорт не является устанавливаемым модом |
| Кампания | Бои, переходы по победе/поражению, проверка графа | Глобальная карта, Фобос/другие базы, сложные условия, постоянный состав и `SaveService` |
| Юниты | Здоровье, ход, базовая атака, способности, восемь статусов, броня, пассивы | Экипировка, травмы, полноценные stat modifiers, инициатива. Непустые `facing`, `modifiers`, `character_binding` расстановки только дают предупреждение |
| Редакторы | Карта, гексы, препятствия, расстановки, стороны, ИИ, юниты, навыки, HUD, save/load/export/trial | Полный UI целей, зон, триггеров, кампаний, глобальной карты и диалогов; шаблоны карт и массовые операции |
| Симуляция | Один бой и последовательность кампании, `SimulationRunResult.to_report()` | Batch-runner, агрегаты, JSON/CSV серии, журнал команд headless-прогона |
| Диагностика | JSONL-лог графического боя | Подключение к `SimulationRunner` и проигрыватель записи |
| Presentation | События, скорость активных Tween, локальные fallback | Универсальный skip/cancel всех операций, звук, единый clock для VFX, покадровые спрайт-листы |
| ContentLock | Версии пакетов и SHA-256 канонических свойств: ID, характеристики, параметры эффектов | Байтовая идентичность внешних изображений и сцен |

## Ограничения и технический долг

- **Команда способности не транзакционна.** `AbilityExecutor` расходует действие и КД до исполнения обработчиков; `AbilityEffectHandler` возвращает только события, без структурированной ошибки. Встроенные обработчики проверяют предусловия заранее. Сторонний обработчик, упавший после изменения состояния, оставит частичный эффект: атомарность `MapMutationService` защищает только пакет карты. До публичных модов нужен контракт: планирование эффектов с последующим commit либо результат ошибки с аварийной остановкой.
- **Результат боя не привязан к запуску кампании.** `CampaignSession.complete_battle()` сверяет результат с текущим сценарием только по `battle_id`; `BattleResult` не содержит ID запуска. Если два сценария используют один бой, повторно переданный результат первого продвинет второй без его исполнения. Синхронный runner результат дважды не передаёт; риск появится с UI кампании, сохранениями и повтором боя. Нужны корреляция запуска с результатом и однократное потребление. Отложено решением владельца ([DECISIONS.md](../DECISIONS.md)).
- **Выключенный в продовых сборках флаг диагностики не обеспечен конфигурацией.** По решению владельца `feature_flags/battle_file_logging` в продовых сборках всегда `false`, но экспорт берёт значение из `project.godot`, где флаг сейчас `true`, и отдельного переопределения для релиза нет.
- **Стартовые настройки сохраняются без защиты записи.** `GameContentSettings._select()` записывает `content/game_content.tres` прямым `ResourceSaver.save`, без временного файла и `.bak`, в отличие от авторских JSON. Сбой записи не воспроизводился.
- `ContentLoader` работает с доверенными Godot `Resource`; это не безопасный загрузчик внешних архивов. `ModAPI` не является песочницей для исполняемого кода.
- `HexStateCatalog` (`features/battle/map/hex_state_catalog.gd`) — встроенный каталог. Перенос в content packages и формула совмещения стоимости местности/состояния не выполнены.
- `UnitLibrary.ACTIVE_ABILITIES` — встроенный список активных умений для редактора юнитов; новое встроенное умение нужно добавить в него вручную.
- `BattleMapAssembler` — legacy-адаптер старого `TileMapLayer`. Новые зависимости на него не добавляются; удаление требует проверки миграционных сценариев.
- `BattleController` (около 820 строк) — графический координатор выбора действия и цикла ИИ. Правила в нём не размещать; первым кандидатом на выделение является выбор действия.
- `BattleEditorShell` (около 1500 строк) координирует workflow; правая панель вынесена в `BattleEditorInspector`, тема — в `EditorUi`, инструменты — в `EditorToolBar`. Файловые сервисы, renderers и новые доменные правила выносить, а не наращивать shell.
- Presentation-определения входят в общий `ContentSnapshot`, но логика боя их не читает. Headless-запуск обязан оставаться корректным без графических ресурсов.
- ИИ `basic_melee` выбирает цель по расстоянию, прогнозирует одно перемещение и одно основное действие, берёт первое подходящее умение по порядку, а призыв ставит на первый допустимый гекс. Атаки противников, будущие изменения поля и групповая тактика не учитываются.
- Графический цикл автоматических команд ограничен 128 подряд и останавливается с явной ошибкой. Длительный бой двух ИИ прогоняется через `SimulationRunner`.
- Порядок ходов определяется порядком расстановок; инициативы нет.
- Удаление гекса с живым юнитом и превращение его в непроходимый отклоняются; погибшие не блокируют мутации.
- Сохранение посреди боя не принято как требование.

## Ближайшие архитектурные направления

Порядок определяется конкретной следующей фичей, но безопасные границы такие:

1. Для внешних модов — import/migration/validation конвейер поверх текущего `ContentSnapshot` и контракт ошибок обработчиков эффектов.
2. Для развития редактора — расширять `BattleDocument` и `EditCommand`, не хранить данные только в UI-нодах.
3. Для кампании — отделить постоянное `CampaignSession` от определений, привязать результат к запуску и добавить `SaveService` с `ContentLock`.
4. Для глубины боя — вводить runtime-состояния способностей/статусов в ядре, не в `UnitActor`.
5. Для балансировки — добавить batch-runner и отчёты поверх одного `SimulationRunner`.
6. Для skip/pause — определить отменяемый контракт presentation до добавления кнопки.

## Граница проверки

Автоматический набор: `python tools/tests/run_tests.py --godot <путь-к-Godot-4.7>`. Runner проверяет код завершения, итог, минимальное число проверок каждого набора и отсутствие ошибок в журнале. Компиляция всех скриптов: `--headless --path . --script tools/tests/check_scripts.gd`.

Автотесты и рендеры, выполненные агентами, не подтверждают:

- полный ручной бой мышью и интерактивные действия в редакторах;
- работу файловых диалогов и закрытие окна;
- физическое удержание Alt и наведение на подсказки;
- визуальную читаемость всех экранов при 1280×720;
- исполняемый EXE: установлены шаблоны экспорта 4.2.2, для 4.7 нужны новые; проверялся только PCK.
