---
alwaysApply: true
---

# Cursor rules (orpheus_client) — артефакты и документация

## Когда артефакты обязательны
Если изменяются любые из:
- `lib/**`
- `test/**`
- `android/**`
- `assets/**`
- `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`

то **обязательно**:
- обновить `CHANGELOG.md` (секция `[Unreleased]`)
- добавить запись в `AI_WORKLOG.md`

## Документация
- Если меняется поведение/UX/контракты/процесс — обнови `docs/**`.
- `AI_WORKLOG.md` — журнал “что сделано”, он **не заменяет** `docs/**`.

## Release notes (“Что нового”)
- Публичный “Что нового” ведём **в админке**: `OPHEUS_ADMIN` → **Версии** (`app_versions`).
- В клиенте (`AppConfig.changelogData`) — только fallback/offline-safe и **не обновляется вручную**.

## Формат записи AI_WORKLOG
Каждая запись включает:
- Date, Time (local)
- Task (кратко)
- Changes (список)
- Files (список путей)
- Commands (что реально запускалось)
 
