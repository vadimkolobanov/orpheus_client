# Command: commit-ready (orpheus_client)

Цель: подготовить коммит (без `git commit`), убедиться что всё готово.

## Чеклист
1. Проверки (по необходимости):
   - `flutter test`
   - `flutter analyze`
2. Артефакты:
   - `CHANGELOG.md` обновлён (`[Unreleased]`)
   - `AI_WORKLOG.md` обновлён (есть новая запись)
   - `docs/**` обновлены при изменении поведения/процесса
3. Git:
   - `git status` без “сюрпризов”
   - все нужные файлы отслеживаются

## Предложи сообщение коммита
Формат: `type(client): краткое описание`
- `feat` / `fix` / `docs` / `chore` / `refactor` / `test`

Пример:
- `fix(client): стабилизирован reconnect WebSocket при фейле хоста`
# Commit ready

Подготовь изменения к коммиту (без выполнения интерактивных действий):

1) Проверь staged/unstaged изменения и кратко суммируй.
2) Убедись, что обновлены:
   - `CHANGELOG.md` (Unreleased)
   - `AI_WORKLOG.md`
   - `docs/*` (если нужно)
3) Предложи commit message в формате Conventional Commits:
   - `feat(client): ...`
   - `fix(client): ...`
   - `docs(client): ...`
   - `chore(client): ...`
4) Дай команды проверки (пример):
   - `flutter analyze`
   - `flutter test` или `.\test_runner.ps1`


