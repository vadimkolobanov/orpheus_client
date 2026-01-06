# Orpheus Client (Flutter) — документация

Эта папка содержит **актуальную** документацию именно по Flutter-клиенту.

## Содержание
- **Обзор проекта (клиент)**: `docs/PROJECT_OVERVIEW.md`
- **Структура проекта (файл → ответственность)**: `docs/PROJECT_STRUCTURE.md`
- **Философия проекта**: `docs/PHILOSOPHY.md`
- **Установка и запуск**: `docs/GETTING_STARTED.md`
- **Гайд для разработки**: `docs/DEVELOPMENT_GUIDE.md`
- **Принципы работы функционала**: `docs/FUNCTIONAL_PRINCIPLES.md`
- **Тестирование**: `docs/testing/README.md`
- **Релизы**: `docs/RELEASES.md`
- **Архитектура**: `docs/ARCHITECTURE.md`
- **Особенности/плюсы/недоработки**: `docs/FEATURES_AND_LIMITATIONS.md`
- **Безопасность (обзор проблем и приоритетов)**: `docs/SECURITY_REVIEW.md`
- **Решения (ADR)**: `docs/DECISIONS/`
- **Миграция домена**: `docs/DOMAIN_MIGRATION_orpheus.click.md`
- **Архив** (не для ежедневной работы): `docs/_archive/`

## Процесс изменений
- Если меняется поведение приложения/контракты — обновляйте тесты (они диктуют поведение).
- Если меняется публичное поведение/UX — обновляйте документацию в `docs/`.
- `AI_WORKLOG.md` — это журнал, не заменяет документацию.

## Release notes / changelog
- Публичные release notes ведём в админ-панели `OPHEUS_ADMIN` → раздел **"Версии"** (`app_versions`).
- `CHANGELOG.md` в этом репозитории — внутренний журнал разработки.

