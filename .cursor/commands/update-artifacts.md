# Command: update-artifacts (orpheus_client)

Цель: синхронизировать артефакты процесса под последние изменения.

## Шаги
1. Посмотри изменения:
   - `git status`
   - `git diff --name-only`
2. Если менялись `lib/`, `test/`, `android/`, `assets/`, `pubspec.*`, `analysis_options.yaml`:
   - Обнови `CHANGELOG.md` → секция `[Unreleased]` (коротко, пользовательским языком).
   - Обнови `AI_WORKLOG.md` → новая запись (Date/Time/Task/Changes/Files/Commands).
3. Если меняется поведение/инструкции — обнови `docs/**`.
4. Если изменение пользовательское (“Что нового”) — напомни: единый источник в `OPHEUS_ADMIN` → “Версии”.

## Критерий готовности
- `CHANGELOG.md` и `AI_WORKLOG.md` отражают изменения.
- Нет “забытых” файлов (untracked) в `git status`.
# Update artifacts (docs/changelog/worklog)

Проверь, что после последних изменений обновлены артефакты процесса:

1) `CHANGELOG.md` — секция `## [Unreleased]` (Added/Changed/Fixed/Removed)
2) `AI_WORKLOG.md` — новая запись (дата/время, задача, что сделано, файлы, команды)
3) `docs/*` — если менялось поведение/инструкции/архитектура
4) `OPHEUS_ADMIN` → "Версии" — обновлены публичные release notes (если изменения видны пользователям)

Если чего-то не хватает — внеси минимальные правки и покажи итог.


