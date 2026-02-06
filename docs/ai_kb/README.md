# База знаний для AI‑агента (пользовательская)

Эта папка — **источник MD‑файлов**, которые можно загружать в базу знаний AI‑агента (например, Timeweb Cloud AI‑agents → Knowledge Base).

## Цель
- Дать AI‑агенту **корректные, актуальные и безопасные** ответы для пользователей.
- Не смешивать user‑документацию с dev/infra/секьюрити‑внутрянкой.

## Что загружать в базу знаний
Рекомендуется загружать **только** файлы из `docs/ai_kb/`:
- `01-what-is-orpheus.md`
- `02-getting-started.md`
- `03-privacy-security.md`
- `04-features.md`
- `05-faq.md`
- `06-troubleshooting.md`
- `07-support-and-bug-report.md`
- `08-security-modes.md`
- `09-system-screen.md`
- `10-rooms.md`
- `12-notes-vault.md`

## Что НЕ загружать (важно)
Эти документы полезны разработке, но **не должны** попадать в базу знаний для пользователей:
- `docs/SECURITY_REVIEW.md` — содержит внутренние уязвимости/приоритеты (риск злоупотреблений).
- `docs/FUNCTIONAL_PRINCIPLES.md`, `docs/ARCHITECTURE.md`, `docs/PROJECT_STRUCTURE.md`, `docs/DECISIONS/*` — технические детали, внутренние контракты, эндпоинты.
- `docs/DOMAIN_MIGRATION_orpheus.click.md` — инфраструктурные планы/домены/пути миграции.
- `docs/testing/*`, `docs/TESTING_GAPS.md`, `docs/COMMIT_PROCESS.md`, `docs/DEVELOPMENT_GUIDE.md` — внутренние процессы.

## Правила обновления (чтобы база знаний не “врала”)
- Любые изменения публичного поведения/UX → обновляйте соответствующий файл в `docs/ai_kb/`.
- Не обещайте пользователю то, чего проект не гарантирует (см. `03-privacy-security.md`).
- Не добавляйте в KB:
  - токены, ключи, креды, внутренние URL;
  - подробности о слабых местах и обходах (это для внутренних security‑доков).

