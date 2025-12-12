# AI_WORKLOG

Журнал действий ИИ/агента в этом репозитории.

Правило: если меняется код/конфиги/поведение — добавляй запись сюда **и** обновляй `CHANGELOG.md` (секция `Unreleased`).

---

## 2025-12-12
- Time: 00:00 local
- Task: Инициализация процесса разработки (Cursor rules/commands, docs, hooks)
- Changes:
  - Добавлены шаблоны документации и журналов.
  - Добавлены правила/команды Cursor для дисциплины артефактов.
  - Добавлен git hook, который не даст забыть обновить `CHANGELOG.md`/`AI_WORKLOG.md`.
- Files:
  - `CHANGELOG.md`
  - `AI_WORKLOG.md`
  - `docs/README.md`
  - `docs/ARCHITECTURE.md`
  - `docs/DECISIONS/0001-ai-process.md`
  - `.cursor/rules/*`
  - `.cursor/commands/*`
  - `.githooks/pre-commit`
  - `scripts/install-hooks.ps1`
  - `.gitignore`
- Commands:
  - `powershell -ExecutionPolicy Bypass -File .\\scripts\\install-hooks.ps1`
  - `flutter pub get`
  - `flutter test` / `.\test_runner.ps1`


