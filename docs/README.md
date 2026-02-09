# Orpheus Client (Flutter) — документация

Эта папка содержит **актуальную** документацию именно по Flutter-клиенту.

## Содержание

### Для разработчика
- **Обзор проекта (клиент)**: `docs/PROJECT_OVERVIEW.md`
- **Структура проекта (файл → ответственность)**: `docs/PROJECT_STRUCTURE.md`
- **Философия проекта**: `docs/PHILOSOPHY.md`
- **Установка и запуск**: `docs/GETTING_STARTED.md`
- **Гайд для разработки**: `docs/DEVELOPMENT_GUIDE.md`
- **Принципы работы функционала**: `docs/FUNCTIONAL_PRINCIPLES.md`
- **Тестирование**: `docs/testing/README.md`
- **Архитектура**: `docs/ARCHITECTURE.md`
- **Особенности/плюсы/недоработки**: `docs/FEATURES_AND_LIMITATIONS.md`
- **Безопасность (обзор проблем и приоритетов)**: `docs/SECURITY_REVIEW.md`
- **Решения (ADR)**: `docs/DECISIONS/`

### База знаний AI (для пользователей)
- **Что такое Orpheus**: `docs/ai_kb/01-what-is-orpheus.md`
- **Быстрый старт**: `docs/ai_kb/02-getting-started.md`
- **Приватность и безопасность**: `docs/ai_kb/03-privacy-security.md`
- **Возможности**: `docs/ai_kb/04-features.md`
- **FAQ**: `docs/ai_kb/05-faq.md`
- **Troubleshooting**: `docs/ai_kb/06-troubleshooting.md`
- **Поддержка**: `docs/ai_kb/07-support-and-bug-report.md`
- **Режимы безопасности**: `docs/ai_kb/08-security-modes.md`
- **Экран Система**: `docs/ai_kb/09-system-screen.md`
- **Комнаты**: `docs/ai_kb/10-rooms.md`
- **История обновлений**: `docs/ai_kb/11-release-history.md`
- **README (правила KB)**: `docs/ai_kb/README.md`

### Архив
- **Архив** (не для ежедневной работы): `docs/_archive/`

## Процесс изменений
- Если меняется поведение приложения/контракты — обновляйте тесты (они диктуют поведение).
- Если меняется публичное поведение/UX — обновляйте документацию в `docs/` и `docs/ai_kb/`.
- `AI_WORKLOG.md` — это журнал, не заменяет документацию.

## Release notes / changelog
- Публичные release notes на сайте: [orpheus.click/changelog](https://orpheus.click/changelog).
- История обновлений для пользователей: `docs/ai_kb/11-release-history.md`.
- `CHANGELOG.md` в этом репозитории — внутренний журнал разработки.
